import CoreImage
import CoreImage.CIFilterBuiltins

/// The film emulation pipeline, black & white or colour. Pure Core Image, so the exact
/// same recipe runs on the live viewfinder and on the full-resolution photo.
///
/// Grain size is expressed relative to the image's long side, so a 1,500 px
/// preview and a 4,000 px still end up with the same-looking grain.
enum FilmLook {
    /// - Parameter stamp: date-back text to burn into the frame (before grain/vignette), if any.
    static func apply(_ stock: FilmStock, to input: CIImage, stamp: String? = nil) -> CIImage {
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
        // 0b. Lens effects (FX): fisheye, swirl, tilt-shift, zoom, drag, double, prism...
        lens = LensFX.lens(lens, stock: stock)

        // 1. Black & white: spectral response -> monochrome (in Core Image's linear working
        //    space). Colour: the scene as it is.
        var image: CIImage
        if stock.color {
            image = lens.clampedToExtent().applyingFilter("CIColorClamp").cropped(to: extent)
        } else {
            let mix = CIVector(x: stock.red, y: stock.green, z: stock.blue, w: 0)
            let mono = CIFilter.colorMatrix()
            mono.inputImage = lens
            mono.rVector = mix
            mono.gVector = mix
            mono.bVector = mix
            mono.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            image = mono.outputImage!.clampedToExtent().applyingFilter("CIColorClamp").cropped(to: extent)
        }

        // 2. Work in gamma-encoded space for the tonal/print steps (curves behave like a darkroom).
        image = image.applyingFilter("CILinearToSRGBToneCurve")

        // 2b. Colour: white balance before the curve, like the film's own colour response.
        let natural = image
        if stock.color, stock.warmth != 0 || stock.tint != 0 {
            image = whiteBalance(image, warmth: stock.warmth, tint: stock.tint)
        }

        // 3. Characteristic curve: S-curve for contrast, mid-tone key, lifted blacks, dimmed whites.
        image = toneCurve(image, stock: stock)

        // 3'. Colour: the grade (RGB curves, aqua blues, saturation, split toning), then
        //     STRENGTH mixes the film's whole colour and tone back toward the scene as shot.
        if stock.color {
            image = grade(image, stock.grade)
            let strength = min(max(stock.strength, 0), 1)
            if strength < 1 {
                let mix = CIFilter.dissolveTransition()
                mix.inputImage = natural
                mix.targetImage = image
                mix.time = Float(strength)
                image = mix.outputImage?.cropped(to: extent) ?? image
            }
        }

        // 3a. Uneven chemical fog (old / expired film): soft blotches lifting the shadows.
        if stock.fog > 0 {
            image = addFog(to: image, amount: stock.fog)
        }

        // 3b. Highlight glow (diffusion / halation-like bloom around bright areas).
        if stock.bloom > 0 {
            image = bloom(image, amount: stock.bloom)
        }
        // 3b'. Colour: halation, the red-orange fringe around bright lights.
        if stock.color, stock.halation > 0 {
            image = bloom(image, amount: stock.halation, tint: (1, 0.36, 0.16), threshold: 0.78, spread: 0.008)
        }

        // 3c. Print effects (FX): halftone dots, etched lines.
        image = LensFX.print(image, stock: stock)

        // 4. Black & white: print toning (split: separate ink, mid and paper colours).
        if !stock.color, stock.toneAmount > 0, stock.tone != .neutral {
            image = tone(image, toning: stock.tone, amount: stock.toneAmount)
        }

        // 4b. Date back: exposed onto the film, so grain and vignette land on it too.
        if let stamp {
            image = DateStamp.burn(stamp, into: image)
        }

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
            v.intensity = Float(min(stock.vignette, 1.2) * 0.8)
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

    /// Soft glow around highlights: keep what's above `threshold`, blur it wide (`spread`
    /// of the long side), tint it, screen it back on.
    private static func bloom(_ image: CIImage, amount: CGFloat,
                              tint: (CGFloat, CGFloat, CGFloat) = (1, 1, 1),
                              threshold: CGFloat = 0.7, spread: CGFloat = 0.015) -> CIImage {
        let extent = image.extent
        let longSide = max(extent.width, extent.height)
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
            .applyingGaussianBlur(sigma: Double(longSide * spread))
            .cropped(to: extent)

        // A tinted glow takes its brightness from the highlights' luminance.
        let strength = CIFilter.colorMatrix()
        strength.inputImage = glow
        if tint == (1, 1, 1) {
            strength.rVector = CIVector(x: amount, y: 0, z: 0, w: 0)
            strength.gVector = CIVector(x: 0, y: amount, z: 0, w: 0)
            strength.bVector = CIVector(x: 0, y: 0, z: amount, w: 0)
        } else {
            let luma: (CGFloat, CGFloat, CGFloat) = (0.2126, 0.7152, 0.0722)
            func row(_ k: CGFloat) -> CIVector {
                CIVector(x: amount * k * luma.0, y: amount * k * luma.1, z: amount * k * luma.2, w: 0)
            }
            strength.rVector = row(tint.0)
            strength.gVector = row(tint.1)
            strength.bVector = row(tint.2)
        }
        strength.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)

        let screen = CIFilter.screenBlendMode()
        screen.inputImage = strength.outputImage
        screen.backgroundImage = image
        return screen.outputImage?.cropped(to: extent) ?? image
    }

    /// Contrast is an S around the mid point; `key` slides the mid tones down (low key,
    /// moody) or up (high key, airy) while black and white stay put.
    static func curvePoints(contrast c: CGFloat, key k: CGFloat,
                            blackLift lo: CGFloat, whitePoint hi: CGFloat) -> [CGPoint] {
        func y(_ v: CGFloat) -> CGFloat { lo + min(max(v, 0), 1) * (hi - lo) }
        let key = min(max(k, -1), 1)
        let mid = 0.5 + 0.2 * key
        let q1 = min(max(0.25 - 0.13 * c + 0.16 * key, 0.02), mid - 0.02)
        let q3 = max(min(0.75 + 0.13 * c + 0.12 * key, 0.98), mid + 0.02)
        return [CGPoint(x: 0, y: y(0)), CGPoint(x: 0.25, y: y(q1)), CGPoint(x: 0.5, y: y(mid)),
                CGPoint(x: 0.75, y: y(q3)), CGPoint(x: 1, y: y(1))]
    }

    private static func toneCurve(_ image: CIImage, stock: FilmStock) -> CIImage {
        let p = curvePoints(contrast: stock.contrast, key: stock.key,
                            blackLift: stock.blackLift, whitePoint: stock.whitePoint)
        let curve = CIFilter.toneCurve()
        curve.inputImage = image
        curve.point0 = p[0]
        curve.point1 = p[1]
        curve.point2 = p[2]
        curve.point3 = p[3]
        curve.point4 = p[4]
        return curve.outputImage ?? image
    }

    /// White balance on gamma-encoded colour: warm adds red and takes blue, tint trades
    /// green for magenta.
    private static func whiteBalance(_ image: CIImage, warmth w: CGFloat, tint t: CGFloat) -> CIImage {
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = image
        matrix.rVector = CIVector(x: 1 + 0.12 * w + 0.04 * t, y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: 0, y: 1 + 0.02 * w - 0.07 * t, z: 0, w: 0)
        matrix.bVector = CIVector(x: 0, y: 0, z: 1 - 0.14 * w + 0.04 * t, w: 0)
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        return matrix.outputImage?.applyingFilter("CIColorClamp") ?? image
    }

    /// Apply a colour grade through a colour cube built from it (cached: the live view
    /// renders every frame, and the cube only changes when the film's settings do).
    private static func grade(_ image: CIImage, _ grade: ColorGrade) -> CIImage {
        guard !grade.isIdentity else { return image }
        let cube = CIFilter.colorCube()
        cube.inputImage = image
        cube.cubeDimension = Float(cubeSize)
        cube.cubeData = cubeData(for: grade)
        return cube.outputImage ?? image
    }

    private static let cubeSize = 33
    private static let cubeLock = NSLock()
    private static var cubes: [ColorGrade: Data] = [:]

    private static func cubeData(for grade: ColorGrade) -> Data {
        cubeLock.lock()
        defer { cubeLock.unlock() }
        if let data = cubes[grade] { return data }
        if cubes.count > 12 { cubes.removeAll() }   // dialling a setting makes a new one each step
        let data = grade.cubeData(size: cubeSize)
        cubes[grade] = data
        return data
    }

    /// Tone the grey print: each channel follows a quadratic through the toning's ink,
    /// mid and paper colours (see `Toning.coefficients`).
    private static func tone(_ image: CIImage, toning: Toning, amount: CGFloat) -> CIImage {
        let k = toning.coefficients(amount: amount)
        let poly = CIFilter.colorPolynomial()
        poly.inputImage = image
        poly.redCoefficients = CIVector(x: k.r.0, y: k.r.1, z: k.r.2, w: 0)
        poly.greenCoefficients = CIVector(x: k.g.0, y: k.g.1, z: k.g.2, w: 0)
        poly.blueCoefficients = CIVector(x: k.b.0, y: k.b.1, z: k.b.2, w: 0)
        poly.alphaCoefficients = CIVector(x: 0, y: 1, z: 0, w: 0)
        return poly.outputImage?.applyingFilter("CIColorClamp") ?? image
    }

    /// Large, soft blotches of fog laid over the print, strongest in the shadows (where
    /// fog shows on a real negative-to-print chain). Fixed pattern, so the live view
    /// doesn't flicker; scaled to the image so preview and print match.
    private static func addFog(to image: CIImage, amount: CGFloat) -> CIImage {
        let extent = image.extent
        let longSide = max(extent.width, extent.height)
        guard let random = CIFilter.randomGenerator().outputImage else { return image }
        // Blur a 12 x 12 patch of noise while it's tiny (cheap), then stretch it over
        // the frame: ~7 soft blotches across the long side.
        let cells = longSide / 7
        let patch = CGRect(x: 0, y: 0, width: 12, height: 12)
        let blotches = random.settingAlphaOne(in: patch.insetBy(dx: -4, dy: -4))
            .applyingGaussianBlur(sigma: 0.9)
            .cropped(to: patch)
            .transformed(by: CGAffineTransform(scaleX: cells, y: cells)
                .concatenating(CGAffineTransform(translationX: extent.minX - cells, y: extent.minY - cells)))
            .applyingGaussianBlur(sigma: Double(cells * 0.25))
            .cropped(to: extent)

        // Red channel of the noise (mean 0.5) -> fog 0 ... lift, with the blotches
        // stretched (x4) so they read after the blur evened them out.
        let lift = CGFloat(0.22) * min(max(amount, 0), 1)
        let fog = CIFilter.colorMatrix()
        fog.inputImage = blotches
        let w = CIVector(x: lift * 4, y: 0, z: 0, w: 0)
        fog.rVector = w; fog.gVector = w; fog.bVector = w
        fog.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        fog.biasVector = CIVector(x: -lift * 1.5, y: -lift * 1.5, z: -lift * 1.5, w: 0)
        guard let layer = fog.outputImage?.applyingFilter("CIColorClamp") else { return image }

        // Screen: lifts shadows a lot, highlights hardly at all.
        let screen = CIFilter.screenBlendMode()
        screen.inputImage = layer
        screen.backgroundImage = image
        return screen.outputImage?.cropped(to: extent) ?? image
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
