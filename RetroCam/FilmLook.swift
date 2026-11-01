import CoreImage
import CoreImage.CIFilterBuiltins

/// The black & white film emulation pipeline. Pure Core Image, so the exact
/// same recipe runs on the live viewfinder and on the full-resolution photo.
///
/// Grain size is expressed relative to the image's long side, so a 1,500 px
/// preview and a 4,000 px still end up with the same-looking grain.
enum FilmLook {
    static func apply(_ stock: FilmStock, to input: CIImage) -> CIImage {
        let extent = input.extent

        // 0. Lens + exposure, in linear light before the film sees it.
        var lens = input
        if stock.exposure != 0 {
            let push = CIFilter.exposureAdjust()
            push.inputImage = lens
            push.ev = Float(stock.exposure)
            lens = push.outputImage ?? lens
        }
        if stock.edgeSoftness > 0 {
            lens = softenEdges(lens, amount: stock.edgeSoftness)
        }

        // 1. Spectral response -> monochrome (in Core Image's linear working space).
        let mix = CIVector(x: stock.red, y: stock.green, z: stock.blue, w: 0)
        let mono = CIFilter.colorMatrix()
        mono.inputImage = lens
        mono.rVector = mix
        mono.gVector = mix
        mono.bVector = mix
        mono.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        var image = mono.outputImage!.clampedToExtent().applyingFilter("CIColorClamp").cropped(to: extent)

        // 2. Work in gamma-encoded space for the tonal/print steps (curves behave like a darkroom).
        image = image.applyingFilter("CILinearToSRGBToneCurve")

        // 3. Characteristic curve: S-curve for contrast, lifted blacks, dimmed whites.
        image = toneCurve(image, stock: stock)

        // 3b. Highlight glow (diffusion / halation-like bloom around bright areas).
        if stock.bloom > 0 {
            image = bloom(image, amount: stock.bloom)
        }

        // 4. Paper toning.
        image = tone(image, paper: stock.paper)

        // 5. Grain.
        if stock.grain > 0 {
            image = addGrain(to: image, amount: stock.grain, size: stock.grainSize)
        }

        // 6. Vignette (cheap lens fall-off).
        if stock.vignette > 0 {
            let v = CIFilter.vignetteEffect()
            v.inputImage = image
            v.center = CGPoint(x: extent.midX, y: extent.midY)
            v.radius = Float(max(extent.width, extent.height) * 0.62)
            v.intensity = Float(stock.vignette * 0.8)
            v.falloff = 0.6
            image = v.outputImage ?? image
        }

        // 7. Back to linear for the renderer.
        return image.applyingFilter("CISRGBToneCurveToLinear").cropped(to: extent)
    }

    /// Lens that gets softer toward the corners: a radial mask (sharp centre, soft edges)
    /// drives a variable blur. Blur size scales with the image so preview and print match.
    private static func softenEdges(_ image: CIImage, amount: CGFloat) -> CIImage {
        let extent = image.extent
        let longSide = max(extent.width, extent.height)

        let gradient = CIFilter.radialGradient()
        gradient.center = CGPoint(x: extent.midX, y: extent.midY)
        gradient.radius0 = Float(longSide * 0.30)
        gradient.radius1 = Float(longSide * 0.75)
        gradient.color0 = CIColor(red: 0, green: 0, blue: 0)
        gradient.color1 = CIColor(red: 1, green: 1, blue: 1)

        let blur = CIFilter.maskedVariableBlur()
        blur.inputImage = image.clampedToExtent()
        blur.mask = gradient.outputImage?.cropped(to: extent)
        blur.radius = Float(amount * longSide * 0.008)
        return blur.outputImage?.cropped(to: extent) ?? image
    }

    /// Soft glow around highlights: keep what's above 70% grey, blur it wide, screen it back on.
    private static func bloom(_ image: CIImage, amount: CGFloat) -> CIImage {
        let extent = image.extent
        let longSide = max(extent.width, extent.height)
        let threshold: CGFloat = 0.7
        let gain = 1 / (1 - threshold)

        let highlights = CIFilter.colorMatrix()
        highlights.inputImage = image
        highlights.rVector = CIVector(x: gain, y: 0, z: 0, w: 0)
        highlights.gVector = CIVector(x: 0, y: gain, z: 0, w: 0)
        highlights.bVector = CIVector(x: 0, y: 0, z: gain, w: 0)
        highlights.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        highlights.biasVector = CIVector(x: -threshold * gain, y: -threshold * gain, z: -threshold * gain, w: 0)
        guard let bright = highlights.outputImage?.applyingFilter("CIColorClamp") else { return image }

        let glow = bright
            .clampedToExtent()
            .applyingGaussianBlur(sigma: Double(longSide * 0.015))
            .cropped(to: extent)

        let strength = CIFilter.colorMatrix()
        strength.inputImage = glow
        strength.rVector = CIVector(x: amount, y: 0, z: 0, w: 0)
        strength.gVector = CIVector(x: 0, y: amount, z: 0, w: 0)
        strength.bVector = CIVector(x: 0, y: 0, z: amount, w: 0)
        strength.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)

        let screen = CIFilter.screenBlendMode()
        screen.inputImage = strength.outputImage
        screen.backgroundImage = image
        return screen.outputImage?.cropped(to: extent) ?? image
    }

    private static func toneCurve(_ image: CIImage, stock: FilmStock) -> CIImage {
        let c = stock.contrast
        let lo = stock.blackLift
        let hi = stock.whitePoint
        func y(_ v: CGFloat) -> CGFloat { lo + min(max(v, 0), 1) * (hi - lo) }

        let curve = CIFilter.toneCurve()
        curve.inputImage = image
        curve.point0 = CGPoint(x: 0.0, y: y(0))
        curve.point1 = CGPoint(x: 0.25, y: y(0.25 - 0.13 * c))
        curve.point2 = CGPoint(x: 0.5, y: y(0.5))
        curve.point3 = CGPoint(x: 0.75, y: y(0.75 + 0.13 * c))
        curve.point4 = CGPoint(x: 1.0, y: y(1))
        return curve.outputImage ?? image
    }

    private static func tone(_ image: CIImage, paper: FilmStock.PaperTone) -> CIImage {
        let color: CIColor
        let amount: Float
        switch paper {
        case .neutral: return image
        case .warm: color = CIColor(red: 1.0, green: 0.86, blue: 0.66); amount = 0.75
        case .cool: color = CIColor(red: 0.86, green: 0.93, blue: 1.0); amount = 0.6
        }
        let f = CIFilter.colorMonochrome()
        f.inputImage = image
        f.color = color
        f.intensity = amount
        return f.outputImage ?? image
    }

    // MARK: - Grain
    //
    // Two octaves of near-Gaussian noise (fine grain plus larger, softer clumps), each
    // laid down at a random angle and offset so it never lines up into a grid and
    // "dances" from frame to frame like real film. Strength follows the tone: strongest
    // in the midtones, gentler in deep shadows and highlights.

    /// Enlarging + blurring the noise keeps ~43% of its spread; this restores it.
    /// Measured for blur sigma = 0.5 x scale (see PR description).
    private static let grainGain: CGFloat = 2.3

    private static func addGrain(to image: CIImage, amount: CGFloat, size: CGFloat) -> CIImage {
        let extent = image.extent
        // Grain size in pixels, relative to the long side so preview and print match.
        let px = max(1, size * max(extent.width, extent.height) / 1600)

        var grainy = image
        for (scale, strength) in [(px, 2.6 * amount), (px * 2.2, 1.4 * amount)] {
            guard let layer = grainLayer(covering: extent, scale: scale, strength: strength) else { return image }
            let blend = CIFilter.softLightBlendMode()
            blend.inputImage = layer
            blend.backgroundImage = grainy
            grainy = blend.outputImage?.cropped(to: extent) ?? grainy
        }

        // Tone weighting: 0.3 + 2.8 L - 2.8 L^2 -> 0.3 at black/white, 1.0 at mid-grey.
        let weight = CIVector(x: 0.3, y: 2.8, z: -2.8, w: 0)
        let mask = CIFilter.colorPolynomial()
        mask.inputImage = image
        mask.redCoefficients = weight
        mask.greenCoefficients = weight
        mask.blueCoefficients = weight
        mask.alphaCoefficients = CIVector(x: 1, y: 0, z: 0, w: 0)

        let mix = CIFilter.blendWithMask()
        mix.inputImage = grainy
        mix.backgroundImage = image
        mix.maskImage = mask.outputImage
        return mix.outputImage?.cropped(to: extent) ?? grainy
    }

    /// Mid-grey (0.5) centred grain covering `extent`, clumps about `scale` px across,
    /// spread (sd) of about 0.167 x `strength`.
    private static func grainLayer(covering extent: CGRect, scale: CGFloat, strength: CGFloat) -> CIImage? {
        guard let random = CIFilter.randomGenerator().outputImage else { return nil }

        // Noise space -> image space: jump to a random patch, rotate by a random angle,
        // enlarge, then centre on the image.
        let offset = CGPoint(x: CGFloat.random(in: 0..<4096), y: CGFloat.random(in: 0..<4096))
        let transform = CGAffineTransform(translationX: -offset.x, y: -offset.y)
            .concatenating(CGAffineTransform(rotationAngle: CGFloat.random(in: 0..<CGFloat.pi)))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: extent.midX, y: extent.midY))

        // CIRandomGenerator's alpha is random too. Left as is, colour filters divide by
        // it (un-premultiply) and nearly transparent pixels explode into bright specks.
        // Make the patch we sample opaque first.
        let margin = scale * 2 + 4
        let sourceRect = extent.insetBy(dx: -margin, dy: -margin).applying(transform.inverted()).integral
        let opaque = random.settingAlphaOne(in: sourceRect)

        // Average three independent uniform channels -> near-Gaussian, mean 0.5, sd ~0.167.
        let third = CIVector(x: 1.0 / 3, y: 1.0 / 3, z: 1.0 / 3, w: 0)
        let mono = CIFilter.colorMatrix()
        mono.inputImage = opaque
        mono.rVector = third
        mono.gVector = third
        mono.bVector = third
        mono.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        guard let monoNoise = mono.outputImage else { return nil }

        // Enlarge, then blur away the sampling grid the enlargement leaves behind.
        let smooth = monoNoise
            .transformed(by: transform)
            .applyingGaussianBlur(sigma: Double(scale * 0.5))
            .cropped(to: extent)

        // Restore and set the spread around 0.5, then keep it in range.
        let k = grainGain * strength
        let spread = CIVector(x: k, y: 0, z: 0, w: 0)
        let contrast = CIFilter.colorMatrix()
        contrast.inputImage = smooth
        contrast.rVector = spread
        contrast.gVector = spread
        contrast.bVector = spread
        contrast.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        contrast.biasVector = CIVector(x: 0.5 - 0.5 * k, y: 0.5 - 0.5 * k, z: 0.5 - 0.5 * k, w: 0)
        return contrast.outputImage?.applyingFilter("CIColorClamp").cropped(to: extent)
    }
}
