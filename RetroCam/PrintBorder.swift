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
    /// Filed carrier: rough black edge, plus light leaks fogging in from the edges.
    /// On B&W negative film a leak exposes the negative, so it prints as pale fog.
    case burned

    var label: String {
        switch self {
        case .none: return "NONE"
        case .white: return "WHITE"
        case .black: return "BLACK"
        case .burned: return "BURN"
        }
    }

    var next: BorderStyle {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

/// How a shot is printed: border style and the burn pattern for this print.
struct PrintFinish {
    var border: BorderStyle
    var seed: UInt32
}

/// Adds the border to a developed (linear-light) print. The output keeps the same size;
/// the picture is scaled to fill the area inside the border.
enum PrintBorder {
    private static let paper = CIColor(red: 0.95, green: 0.94, blue: 0.91, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!
    private static let filmBase = CIColor(red: 0.03, green: 0.03, blue: 0.03, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!

    /// - Parameter seed: picks the burn pattern; keep it fixed for the live preview
    ///   (no flicker) and vary it per shot so every print is different.
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
        case .burned:
            return burned(image, width: (short * 0.045).rounded(), seed: seed)
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

    // MARK: Burned (filed carrier + light leaks)

    private static func burned(_ image: CIImage, width b: CGFloat, seed: UInt32) -> CIImage {
        let extent = image.extent
        let short = min(extent.width, extent.height)
        let inner = extent.insetBy(dx: b, dy: b)

        // Picture reaches a little past the inner edge so the rough edge can bite both ways.
        let picture = fill(image, into: inner.insetBy(dx: -b * 0.4, dy: -b * 0.4)).cropped(to: extent)
        let base = CIImage(color: filmBase).cropped(to: extent)

        // White inner rectangle on black, softened: a ramp across the frame edge.
        let rect = CIImage(color: .white).cropped(to: inner)
            .composited(over: CIImage(color: .black).cropped(to: extent))
        let ramp = rect.clampedToExtent().applyingGaussianBlur(sigma: Double(b * 0.35)).cropped(to: extent)

        // Rough, filed edge: ramp + fine noise, then a steep threshold.
        let rough = scaled(noise(covering: extent, scale: b * 0.15, seed: seed), by: 0.5, plus: 0)
        let edgeMask = scaled(add(rough, ramp), by: 8, plus: 0.5 - 0.75 * 8)
            .applyingFilter("CIColorClamp")

        let blend = CIFilter.blendWithMask()
        blend.inputImage = picture
        blend.backgroundImage = base
        blend.maskImage = edgeMask
        guard var result = blend.outputImage?.cropped(to: extent) else { return image }

        // Light leaks: pale fog near the edges, in patches.
        let nearEdge = scaled(rect.clampedToExtent().applyingGaussianBlur(sigma: Double(b * 2)).cropped(to: extent),
                              by: -1, plus: 1)
        let patches = scaled(noise(covering: extent, scale: short * 0.12, seed: seed &+ 1), by: 3, plus: -1)
            .applyingFilter("CIColorClamp")
        let multiply = CIFilter.multiplyBlendMode()
        multiply.inputImage = patches
        multiply.backgroundImage = nearEdge
        if let fogShape = multiply.outputImage {
            let fog = scaled(fogShape.cropped(to: extent), by: 0.7, plus: 0).applyingFilter("CIColorClamp")
            let screen = CIFilter.screenBlendMode()
            screen.inputImage = fog
            screen.backgroundImage = result
            result = screen.outputImage?.cropped(to: extent) ?? result
        }
        return result
    }

    // MARK: Helpers

    /// out = in * gain + bias on RGB (alpha untouched).
    private static func scaled(_ image: CIImage, by gain: CGFloat, plus bias: CGFloat) -> CIImage {
        let m = CIFilter.colorMatrix()
        m.inputImage = image
        m.rVector = CIVector(x: gain, y: 0, z: 0, w: 0)
        m.gVector = CIVector(x: 0, y: gain, z: 0, w: 0)
        m.bVector = CIVector(x: 0, y: 0, z: gain, w: 0)
        m.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        m.biasVector = CIVector(x: bias, y: bias, z: bias, w: 0)
        return m.outputImage ?? image
    }

    /// a + b on RGB (both opaque).
    private static func add(_ a: CIImage, _ b: CIImage) -> CIImage {
        let f = CIFilter.linearDodgeBlendMode()
        f.inputImage = a
        f.backgroundImage = b
        return f.outputImage ?? b
    }

    /// Smooth mid-grey noise in 0...1 with blobs about `scale` px across, fixed by `seed`.
    private static func noise(covering extent: CGRect, scale: CGFloat, seed: UInt32) -> CIImage {
        let random = CIFilter.randomGenerator().outputImage ?? CIImage(color: .gray)
        let offset = CGPoint(x: CGFloat(seed % 997) * 5.3, y: CGFloat((seed / 997) % 991) * 7.1)
        let transform = CGAffineTransform(translationX: -offset.x, y: -offset.y)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: extent.minX, y: extent.minY))
        let sourceRect = extent.insetBy(dx: -scale * 4, dy: -scale * 4).applying(transform.inverted()).integral
        // Opaque first (the generator's alpha is random), then average three channels.
        let third = CIVector(x: 1.0 / 3, y: 1.0 / 3, z: 1.0 / 3, w: 0)
        let mono = CIFilter.colorMatrix()
        mono.inputImage = random.settingAlphaOne(in: sourceRect)
        mono.rVector = third
        mono.gVector = third
        mono.bVector = third
        mono.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        let smooth = (mono.outputImage ?? random)
            .transformed(by: transform)
            .applyingGaussianBlur(sigma: Double(scale * 0.6))
            .cropped(to: extent)
        // Blurring narrows the spread; stretch it back around 0.5.
        return scaled(smooth, by: 3.5, plus: 0.5 - 0.5 * 3.5).applyingFilter("CIColorClamp")
    }
}
