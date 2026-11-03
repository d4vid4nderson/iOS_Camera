import CoreImage
import MetalKit
import SwiftUI

/// Draws the live camera feed through the film look into an MTKView on the GPU.
final class PreviewRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let context: CIContext

    private let lock = NSLock()
    private var latestFrame: CIImage?

    /// Read on the main thread (where MTKView draws), written from the main thread.
    var stock: FilmStock = .classic400
    var stampMode: StampMode = .off
    var border: BorderStyle = .none
    var borderWidth: Double = PrintBorder.defaultWidth
    var format: FrameFormat = .medium645
    var orientation: FrameOrientation = .landscape
    /// The phone is held on its side: the screen's long side is level, so a landscape
    /// frame runs along it.
    var sideways = false
    /// Fixed per-session seed for textured borders, so the live view does not flicker.
    private let borderSeed = UInt32.random(in: 0...UInt32.max)

    override init() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            fatalError("Metal is not available on this device")
        }
        self.device = device
        self.commandQueue = queue
        self.context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false, .name: "preview"])
        super.init()
    }

    /// Called from the camera's video queue.
    func push(_ frame: CIImage) {
        lock.lock()
        latestFrame = frame
        lock.unlock()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        lock.lock()
        let frame = latestFrame
        lock.unlock()

        let target = view.drawableSize
        guard var frame, target.width > 0, target.height > 0,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        // Safety net: the camera connection should already deliver portrait frames. If a
        // camera still hands over landscape ones, turn them rather than show them sideways.
        if frame.extent.width > frame.extent.height {
            frame = frame.oriented(.right)
            frame = frame.transformed(by: CGAffineTransform(translationX: -frame.extent.minX, y: -frame.extent.minY))
        }

        // Aspect-fill the frame into the drawable, *then* develop it, so we only
        // process as many pixels as the screen shows.
        let scale = max(target.width / frame.extent.width, target.height / frame.extent.height)
        var image = frame.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        image = image.transformed(by: CGAffineTransform(
            translationX: (target.width - image.extent.width) / 2 - image.extent.minX,
            y: (target.height - image.extent.height) / 2 - image.extent.minY))
        let bounds = CGRect(origin: .zero, size: target)
        // The frame format, as the photo will be cut: the picture inside the viewfinder.
        let frameRect = format.rect(in: bounds, wide: (orientation == .landscape) != sideways)
        var picture = image.cropped(to: frameRect)
            .transformed(by: CGAffineTransform(translationX: -frameRect.minX, y: -frameRect.minY))
        let pictureBounds = CGRect(origin: .zero, size: frameRect.size)
        picture = FilmLook.apply(stock, to: picture, stamp: stampMode.text(for: Date())).cropped(to: pictureBounds)
        picture = PrintBorder.apply(border, to: picture, seed: borderSeed, width: borderWidth,
                                    label: SlideLabel(title: stock.name, number: nil, color: stock.color))
        // Fit it (a slide mount is bigger than the picture) in the middle, on black.
        let out = picture.extent
        let fit = min(bounds.width / out.width, bounds.height / out.height, 1)
        picture = picture.transformed(by: CGAffineTransform(scaleX: fit, y: fit))
        picture = picture.transformed(by: CGAffineTransform(
            translationX: (bounds.width - picture.extent.width) / 2 - picture.extent.minX,
            y: (bounds.height - picture.extent.height) / 2 - picture.extent.minY))
        image = picture.composited(over: CIImage(color: .black).cropped(to: bounds))

        let destination = CIRenderDestination(
            width: Int(target.width),
            height: Int(target.height),
            pixelFormat: view.colorPixelFormat,
            commandBuffer: commandBuffer,
            mtlTextureProvider: { drawable.texture })

        _ = try? context.startTask(toRender: image, from: bounds, to: destination, at: .zero)
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

struct ViewfinderView: UIViewRepresentable {
    let renderer: PreviewRenderer

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: renderer.device)
        view.delegate = renderer
        view.framebufferOnly = false          // Core Image writes into the drawable
        view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond = 30
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.backgroundColor = .black
        view.contentMode = .scaleAspectFill
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}
}
