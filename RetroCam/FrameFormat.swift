import CoreImage
import CoreGraphics

/// The shape of the picture, after the film formats and cameras it comes from. The sensor
/// is 4:3; every other format is a centred crop of it, with its long side along the
/// photo's long side (so it follows how the phone is held).
enum FrameFormat: String, CaseIterable {
    /// 6×4.5 medium format: the sensor's own 4:3, uncropped.
    case medium645
    /// 35mm: 3:2.
    case thirtyFive
    /// 6×6 medium format: square.
    case square
    /// 4×5 large format: 5:4.
    case large
    /// Widescreen 16:9.
    case wide
    /// The panoramic 65:24 of the XPAN.
    case xpan

    var label: String {
        switch self {
        case .medium645: return "6×4.5"
        case .thirtyFive: return "35MM"
        case .square: return "6×6"
        case .large: return "4×5"
        case .wide: return "16:9"
        case .xpan: return "XPAN"
        }
    }

    /// The format as a ratio, for the bar ("3:2").
    var ratioText: String {
        switch self {
        case .medium645: return "4:3"
        case .thirtyFive: return "3:2"
        case .square: return "1:1"
        case .large: return "5:4"
        case .wide: return "16:9"
        case .xpan: return "65:24"
        }
    }

    /// Long side over short side.
    var ratio: CGFloat {
        switch self {
        case .medium645: return 4 / 3
        case .thirtyFive: return 3 / 2
        case .square: return 1
        case .large: return 5 / 4
        case .wide: return 16 / 9
        case .xpan: return 65 / 24
        }
    }

    /// The largest centred rectangle of this format inside `rect`, its long side along
    /// `rect`'s long side.
    func rect(in rect: CGRect) -> CGRect {
        let landscape = rect.width >= rect.height
        var long = max(rect.width, rect.height)
        var short = min(rect.width, rect.height)
        guard short > 0 else { return rect }
        if long / short > ratio {
            long = short * ratio        // narrower than the sensor: trim the long side
        } else {
            short = long / ratio        // wider: trim the short side
        }
        let w = (landscape ? long : short).rounded()
        let h = (landscape ? short : long).rounded()
        return CGRect(x: (rect.midX - w / 2).rounded(), y: (rect.midY - h / 2).rounded(), width: w, height: h)
    }

    /// `image` cropped to this format, moved so the crop starts at the origin.
    func crop(_ image: CIImage) -> CIImage {
        guard self != .medium645 else { return image }
        let r = rect(in: image.extent)
        return image.cropped(to: r).transformed(by: CGAffineTransform(translationX: -r.minX, y: -r.minY))
    }
}
