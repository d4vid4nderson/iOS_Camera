import AVFoundation
import CoreImage
import SwiftUI

/// Owns the capture session. UI state is @Published and only touched on the main thread;
/// session work happens on `sessionQueue`, frames arrive on `videoQueue`.
final class CameraModel: NSObject, ObservableObject {
    enum Status: Equatable {
        case starting
        case running
        case unauthorized
        case failed(String)
    }

    static let rollLength = 36

    @Published private(set) var status: Status = .starting
    @Published var stock: FilmStock = .classic400 {
        didSet { renderer.stock = stock }
    }
    @Published private(set) var exposureBias: Float = 0
    @Published private(set) var framesShot = 0
    @Published private(set) var lastPrint: UIImage?
    @Published private(set) var shutterBlink = false
    @Published private(set) var developing = 0
    @Published var message: String?

    var rollFinished: Bool { framesShot >= Self.rollLength }

    let renderer = PreviewRenderer()

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "retrocam.session")
    private let videoQueue = DispatchQueue(label: "retrocam.video", qos: .userInteractive)
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()

    // Session-queue state.
    private var isConfigured = false
    private var input: AVCaptureDeviceInput?
    private var position: AVCaptureDevice.Position = .back
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var sessionExposureBias: Float = 0
    private var inFlight: [Int64: PhotoCaptureProcessor] = [:]

    override init() {
        super.init()
        renderer.stock = stock
    }

    // MARK: - Lifecycle

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { self.run() } else { self.status = .unauthorized }
                }
            }
        default:
            status = .unauthorized
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    private func run() {
        sessionQueue.async {
            if !self.isConfigured {
                do {
                    try self.configure()
                    self.isConfigured = true
                } catch {
                    DispatchQueue.main.async { self.status = .failed(error.localizedDescription) }
                    return
                }
            }
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async { self.status = .running }
        }
    }

    private func configure() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo   // 4:3, matches the viewfinder
        try attachCamera(at: .back)

        guard session.canAddOutput(videoOutput) else { throw CameraError.setupFailed("video output") }
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        session.addOutput(videoOutput)

        guard session.canAddOutput(photoOutput) else { throw CameraError.setupFailed("photo output") }
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality

        updateConnections()
    }

    private func attachCamera(at position: AVCaptureDevice.Position) throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw CameraError.noCamera
        }
        let newInput = try AVCaptureDeviceInput(device: device)
        if let input { session.removeInput(input) }
        guard session.canAddInput(newInput) else {
            if let input { session.addInput(input) }
            throw CameraError.setupFailed("camera input")
        }
        session.addInput(newInput)
        input = newInput
        self.position = position
        rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
    }

    /// Portrait viewfinder; mirror it for selfies.
    private func updateConnections() {
        guard let connection = videoOutput.connection(with: .video) else { return }
        if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = (position == .front)
        }
    }

    // MARK: - Controls

    func flipCamera() {
        sessionQueue.async {
            guard self.isConfigured else { return }
            let next: AVCaptureDevice.Position = self.position == .back ? .front : .back
            self.session.beginConfiguration()
            do {
                try self.attachCamera(at: next)
            } catch {
                DispatchQueue.main.async { self.message = error.localizedDescription }
            }
            self.updateConnections()
            self.session.commitConfiguration()
            self.applyExposureBias()
        }
    }

    func nudgeExposure(by stops: Float) {
        let value = (exposureBias + stops).clamped(to: -2...2)
        let snapped = (value * 3).rounded() / 3   // 1/3-stop clicks, like a real dial
        exposureBias = snapped
        sessionQueue.async {
            self.sessionExposureBias = snapped
            self.applyExposureBias()
        }
    }

    /// Session queue only.
    private func applyExposureBias() {
        guard let device = input?.device else { return }
        let clamped = sessionExposureBias.clamped(to: device.minExposureTargetBias...device.maxExposureTargetBias)
        do {
            try device.lockForConfiguration()
            device.setExposureTargetBias(clamped)
            device.unlockForConfiguration()
        } catch {}
    }

    /// `point` is normalised (0...1) in the portrait viewfinder.
    func focus(at point: CGPoint) {
        sessionQueue.async {
            guard let device = self.input?.device else { return }
            // Sensor coordinates are landscape; rotate (and un-mirror for the front camera).
            let devicePoint = self.position == .front
                ? CGPoint(x: point.y, y: point.x)
                : CGPoint(x: point.y, y: 1 - point.x)
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = .continuousAutoFocus
                }
                if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = .continuousAutoExposure
                }
                device.unlockForConfiguration()
            } catch {}
        }
    }

    func rewindRoll() {
        framesShot = 0
    }

    // MARK: - Capture

    func shoot() {
        guard status == .running, !rollFinished else { return }
        let stock = self.stock

        framesShot += 1
        developing += 1
        shutterBlink = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { self.shutterBlink = false }

        sessionQueue.async {
            if let connection = self.photoOutput.connection(with: .video),
               let angle = self.rotationCoordinator?.videoRotationAngleForHorizonLevelCapture,
               connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }

            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .balanced
            let id = settings.uniqueID

            let processor = PhotoCaptureProcessor(stock: stock) { [weak self] result in
                guard let self else { return }
                self.sessionQueue.async { self.inFlight[id] = nil }
                DispatchQueue.main.async { self.finish(result) }
            }
            self.inFlight[id] = processor
            self.photoOutput.capturePhoto(with: settings, delegate: processor)
        }
    }

    private func finish(_ result: Result<Darkroom.Print, Error>) {
        switch result {
        case .success(let print):
            lastPrint = print.thumbnail
            Task {
                do {
                    try await Darkroom.saveToLibrary(print.jpeg)
                } catch {
                    await MainActor.run { self.message = error.localizedDescription }
                }
                await MainActor.run { self.developing -= 1 }
            }
        case .failure(let error):
            developing -= 1
            framesShot = max(0, framesShot - 1)   // didn't expose, give the frame back
            message = error.localizedDescription
        }
    }
}

// MARK: - Live frames

extension CameraModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        renderer.push(CIImage(cvPixelBuffer: pixelBuffer))
    }
}

// MARK: - Still capture

private final class PhotoCaptureProcessor: NSObject, AVCapturePhotoCaptureDelegate {
    private let stock: FilmStock
    private let completion: (Result<Darkroom.Print, Error>) -> Void
    private var photoData: Data?

    init(stock: FilmStock, completion: @escaping (Result<Darkroom.Print, Error>) -> Void) {
        self.stock = stock
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if error == nil { photoData = photo.fileDataRepresentation() }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error {
            completion(.failure(error))
            return
        }
        guard let data = photoData else {
            completion(.failure(CameraError.processingFailed))
            return
        }
        let stock = self.stock
        let completion = self.completion
        DispatchQueue.global(qos: .userInitiated).async {
            completion(Result { try Darkroom.develop(data, stock: stock) })
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
