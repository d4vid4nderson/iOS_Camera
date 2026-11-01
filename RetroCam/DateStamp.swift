import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// What the date back burns into the corner of the frame.
enum StampMode: String, CaseIterable {
    case off
    case date
    case dateTime

    /// Short label for the control.
    var label: String {
        switch self {
        case .off: return "OFF"
        case .date: return "DATE"
        case .dateTime: return "D+T"
        }
    }

    var next: StampMode {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM dd ''yy"          // 10 24 '26
        return f
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM dd ''yy  HH:mm"   // 10 24 '26  21:28
        return f
    }()

    /// The text to stamp for `date`, or nil when the stamp is off.
    func text(for date: Date) -> String? {
        switch self {
        case .off: return nil
        case .date: return Self.dateFormatter.string(from: date)
        case .dateTime: return Self.dateTimeFormatter.string(from: date)
        }
    }
}

/// Seven-segment date-back digits, burned into the film the way a real date back did:
/// a small light behind the film exposes the digits, so on the print they're soft,
/// glowing, slightly uneven, and carry the same grain and vignette as the picture.
enum DateStamp {
    private static let cache = NSCache<NSString, CIImage>()

    /// Burn `text` into the bottom-right corner of `image`.
    /// Called by FilmLook in its gamma-encoded print stage, before grain and vignette.
    static func burn(_ text: String, into image: CIImage) -> CIImage {
        let extent = image.extent
        let longSide = max(extent.width, extent.height)
        let height = (longSide * 0.032).rounded()
        let margin = longSide * 0.045
        guard height >= 6, let glyphs = glyphMask(text, height: height) else { return image }

        let placed = glyphs.transformed(by: CGAffineTransform(
            translationX: extent.maxX - margin - glyphs.extent.width,
            y: extent.minY + margin))

        // Wide red halo (light scattering in the film base, slightly off-register),
        // warm glow, then a softened orange core. Screened on like light, not pasted on.
        let layers: [(blur: CGFloat, offset: CGFloat, r: CGFloat, g: CGFloat, b: CGFloat, strength: CGFloat)] = [
            (0.45, 0.03, 1.0, 0.25, 0.05, 0.35),
            (0.18, 0.00, 1.0, 0.42, 0.10, 0.55),
            (0.06, 0.00, 1.0, 0.58, 0.22, 0.95),
        ]
        var out = image
        for layer in layers {
            let light = placed
                .applyingGaussianBlur(sigma: Double(height * layer.blur))
                .transformed(by: CGAffineTransform(translationX: -height * layer.offset, y: -height * layer.offset))
            let tint = CIFilter.colorMatrix()
            tint.inputImage = light
            tint.rVector = CIVector(x: layer.r, y: 0, z: 0, w: 0)
            tint.gVector = CIVector(x: 0, y: layer.g, z: 0, w: 0)
            tint.bVector = CIVector(x: 0, y: 0, z: layer.b, w: 0)
            tint.aVector = CIVector(x: 0, y: 0, z: 0, w: layer.strength)
            let screen = CIFilter.screenBlendMode()
            screen.inputImage = tint.outputImage
            screen.backgroundImage = out
            out = screen.outputImage ?? out
        }
        return out.cropped(to: extent)
    }

    /// White glyphs on transparent, each segment a slightly different strength.
    /// No colour management: values go straight into FilmLook's encoded print stage.
    private static func glyphMask(_ text: String, height: CGFloat) -> CIImage? {
        let key = "\(text)|\(Int(height))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let cg = render(text, height: height) else { return nil }
        let image = CIImage(cgImage: cg, options: [.colorSpace: NSNull()])
        cache.setObject(image, forKey: key)
        return image
    }

    // MARK: Seven-segment drawing

    /// Segments: a top, b top-right, c bottom-right, d bottom, e bottom-left, f top-left, g middle.
    private static let digitSegments: [Character: String] = [
        "0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc",
        "5": "afgcd", "6": "afgedc", "7": "abc", "8": "abcdefg", "9": "abcdfg",
    ]

    private static func render(_ text: String, height h: CGFloat) -> CGImage? {
        let digitWidth = h * 0.5
        let thickness = h * 0.11
        let gap = h * 0.04
        let slant = h * 0.12                 // italic lean, like the real LEDs
        let pad = h * 0.3                    // room for the glow

        func advance(_ c: Character) -> CGFloat {
            switch c {
            case " ": return h * 0.35
            case "'": return thickness + h * 0.14
            case ":": return thickness + h * 0.2
            default: return digitSegments[c] != nil ? digitWidth + h * 0.18 : 0
            }
        }
        let textWidth = text.reduce(0) { $0 + advance($1) }
        let size = CGSize(width: (textWidth + slant + 2 * pad).rounded(.up), height: (h + 2 * pad).rounded(.up))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            cg.translateBy(x: pad, y: pad)
            // Lean right: top of each glyph shifted by `slant`.
            cg.concatenate(CGAffineTransform(a: 1, b: 0, c: -slant / h, d: 1, tx: slant, ty: 0))

            // Worn LEDs: each segment 78-100% strength, same pattern every time.
            var segmentIndex = 0
            func bar(_ rect: CGRect) {
                let noise = (sin(Double(segmentIndex) * 12.9898) * 43758.5453)
                let strength = 0.78 + 0.22 * (noise - noise.rounded(.down))
                segmentIndex += 1
                UIColor(white: 1, alpha: CGFloat(strength)).setFill()
                UIBezierPath(roundedRect: rect, cornerRadius: thickness / 2).fill()
            }

            var x: CGFloat = 0
            for c in text {
                if let segments = digitSegments[c] {
                    let w = digitWidth, t = thickness, half = h / 2
                    for s in segments {
                        switch s {
                        case "a": bar(CGRect(x: x + t / 2 + gap, y: 0, width: w - t - 2 * gap, height: t))
                        case "g": bar(CGRect(x: x + t / 2 + gap, y: half - t / 2, width: w - t - 2 * gap, height: t))
                        case "d": bar(CGRect(x: x + t / 2 + gap, y: h - t, width: w - t - 2 * gap, height: t))
                        case "f": bar(CGRect(x: x, y: t / 2 + gap, width: t, height: half - t / 2 - 2 * gap))
                        case "b": bar(CGRect(x: x + w - t, y: t / 2 + gap, width: t, height: half - t / 2 - 2 * gap))
                        case "e": bar(CGRect(x: x, y: half + gap, width: t, height: half - t / 2 - 2 * gap))
                        case "c": bar(CGRect(x: x + w - t, y: half + gap, width: t, height: half - t / 2 - 2 * gap))
                        default: break
                        }
                    }
                } else if c == "'" {
                    bar(CGRect(x: x, y: 0, width: thickness, height: h * 0.3))
                } else if c == ":" {
                    bar(CGRect(x: x, y: h * 0.28, width: thickness, height: thickness))
                    bar(CGRect(x: x, y: h * 0.66, width: thickness, height: thickness))
                }
                x += advance(c)
            }
        }
        return image.cgImage
    }
}
