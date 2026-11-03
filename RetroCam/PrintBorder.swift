import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

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
    /// The shape of the picture, and which way it's framed.
    var format: FrameFormat = .medium645
    var orientation: FrameOrientation = .landscape
    /// What a slide mount prints: the film and the frame number.
    var label: SlideLabel?
}

/// What's printed on a slide mount.
struct SlideLabel {
    var title: String
    var number: String?
    /// Colour film gets a cream card, black & white a grey-white plastic one.
    var color: Bool
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
                      width: Double = defaultWidth, label: SlideLabel? = nil) -> CIImage {
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
            return slide(image, seed: seed, label: label)
        }
    }

    // MARK: Slide mount

    private static func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CIColor {
        CIColor(red: r, green: g, blue: b, alpha: a, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!
    }

    /// The picture in a slide mount, as on filmexposures.com: a card (cream for colour
    /// film, grey-white plastic for black & white) with rounded corners and a soft shadow,
    /// on near-black; the film's name and the frame number printed across the top; the
    /// picture in a window with softly rounded corners and a shadowed edge. The margins
    /// follow the window, so a wide format gets a wide mount.
    private static func slide(_ input: CIImage, seed: UInt32, label: SlideLabel?) -> CIImage {
        var image = input
        // Keep the mounted print near the photo's size (long side at most 5000 px).
        let maxLong: CGFloat = 5000
        let grow: CGFloat = 1.5
        let wanted = max(image.extent.width, image.extent.height) * grow
        if wanted > maxLong {
            image = image.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: maxLong / wanted, kCIInputAspectRatioKey: 1])
        }
        image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        let e = image.extent
        // Margins from the picture's overall size, so a wide window gets a slim, wide mount.
        let long = (e.width * e.height).squareRoot()
        let side = (long * 0.19).rounded(), top = (long * 0.26).rounded(), bottom = (long * 0.20).rounded()
        let pad = (long * 0.08).rounded()
        let card = CGRect(x: pad, y: pad, width: e.width + 2 * side, height: e.height + top + bottom)
        let canvas = CGRect(x: 0, y: 0, width: card.width + 2 * pad, height: card.height + 2 * pad)
        let window = CGRect(x: card.minX + side, y: card.minY + bottom, width: e.width, height: e.height)

        let color = label?.color ?? true
        let light = color ? srgb(0.925, 0.89, 0.81) : srgb(0.90, 0.898, 0.882)
        let dark = color ? srgb(0.866, 0.82, 0.714) : srgb(0.812, 0.804, 0.78)
        let ink = color ? srgb(0.227, 0.176, 0.122) : srgb(0.149, 0.149, 0.165)
        let muted = color ? srgb(0.435, 0.376, 0.298) : srgb(0.365, 0.361, 0.353)

        // Near-black behind, and the card's soft shadow.
        var out = CIImage(color: srgb(0.06, 0.051, 0.047)).cropped(to: canvas)
        let cardRadius = Float(min(card.width, card.height) * 0.05)
        let shadow = CIFilter.roundedRectangleGenerator()
        shadow.extent = card.offsetBy(dx: 0, dy: -long * 0.012)
        shadow.radius = cardRadius
        shadow.color = srgb(0, 0, 0, 0.75)
        if let soft = shadow.outputImage?.applyingGaussianBlur(sigma: Double(long * 0.018)).cropped(to: canvas) {
            out = soft.composited(over: out)
        }

        // The card: a light-to-dark sweep with a little paper texture, rounded corners.
        let gradient = CIFilter.linearGradient()
        gradient.point0 = CGPoint(x: card.minX, y: card.maxY)
        gradient.point1 = CGPoint(x: card.maxX, y: card.minY)
        gradient.color0 = light
        gradient.color1 = dark
        var face = (gradient.outputImage ?? CIImage(color: light)).cropped(to: card)
        if let noise = CIFilter.randomGenerator().outputImage?
            .transformed(by: CGAffineTransform(translationX: CGFloat(seed % 997), y: CGFloat(seed % 613)))
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0.06, y: 0, z: 0, w: 0),
            ]) {
            face = noise.cropped(to: card).composited(over: face)
        }
        // The window's shadowed edge, cut into the card.
        let lip = max(min(e.width, e.height) * 0.008, 1)
        let windowRadius = Float(min(e.width, e.height) * 0.025)
        let edge = CIFilter.roundedRectangleGenerator()
        edge.extent = window.insetBy(dx: -lip, dy: -lip)
        edge.radius = windowRadius + Float(lip)
        edge.color = srgb(0.1, 0.07, 0.04, 0.5)
        if let ring = edge.outputImage { face = ring.composited(over: face) }

        // The film's name and the frame number across the top margin.
        if let label {
            let size = long * 0.06
            let baseline = window.maxY + (top - size) * 0.45
            if let name = text(label.title, size: size, weight: .heavy, color: ink) {
                face = name.transformed(by: CGAffineTransform(translationX: window.minX, y: baseline)).composited(over: face)
            }
            if let number = label.number, let n = text(number, size: size * 0.8, weight: .semibold, color: muted) {
                face = n.transformed(by: CGAffineTransform(translationX: window.maxX - n.extent.width, y: baseline)).composited(over: face)
            }
        }
        out = mask(face, to: card, radius: cardRadius, over: out)

        // The picture, in the window with softly rounded corners.
        let picture = image.transformed(by: CGAffineTransform(translationX: window.minX, y: window.minY))
        return mask(picture, to: window, radius: windowRadius, over: out).cropped(to: canvas)
    }

    /// `image` inside a rounded rectangle, over `background`.
    private static func mask(_ image: CIImage, to rect: CGRect, radius: Float, over background: CIImage) -> CIImage {
        let shape = CIFilter.roundedRectangleGenerator()
        shape.extent = rect
        shape.radius = radius
        shape.color = CIColor.white
        guard let mask = shape.outputImage else { return image.cropped(to: rect).composited(over: background) }
        return image.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: background, kCIInputMaskImageKey: mask,
        ])
    }

    /// Printed text, in the app's monospaced face.
    private static func text(_ string: String, size: CGFloat, weight: UIFont.Weight, color: CIColor) -> CIImage? {
        let font = UIFont.monospacedSystemFont(ofSize: size, weight: weight)
        let generator = CIFilter.attributedTextImageGenerator()
        generator.text = NSAttributedString(string: string, attributes: [
            .font: font, .foregroundColor: UIColor(ciColor: color), .kern: size * 0.06,
        ])
        generator.scaleFactor = 1
        return generator.outputImage
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
