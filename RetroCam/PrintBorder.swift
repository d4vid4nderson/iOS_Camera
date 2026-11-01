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

    var label: String {
        switch self {
        case .none: return "NONE"
        case .white: return "WHITE"
        case .black: return "BLACK"
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
}

/// Adds the border to a developed (linear-light) print. The output keeps the same size;
/// the picture is scaled to fill the area inside the border.
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
        }
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
