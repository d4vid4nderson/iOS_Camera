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

        // 1. Spectral response -> monochrome (in Core Image's linear working space).
        let mix = CIVector(x: stock.red, y: stock.green, z: stock.blue, w: 0)
        let mono = CIFilter.colorMatrix()
        mono.inputImage = input
        mono.rVector = mix
        mono.gVector = mix
        mono.bVector = mix
        mono.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        var image = mono.outputImage!.clampedToExtent().applyingFilter("CIColorClamp").cropped(to: extent)

        // 2. Work in gamma-encoded space for the tonal/print steps (curves behave like a darkroom).
        image = image.applyingFilter("CILinearToSRGBToneCurve")

        // 3. Characteristic curve: S-curve for contrast, lifted blacks, dimmed whites.
        image = toneCurve(image, stock: stock)

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

    private static func addGrain(to image: CIImage, amount: CGFloat, size: CGFloat) -> CIImage {
        let extent = image.extent
        guard let noiseBase = CIFilter.randomGenerator().outputImage else { return image }

        // Random offset every call so grain "dances" between frames like real film,
        // instead of looking like dust stuck on the lens.
        let dx = CGFloat.random(in: 0..<2048)
        let dy = CGFloat.random(in: 0..<2048)
        let scale = max(1, size * max(extent.width, extent.height) / 1600)

        let noise = noiseBase
            .transformed(by: CGAffineTransform(translationX: -dx, y: -dy))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            .cropped(to: extent)

        // Monochrome noise centred on 50% grey (neutral for soft light).
        let a = amount * 0.9
        let grey = CIFilter.colorMatrix()
        grey.inputImage = noise
        grey.rVector = CIVector(x: a, y: 0, z: 0, w: 0)
        grey.gVector = CIVector(x: a, y: 0, z: 0, w: 0)
        grey.bVector = CIVector(x: a, y: 0, z: 0, w: 0)
        grey.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        grey.biasVector = CIVector(x: 0.5 - a / 2, y: 0.5 - a / 2, z: 0.5 - a / 2, w: 1)

        let blend = CIFilter.softLightBlendMode()
        blend.inputImage = grey.outputImage
        blend.backgroundImage = image
        return blend.outputImage?.cropped(to: extent) ?? image
    }
}
