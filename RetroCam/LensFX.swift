import CoreImage
import CoreImage.CIFilterBuiltins

/// Lens and print effects (FX panel). Every size is a fraction of the image's long side,
/// so the 1,200 px live preview and a 6,000 px photo get the same look.
///
/// Lens effects run on the colour image before the film sees it (a real lens bends the
/// light first); print effects (HALFTONE, ETCH) run on the developed grey print.
enum LensFX {
    /// The effect centre in Core Image coordinates (bottom-left origin).
    private static func center(_ stock: FilmStock, in extent: CGRect) -> CGPoint {
        let x = min(max(stock.effectX, 0), 1)
        let y = min(max(stock.effectY, 0), 1)
        return CGPoint(x: extent.minX + x * extent.width, y: extent.minY + (1 - y) * extent.height)
    }

    static func lens(_ image: CIImage, stock: FilmStock) -> CIImage {
        let amount = min(max(stock.effectAmount, 0), 1)
        guard stock.effect != .none, !stock.effect.isPrintEffect, amount > 0 else { return image }
        let extent = image.extent
        let long = max(extent.width, extent.height)
        let c = center(stock, in: extent)
        let source = image.clampedToExtent()
        let out: CIImage?

        switch stock.effect {
        case .fisheye:
            let f = CIFilter.bumpDistortion()
            f.inputImage = source
            f.center = c
            f.radius = Float(long * 0.75)
            f.scale = Float(0.15 + amount * 0.85)
            out = f.outputImage

        case .swirl:
            let f = CIFilter.twirlDistortion()
            f.inputImage = source
            f.center = c
            f.radius = Float(long * 0.6)
            f.angle = Float(amount * 3.2)
            out = f.outputImage

        case .tiltShift:
            out = tiltShift(source, extent: extent, bandY: c.y, amount: amount)

        case .zoomBurst:
            let f = CIFilter.zoomBlur()
            f.inputImage = source
            f.center = c
            f.amount = Float(amount * long * 0.035)
            out = f.outputImage

        case .drag:
            let f = CIFilter.motionBlur()
            f.inputImage = source
            f.radius = Float(amount * long * 0.03)
            f.angle = 0
            out = f.outputImage

        case .double:
            // A second exposure on the same frame, slipped down and to the right.
            let shift = amount * long * 0.04
            let ghost = source.transformed(by: CGAffineTransform(translationX: shift, y: -shift * 0.6))
            out = average([(source, 0.55), (ghost, 0.45)])

        case .prism:
            // Repeated slices, as through a faceted prism filter.
            let shift = amount * long * 0.06
            let left = source.transformed(by: CGAffineTransform(translationX: -shift, y: 0))
            let right = source.transformed(by: CGAffineTransform(translationX: shift, y: 0))
            out = average([(source, 0.5), (left, 0.25), (right, 0.25)])

        case .ripple:
            out = ripple(source, extent: extent, amount: amount)

        case .kaleido:
            let f = CIFilter.kaleidoscope()
            f.inputImage = source
            f.center = c
            f.count = 3 + Int((amount * 6).rounded())
            f.angle = 0
            out = f.outputImage

        case .none, .halftone, .etch:
            out = image
        }
        return out?.cropped(to: extent) ?? image
    }

    static func print(_ image: CIImage, stock: FilmStock) -> CIImage {
        let amount = min(max(stock.effectAmount, 0), 1)
        guard stock.effect.isPrintEffect, amount > 0 else { return image }
        let extent = image.extent
        let long = max(extent.width, extent.height)

        switch stock.effect {
        case .halftone:
            // Newsprint dots: coarser as the amount goes up.
            let f = CIFilter.dotScreen()
            f.inputImage = image
            f.center = center(stock, in: extent)
            f.width = Float(long * (0.004 + amount * 0.012))
            f.angle = 0.6
            f.sharpness = 0.65
            return f.outputImage?.cropped(to: extent) ?? image

        case .etch:
            // Ink lines on paper, mixed over the print by the amount.
            let lines = CIFilter.lineOverlay()
            lines.inputImage = image
            lines.nrNoiseLevel = 0.07
            lines.nrSharpness = 0.71
            lines.edgeIntensity = 1.0
            lines.threshold = 0.1
            lines.contrast = 50
            guard let ink = lines.outputImage?.cropped(to: extent) else { return image }
            let paper = CIImage(color: CIColor(red: 0.96, green: 0.96, blue: 0.94)).cropped(to: extent)
            let etched = ink.composited(over: paper)
            let mix = CIFilter.dissolveTransition()
            mix.inputImage = image
            mix.targetImage = etched
            mix.time = Float(0.35 + amount * 0.65)
            return mix.outputImage?.cropped(to: extent) ?? image

        default:
            return image
        }
    }

    // MARK: Helpers

    /// Weighted sum of images (weights add up to 1).
    private static func average(_ layers: [(CIImage, CGFloat)]) -> CIImage? {
        var sum: CIImage?
        for (layer, weight) in layers {
            let scale = CIFilter.colorMatrix()
            scale.inputImage = layer
            scale.rVector = CIVector(x: weight, y: 0, z: 0, w: 0)
            scale.gVector = CIVector(x: 0, y: weight, z: 0, w: 0)
            scale.bVector = CIVector(x: 0, y: 0, z: weight, w: 0)
            scale.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            guard let scaled = scale.outputImage else { return nil }
            if let current = sum {
                let add = CIFilter.additionCompositing()
                add.inputImage = scaled
                add.backgroundImage = current
                sum = add.outputImage
            } else {
                sum = scaled
            }
        }
        return sum
    }

    /// Sharp band through `bandY`, blur growing above and below it.
    private static func tiltShift(_ image: CIImage, extent: CGRect, bandY: CGFloat, amount: CGFloat) -> CIImage? {
        let long = max(extent.width, extent.height)
        let halfBand = extent.height * 0.08
        let fade = extent.height * 0.22
        // Two gradients, white away from the band, black at it; the brighter one wins.
        func ramp(from y0: CGFloat, to y1: CGFloat) -> CIImage? {
            let g = CIFilter.linearGradient()
            g.point0 = CGPoint(x: 0, y: y0)
            g.point1 = CGPoint(x: 0, y: y1)
            g.color0 = CIColor(red: 0, green: 0, blue: 0)
            g.color1 = CIColor(red: 1, green: 1, blue: 1)
            return g.outputImage?.cropped(to: extent)
        }
        guard let above = ramp(from: bandY + halfBand, to: bandY + halfBand + fade),
              let below = ramp(from: bandY - halfBand, to: bandY - halfBand - fade) else { return nil }
        let mask = above.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: below])

        let blur = CIFilter.maskedVariableBlur()
        blur.inputImage = image
        blur.mask = mask
        blur.radius = Float(amount * long * 0.012)
        return blur.outputImage
    }

    /// Watery horizontal waves: a soft stripe pattern drives a displacement.
    private static func ripple(_ image: CIImage, extent: CGRect, amount: CGFloat) -> CIImage? {
        let long = max(extent.width, extent.height)
        let wave = long * 0.035
        let stripes = CIFilter.stripesGenerator()
        stripes.center = CGPoint(x: extent.midX, y: extent.midY)
        stripes.color0 = CIColor(red: 1, green: 1, blue: 1)
        stripes.color1 = CIColor(red: 0, green: 0, blue: 0)
        stripes.width = Float(wave)
        stripes.sharpness = 0
        guard let bands = stripes.outputImage?
            .transformed(by: CGAffineTransform(rotationAngle: .pi / 2))   // horizontal bands
            .applyingGaussianBlur(sigma: Double(wave * 0.35))
            .cropped(to: extent) else { return nil }

        let displace = CIFilter.displacementDistortion()
        displace.inputImage = image
        displace.displacementImage = bands
        displace.scale = Float(amount * long * 0.025)
        return displace.outputImage
    }
}
