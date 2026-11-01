import AVFoundation
import CoreImage
import SwiftUI

/// Owns the capture session. UI state is @Published and only touched on the main thread;
/// session work happens on `sessionQueue`, frames arrive on `videoQueue`.
/// Flash setting for the next shot.
enum FlashSetting: String, CaseIterable {
    case off, auto, on

    var label: String { rawValue.uppercased() }
    var mode: AVCaptureDevice.FlashMode {
        switch self {
        case .off: return .off
        case .auto: return .auto
        case .on: return .on
        }
    }
    var next: FlashSetting {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

final class CameraModel: NSObject, ObservableObject {
    enum Status: Equatable {
        case starting
        case running
        case unauthorized
        case failed(String)
    }

    static let rollLength = 36
    /// GRAIN control: multiplier on the film's own grain, in 25% clicks.
    static let grainLevels = stride(from: 0.0, through: 2.0, by: 0.25).map { $0 }
    private static let grainLevelKey = "grainLevel"
    private static let flashKey = "flash"
    private static let stampKey = "stamp"
    private static let borderKey = "border"
    private static let borderWidthKey = "borderWidth"
    private static let filmKey = "film.selected"
    private static func lensKey(_ position: AVCaptureDevice.Position) -> String {
        position == .front ? "lensFocal.front" : "lensFocal.back"
    }

    @Published private(set) var status: Status = .starting
    /// Built-in and saved films, plus per-film adjustments. Persisted on every change.
    @Published private(set) var library = FilmLibrary.load() {
        didSet { library.save() }
    }
    /// The film loaded right now, including any adjustments.
    @Published private(set) var stock: FilmStock = {
        let id = UserDefaults.standard.string(forKey: CameraModel.filmKey) ?? FilmStock.classic400.id
        return FilmLibrary.load().current(id: id) ?? .classic400
    }() {
        didSet {
            renderer.stock = developedStock
            if stock.id != oldValue.id { UserDefaults.standard.set(stock.id, forKey: Self.filmKey) }
        }
    }
    @Published private(set) var grainLevel: Double = {
        let saved = UserDefaults.standard.object(forKey: CameraModel.grainLevelKey) as? Double
        return saved.map { min(max($0, 0), 2) } ?? 1
    }() {
        didSet {
            UserDefaults.standard.set(grainLevel, forKey: Self.grainLevelKey)
            renderer.stock = developedStock
        }
    }
    @Published private(set) var exposureBias: Float = 0
    @Published private(set) var flash: FlashSetting =
        FlashSetting(rawValue: UserDefaults.standard.string(forKey: CameraModel.flashKey) ?? "") ?? .off {
        didSet { UserDefaults.standard.set(flash.rawValue, forKey: Self.flashKey) }
    }
    /// Whether the current camera has a flash (asked from the phone, per side).
    @Published private(set) var flashAvailable = false
    @Published private(set) var border: BorderStyle =
        BorderStyle(rawValue: UserDefaults.standard.string(forKey: CameraModel.borderKey) ?? "") ?? .none {
        didSet {
            UserDefaults.standard.set(border.rawValue, forKey: Self.borderKey)
            renderer.border = border
        }
    }
    /// Border width as a fraction of the print's short side (whole percent steps).
    @Published private(set) var borderWidth: Double = {
        let saved = UserDefaults.standard.object(forKey: CameraModel.borderWidthKey) as? Double
        return min(max(saved ?? PrintBorder.defaultWidth, PrintBorder.widthRange.lowerBound),
                   PrintBorder.widthRange.upperBound)
    }() {
        didSet {
            UserDefaults.standard.set(borderWidth, forKey: Self.borderWidthKey)
            renderer.borderWidth = borderWidth
        }
    }
    @Published private(set) var stampMode: StampMode =
        StampMode(rawValue: UserDefaults.standard.string(forKey: CameraModel.stampKey) ?? "") ?? .date {
        didSet {
            UserDefaults.standard.set(stampMode.rawValue, forKey: Self.stampKey)
            renderer.stampMode = stampMode
        }
    }
    /// Lenses this phone can offer for the current camera side (discovered at runtime).
    @Published private(set) var lenses: [LensOption] = []
    @Published private(set) var lens: LensOption?
    @Published private(set) var framesShot = 0
    @Published private(set) var lastPrint: UIImage?
    @Published private(set) var shutterBlink = false
    @Published private(set) var developing = 0
    @Published var message: String?
    /// How far to turn on-screen icons (degrees, clockwise) so they stay level when the
    /// phone is turned. The screen itself stays portrait.
    @Published private(set) var uiRotation: Double = 0
    /// Camera orientation readout for troubleshooting (long-press the frame counter).
    @Published private(set) var diagnostics: String?
    var showDiagnostics = false {
        didSet { if !showDiagnostics { diagnostics = nil } }
    }

    var rollFinished: Bool { framesShot >= Self.rollLength }

    /// The selected film with the GRAIN setting applied; used for preview and capture alike.
    var developedStock: FilmStock { stock.withGrain(scaledBy: grainLevel) }

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
    /// Follows the back camera, whatever camera is active, to tell how the phone is turned.
    private var levelCoordinator: AVCaptureDevice.RotationCoordinator?
    private var levelObservation: NSKeyValueObservation?
    /// The angle the live-frame connection should use with the phone upright.
    private var previewAngle: CGFloat = 90
    private var frameCount = 0
    private var sessionExposureBias: Float = 0
    private var inFlight: [Int64: PhotoCaptureProcessor] = [:]

    override init() {
        super.init()
        renderer.stock = developedStock
        renderer.stampMode = stampMode
        renderer.border = border
        renderer.borderWidth = borderWidth
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
                    // configure() has committed by now, so the connections are final.
                    self.updateConnections()
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
        if let back = input?.device { trackPhoneRotation(with: back) }

        guard session.canAddOutput(videoOutput) else { throw CameraError.setupFailed("video output") }
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        session.addOutput(videoOutput)

        guard session.canAddOutput(photoOutput) else { throw CameraError.setupFailed("photo output") }
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality

        refreshLenses()
    }

    /// The richest camera this phone has on that side. On the back, a virtual multi-camera
    /// device lets one zoom factor move across ultra-wide, main and telephoto.
    private static func bestDevice(at position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let preference: [AVCaptureDevice.DeviceType] = position == .back
            ? [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
            : [.builtInWideAngleCamera]
        for type in preference {
            if let device = AVCaptureDevice.default(type, for: .video, position: position) { return device }
        }
        return nil
    }

    private static func megapixels(_ format: AVCaptureDevice.Format) -> Double {
        let best = format.supportedMaxPhotoDimensions.map { Double($0.width) * Double($0.height) }.max()
        return (best ?? 12_000_000) / 1_000_000
    }

    /// Describe the physical cameras behind `device` from what the phone reports:
    /// field of view -> focal length, switch-over zoom factors, and photo size.
    private static func physicalCameras(of device: AVCaptureDevice) -> [PhysicalCamera] {
        let baseFocal = LensPlanner.equivalentFocalLength(
            horizontalFieldOfView: Double(device.activeFormat.videoFieldOfView))
        let outputLimit = megapixels(device.activeFormat)
        let members = (device.isVirtualDevice ? device.constituentDevices : [device])
            .sorted { $0.activeFormat.videoFieldOfView > $1.activeFormat.videoFieldOfView }  // widest first
        let zooms = [1.0] + device.virtualDeviceSwitchOverVideoZoomFactors.map { $0.doubleValue }
        return zip(members, zooms).map { member, zoom in
            PhysicalCamera(focalLength: baseFocal * zoom,
                           megapixels: min(megapixels(member.activeFormat), outputLimit),
                           zoomFactor: zoom)
        }
    }

    private func attachCamera(at position: AVCaptureDevice.Position) throws {
        guard let device = Self.bestDevice(at: position) else {
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

    /// Session queue only. Work out this side's lenses and select the remembered one.
    private func refreshLenses() {
        guard let device = input?.device else { return }
        let options = LensPlanner.lenses(for: Self.physicalCameras(of: device))
        let saved = UserDefaults.standard.object(forKey: Self.lensKey(position)) as? Int
        let chosen = LensPlanner.defaultLens(in: options, preferred: saved)
        if let chosen { applyZoom(chosen.zoomFactor) }
        DispatchQueue.main.async {
            self.lenses = options
            self.lens = chosen
        }
    }

    /// Session queue only.
    private func applyZoom(_ factor: Double) {
        guard let device = input?.device else { return }
        let zoom = CGFloat(factor).clamped(to: device.minAvailableVideoZoomFactor...device.maxAvailableVideoZoomFactor)
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = zoom
            device.unlockForConfiguration()
        } catch {}
    }

    // MARK: - Films

    /// Load a film (with the adjustments last made to it, if any).
    func selectFilm(id: String) {
        guard let film = library.current(id: id) else { return }
        stock = film
    }

    var isFilmEdited: Bool { library.isEdited(id: stock.id) }

    /// Adjust the loaded film. The change is remembered for this film until reset or saved.
    func adjustFilm(_ change: (inout FilmStock) -> Void) {
        var film = stock
        change(&film)
        guard film != stock else { return }
        stock = film
        library.setEdit(film)
    }

    /// Back to the film as shipped (or as last saved).
    func resetFilm() {
        library.reset(id: stock.id)
        if let original = library.original(id: stock.id) { stock = original }
    }

    /// Save the loaded film, adjustments and all, as a new film of the user's own and load it.
    func saveFilm(named name: String) {
        let sourceID = stock.id
        let film = library.saveNew(from: stock, named: name)
        library.reset(id: sourceID)   // the source film goes back to how it was
        stock = film
    }

    /// Write the adjustments into the loaded film (only for the user's own films).
    func updateSavedFilm() {
        guard stock.isCustom else { return }
        library.update(stock)
    }

    func renameFilm(id: String, to name: String) {
        library.rename(id: id, to: name)
        if stock.id == id, let film = library.current(id: id) { stock = film }
    }

    func deleteFilm(id: String) {
        library.delete(id: id)
        if stock.id == id { stock = library.current(id: FilmStock.classic400.id) ?? .classic400 }
    }

    func cycleFlash() { flash = flash.next }
    func cycleStamp() { stampMode = stampMode.next }
    func cycleBorder() { border = border.next }
    func selectBorder(_ style: BorderStyle) { border = style }

    /// Set the border width (fraction of the short side), snapped to whole percents.
    func setBorderWidth(_ width: Double) {
        let range = PrintBorder.widthRange
        let snapped = (min(max(width, range.lowerBound), range.upperBound) * 100).rounded() / 100
        if snapped != borderWidth { borderWidth = snapped }
    }

    /// Set the GRAIN multiplier, snapped to the nearest 25% click.
    func setGrainLevel(_ level: Double) {
        let snapped = Self.grainLevels.min { abs($0 - level) < abs($1 - level) } ?? 1
        if snapped != grainLevel { grainLevel = snapped }
    }

    func selectLens(_ option: LensOption) {
        guard option != lens else { return }
        lens = option
        sessionQueue.async {
            UserDefaults.standard.set(option.focalLength, forKey: Self.lensKey(self.position))
            self.applyZoom(option.zoomFactor)
        }
    }

    /// Portrait viewfinder; mirror it for selfies. Allow full-resolution photos so cropped
    /// lenses (35mm, 50mm...) keep real detail instead of upscaling a 12 MP frame.
    private func updateConnections() {
        if let device = input?.device,
           let largest = device.activeFormat.supportedMaxPhotoDimensions.max(by: {
               Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height)
           }) {
            photoOutput.maxPhotoDimensions = largest
        }
        let hasFlash = photoOutput.supportedFlashModes.contains(.on)
        DispatchQueue.main.async { self.flashAvailable = hasFlash }
        guard let connection = videoOutput.connection(with: .video) else { return }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = (position == .front)
        }
        levelPreview()
    }

    /// Session queue only. Point the live frames upright for a portrait screen.
    ///
    /// Not a fixed 90°: cameras are mounted differently (Apple notes the default angle
    /// differs between devices), so ask the camera's rotation coordinator. Its capture
    /// angle is level with gravity; take off however far the phone is turned from
    /// upright (measured on the back camera, which is the same for both sides) to get
    /// the angle for an upright, portrait screen.
    private func levelPreview() {
        guard let coordinator = rotationCoordinator,
              let connection = videoOutput.connection(with: .video) else { return }
        let turned = (levelCoordinator?.videoRotationAngleForHorizonLevelCapture ?? 90) - 90
        let angle = Self.normalized(coordinator.videoRotationAngleForHorizonLevelCapture - turned)
        previewAngle = angle
        if connection.videoRotationAngle != angle, connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }

    /// Session queue only. Watch how the phone is turned, to keep icons level and to
    /// re-level the preview whenever the phone is back upright.
    private func trackPhoneRotation(with backCamera: AVCaptureDevice) {
        let coordinator = AVCaptureDevice.RotationCoordinator(device: backCamera, previewLayer: nil)
        levelCoordinator = coordinator
        levelObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture,
                                               options: [.initial, .new]) { [weak self] coordinator, _ in
            // The back camera is level at 90° with the phone upright.
            let turned = CameraModel.normalized(coordinator.videoRotationAngleForHorizonLevelCapture - 90)
            DispatchQueue.main.async {
                guard let self else { return }
                // Turn icons the opposite way to the phone (signed, so they take the short way round).
                let icons = turned == 180 ? 180 : -Double(turned > 180 ? turned - 360 : turned)
                if icons != self.uiRotation { self.uiRotation = icons }
            }
            if turned == 0 {
                self?.sessionQueue.async { self?.levelPreview() }
            }
        }
    }

    /// An angle in 0..<360.
    private static func normalized(_ degrees: CGFloat) -> CGFloat {
        let r = degrees.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
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
            self.session.commitConfiguration()
            // After the commit: the new camera's connections only exist once the
            // configuration is committed. Setting rotation/mirroring before that
            // hit the outgoing connection and left the front camera landscape.
            self.updateConnections()
            self.refreshLenses()
            self.applyExposureBias()
        }
    }

    /// Step the GRAIN control one click up (+1) or down (-1).
    func nudgeGrain(by clicks: Int) {
        let levels = Self.grainLevels
        let current = levels.enumerated().min { abs($0.element - grainLevel) < abs($1.element - grainLevel) }?.offset ?? 4
        grainLevel = levels[min(max(current + clicks, 0), levels.count - 1)]
    }

    func nudgeExposure(by stops: Float) {
        setExposure(exposureBias + stops)
    }

    /// Set exposure compensation, snapped to 1/3-stop clicks within ±2 EV.
    func setExposure(_ stops: Float) {
        let snapped = (stops.clamped(to: -2...2) * 3).rounded() / 3   // 1/3-stop clicks, like a real dial
        guard snapped != exposureBias else { return }
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
        let stock = self.developedStock
        let flashMode = flashAvailable ? flash.mode : .off
        let stampText = stampMode.text(for: Date())
        let finish = PrintFinish(border: border, seed: UInt32.random(in: 0...UInt32.max), width: borderWidth)

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
            settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
            if flashMode != .off, self.photoOutput.supportedFlashModes.contains(flashMode) {
                settings.flashMode = flashMode
                // Flash shots stay at standard resolution: high-resolution capture and
                // flash aren't guaranteed to combine on every camera.
                if let standard = self.input?.device.activeFormat.supportedMaxPhotoDimensions
                    .filter({ Int($0.width) * Int($0.height) <= 12_600_000 })
                    .max(by: { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }) {
                    settings.maxPhotoDimensions = standard
                }
            }
            let id = settings.uniqueID

            let processor = PhotoCaptureProcessor(stock: stock, stampText: stampText, finish: finish) { [weak self] result in
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
        if showDiagnostics {
            frameCount += 1
            if frameCount % 15 == 0 {
                let side = connection.isVideoMirrored ? "FRONT" : "BACK"
                let text = "\(side)  conn \(Int(connection.videoRotationAngle))°  want \(Int(previewAngle))°  "
                    + "\(CVPixelBufferGetWidth(pixelBuffer))×\(CVPixelBufferGetHeight(pixelBuffer))"
                DispatchQueue.main.async { if self.showDiagnostics { self.diagnostics = text } }
            }
        }
    }
}

// MARK: - Still capture

private final class PhotoCaptureProcessor: NSObject, AVCapturePhotoCaptureDelegate {
    private let stock: FilmStock
    private let stampText: String?
    private let finish: PrintFinish
    private let completion: (Result<Darkroom.Print, Error>) -> Void
    private var photoData: Data?

    init(stock: FilmStock, stampText: String?, finish: PrintFinish,
         completion: @escaping (Result<Darkroom.Print, Error>) -> Void) {
        self.stock = stock
        self.stampText = stampText
        self.finish = finish
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
        let stampText = self.stampText
        let finish = self.finish
        let completion = self.completion
        DispatchQueue.global(qos: .userInitiated).async {
            completion(Result { try Darkroom.develop(data, stock: stock, stampText: stampText, finish: finish) })
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
