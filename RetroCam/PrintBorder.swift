import CoreImage
import CoreImage.CIFilterBuiltins

/// Print border styles, each modelled on where that border comes from in a darkroom.
enum BorderStyle: String, CaseIterable {
    /// Full bleed.
    case none
    /// The paper margin under the enlarger's easel.
    case white
    /// The clear film edge printed through a widened negative carrier: prints black.
    case black
    /// A 35mm slide: the picture in the window of a card mount.
    case slide

    var label: String {
        switch self {
        case .none: return "NONE"
        case .white: return "WHITE"
        case .black: return "BLACK"
        case .slide: return "SLIDE"
        }
    }

    var next: BorderStyle {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

/// How a shot is printed: border style, its width, and a per-print seed for textured borders.
struct PrintFinish {
    var border: BorderStyle
    var seed: UInt32
    /// Border width as a fraction of the print's short side.
    var width: Double = PrintBorder.defaultWidth
    /// The shape of the picture.
    var format: FrameFormat = .medium645
}

/// Adds the border to a developed (linear-light) print. WHITE and BLACK keep the print's
/// size, with the picture scaled to fill the area inside the border; SLIDE puts the
/// picture, as it is, in the window of a square card mount, so the output is larger.
enum PrintBorder {
    /// Border width choices, as a fraction of the print's short side (2% to 12%).
    static let widthRange: ClosedRange<Double> = 0.02...0.12
    static let defaultWidth = 0.06
    private static let paper = CIColor(red: 0.95, green: 0.94, blue: 0.91, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!
    private static let filmBase = CIColor(red: 0.03, green: 0.03, blue: 0.03, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!

    /// - Parameters:
    ///   - seed: per-print variation for textured borders (unused by WHITE/BLACK).
    ///   - width: border width as a fraction of the short side (clamped to `widthRange`).
    static func apply(_ style: BorderStyle, to image: CIImage, seed: UInt32,
                      width: Double = defaultWidth) -> CIImage {
        let extent = image.extent
        let short = min(extent.width, extent.height)
        let fraction = min(max(width, widthRange.lowerBound), widthRange.upperBound)
        let pixels = max((short * fraction).rounded(), 1)
        switch style {
        case .none:
            return image
        case .white:
            return solid(image, color: paper, width: pixels)
        case .black:
            return solid(image, color: filmBase, width: pixels)
        case .slide:
            return slide(image, seed: seed)
        }
    }

    // MARK: Slide mount

    private static let mountLight = CIColor(red: 0.93, green: 0.89, blue: 0.81, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!
    private static let mountDark = CIColor(red: 0.85, green: 0.80, blue: 0.70, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!
    private static let windowEdge = CIColor(red: 0.2, green: 0.15, blue: 0.1, alpha: 0.45, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!

    /// The picture in a square card mount (a 35mm mount is 50mm across for a 36mm frame),
    /// with a softly rounded window, a shadowed edge round it and a little paper texture.
    private static func slide(_ image: CIImage, seed: UInt32) -> CIImage {
        // Keep the mounted print near the photo's size (at most 5000 px square, ~25 MP).
        var image = image
        let maxSide: CGFloat = 5000
        let wanted = max(image.extent.width, image.extent.height) * 1.42
        if wanted > maxSide {
            let s = maxSide / wanted
            image = image.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: s, kCIInputAspectRatioKey: 1])
            image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        }
        let e = image.extent
        let side = (max(e.width, e.height) * 1.42).rounded()
        let canvas = CGRect(x: 0, y: 0, width: side, height: side)
        let window = CGRect(x: ((side - e.width) / 2).rounded(), y: ((side - e.height) / 2).rounded(),
                            width: e.width, height: e.height)
        let radius = Float(min(e.width, e.height) * 0.025)

        let gradient = CIFilter.linearGradient()
        gradient.point0 = CGPoint(x: 0, y: side)
        gradient.point1 = CGPoint(x: side, y: 0)
        gradient.color0 = mountLight
        gradient.color1 = mountDark
        var mount = (gradient.outputImage ?? CIImage(color: mountLight)).cropped(to: canvas)

        // Paper texture: faint noise, different on every print.
        let noise = CIFilter.randomGenerator().outputImage?
            .transformed(by: CGAffineTransform(translationX: CGFloat(seed % 997), y: CGFloat(seed % 613)))
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0.05, y: 0, z: 0, w: 0),
            ])
        if let noise { mount = noise.cropped(to: canvas).composited(over: mount) }

        // The shadowed edge of the window, then the picture with rounded corners.
        let edge = CIFilter.roundedRectangleGenerator()
        let lip = max(min(e.width, e.height) * 0.006, 1)
        edge.extent = window.insetBy(dx: -lip, dy: -lip)
        edge.radius = radius + Float(lip)
        edge.color = windowEdge
        if let ring = edge.outputImage { mount = ring.composited(over: mount) }

        let maskShape = CIFilter.roundedRectangleGenerator()
        maskShape.extent = window
        maskShape.radius = radius
        maskShape.color = CIColor.white
        let picture = image.transformed(by: CGAffineTransform(translationX: window.minX - e.minX, y: window.minY - e.minY))
        guard let mask = maskShape.outputImage else { return picture.composited(over: mount).cropped(to: canvas) }
        return picture.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: mount, kCIInputMaskImageKey: mask,
        ]).cropped(to: canvas)
    }

    // MARK: Solid borders

    private static func solid(_ image: CIImage, color: CIColor, width b: CGFloat) -> CIImage {
        let extent = image.extent
        let inner = extent.insetBy(dx: b, dy: b)
        let picture = fill(image, into: inner).cropped(to: inner)
        return picture.composited(over: CIImage(color: color).cropped(to: extent))
    }

    /// Scale `image` (aspect-fill) so it covers `rect`, centred on it.
    private static func fill(_ image: CIImage, into rect: CGRect) -> CIImage {
        let extent = image.extent
        let s = max(rect.width / extent.width, rect.height / extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: s, y: s))
        return scaled.transformed(by: CGAffineTransform(
            translationX: rect.midX - scaled.extent.midX,
            y: rect.midY - scaled.extent.midY))
    }
}
