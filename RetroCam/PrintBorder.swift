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

/// How a shot is printed: border style plus a per-print seed for textured borders.
struct PrintFinish {
    var border: BorderStyle
    var seed: UInt32
}

/// Adds the border to a developed (linear-light) print. The output keeps the same size;
/// the picture is scaled to fill the area inside the border.
enum PrintBorder {
    private static let paper = CIColor(red: 0.95, green: 0.94, blue: 0.91, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!
    private static let filmBase = CIColor(red: 0.03, green: 0.03, blue: 0.03, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!

    /// - Parameter seed: per-print variation for textured borders (unused by WHITE/BLACK).
    static func apply(_ style: BorderStyle, to image: CIImage, seed: UInt32) -> CIImage {
        let extent = image.extent
        let short = min(extent.width, extent.height)
        switch style {
        case .none:
            return image
        case .white:
            return solid(image, color: paper, width: (short * 0.06).rounded())
        case .black:
            return solid(image, color: filmBase, width: (short * 0.045).rounded())
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
