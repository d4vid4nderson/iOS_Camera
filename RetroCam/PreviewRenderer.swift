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
        guard let frame, target.width > 0, target.height > 0,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        // Aspect-fill the frame into the drawable, *then* develop it, so we only
        // process as many pixels as the screen shows.
        let scale = max(target.width / frame.extent.width, target.height / frame.extent.height)
        var image = frame.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        image = image.transformed(by: CGAffineTransform(
            translationX: (target.width - image.extent.width) / 2 - image.extent.minX,
            y: (target.height - image.extent.height) / 2 - image.extent.minY))
        let bounds = CGRect(origin: .zero, size: target)
        image = FilmLook.apply(stock, to: image.cropped(to: bounds))

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
