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

    /// The most pixels a developed frame keeps, like the detail each film format holds:
    /// 35mm-sized frames 24 MP, medium format 36 MP, 4×5 everything the sensor gives (about
    /// 46 MP from a 48 MP camera). Smaller captures (other lenses, flash) stay as they are.
    var maxPixels: CGFloat {
        switch self {
        case .thirtyFive, .xpan, .wide: return 24_000_000
        case .medium645, .square: return 36_000_000
        case .large: return 50_000_000
        }
    }

    /// Megapixels a frame of this format comes out at from a camera giving `sensor` MP
    /// (a 4:3 sensor): the format's cut of the sensor, capped at `maxPixels`. Whole numbers.
    func megapixels(fromSensor sensor: Double) -> Int {
        let sensorRatio: Double = 4 / 3
        let r = Double(ratio)
        let share = r >= sensorRatio ? sensorRatio / r : r / sensorRatio
        return Int(min(Double(maxPixels) / 1_000_000, sensor * share).rounded())
    }

    /// Whether the orientation can be chosen (6×4.5 is the sensor as held; 6×6 is square).
    var hasOrientation: Bool { self != .medium645 && self != .square }

    /// The largest centred rectangle of this format inside `rect`: wider than tall when
    /// `wide`, taller than wide otherwise. 6×4.5 is the whole of `rect`, as held.
    func rect(in rect: CGRect, wide: Bool) -> CGRect {
        guard self != .medium645, rect.width > 0, rect.height > 0 else { return rect }
        // Target width over height.
        let aspect = wide ? ratio : 1 / ratio
        var w = rect.width, h = rect.height
        if w / h > aspect { w = h * aspect } else { h = w / aspect }
        w = w.rounded(); h = h.rounded()
        return CGRect(x: (rect.midX - w / 2).rounded(), y: (rect.midY - h / 2).rounded(), width: w, height: h)
    }

    /// `image` cropped to this format, moved so the crop starts at the origin.
    func crop(_ image: CIImage, wide: Bool) -> CIImage {
        guard self != .medium645 else { return image }
        let r = rect(in: image.extent, wide: wide)
        return image.cropped(to: r).transformed(by: CGAffineTransform(translationX: -r.minX, y: -r.minY))
    }
}

/// Which way a format is framed in the world, whichever way the phone is held.
enum FrameOrientation: String, CaseIterable {
    case landscape, portrait

    var label: String { self == .landscape ? "LANDSCAPE" : "PORTRAIT" }
}
