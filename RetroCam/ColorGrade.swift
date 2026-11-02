import Foundation

/// The colour grade of a colour film, as a function from one colour to another:
/// per-channel curves (the RGB curves graders bend: lift green in the highlights, pull
/// blue down…), a shift of blues toward aqua or navy, saturation, and split toning
/// (a colour for the shadows, another for the highlights).
///
/// `FilmLook` bakes this into a small 3D lookup table (a colour cube) whenever the film's
/// settings change, so the live view and the photo run the same grade on the GPU. The
/// grade itself is a handful of numbers, so a film's share link stays short.
///
/// Works on gamma-encoded values (0...1), after the film's tone curve.
struct ColorGrade: Hashable {
    /// 0 = black & white, 1 = as shot, up to 1.6.
    var saturation: Double = 1
    /// Shadow and highlight colours as hues (0...1 around the colour wheel), and how
    /// strongly each tints its end of the tonal range (0...1).
    var shadowHue: Double = 0.58
    var shadowAmount: Double = 0
    var highlightHue: Double = 0.1
    var highlightAmount: Double = 0
    /// Blues toward aqua (+) or navy (-), -1...1.
    var aqua: Double = 0
    /// Colour unity, 0...1: hues near `unifyHue` are pulled toward it and colours far
    /// from it are muted, so a whole frame sits in one colour family (earthy tans, say,
    /// with slate skies). Greys and whites stay clean.
    var unify: Double = 0
    var unifyHue: Double = 0.11
    /// Per-channel curve bends, -1...1: how far each channel is lifted (+) or lowered (-)
    /// in its shadows (a third of the way up) and its highlights (two thirds up). Black
    /// and white stay put.
    var redShadows: Double = 0, redHighlights: Double = 0
    var greenShadows: Double = 0, greenHighlights: Double = 0
    var blueShadows: Double = 0, blueHighlights: Double = 0

    /// Leaves every colour as it is.
    var isIdentity: Bool {
        saturation == 1 && shadowAmount == 0 && highlightAmount == 0 && aqua == 0 && unify == 0
            && redShadows == 0 && redHighlights == 0 && greenShadows == 0
            && greenHighlights == 0 && blueShadows == 0 && blueHighlights == 0
    }

    /// How far a full curve bend moves a channel at its peak.
    static let curveReach = 0.08
    /// How far full split toning moves a colour toward its tint.
    static let toneReach = 0.3

    /// Grade one colour (each channel 0...1).
    func map(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        // 1. Per-channel curves: bumps peaking at 1/3 and 2/3 that are zero at 0 and 1.
        func bend(_ x: Double, _ low: Double, _ high: Double) -> Double {
            let lowWeight = 6.75 * x * (1 - x) * (1 - x)
            let highWeight = 6.75 * x * x * (1 - x)
            return clamp(x + Self.curveReach * (low * lowWeight + high * highWeight))
        }
        var r = bend(r, redShadows, redHighlights)
        var g = bend(g, greenShadows, greenHighlights)
        var b = bend(b, blueShadows, blueHighlights)

        // 2. Blues toward aqua or navy: a hue shift that only touches blue-ish colours.
        if aqua != 0 {
            var (h, s, v) = Self.hsv(r, g, b)
            if s > 0.02 {
                let distance = abs(Self.hueDistance(h, 0.6))     // 0.6 = 216°, sky blue
                let weight = max(0, 1 - distance / 0.14)
                h = (h - aqua * 0.045 * weight * weight).truncatingRemainder(dividingBy: 1)
                if h < 0 { h += 1 }
                (r, g, b) = Self.rgb(h, s, v)
            }
        }

        // 2b. Unity: pull nearby hues toward one, mute the far ones (they're not rotated,
        //     which would sweep a blue sky through green), and keep brightness.
        if unify > 0 {
            let (h, s, v) = Self.hsv(r, g, b)
            if s > 0.01 {
                let before = Self.luma(r, g, b)
                let d = Self.hueDistance(h, unifyHue), ad = abs(d)
                let near = max(0, 1 - ad / 0.25)               // within 90°
                let far = min(max((ad - 0.08) / 0.3, 0), 1)    // beyond ~30°
                var h2 = (h - d * unify * 0.6 * near).truncatingRemainder(dividingBy: 1)
                if h2 < 0 { h2 += 1 }
                (r, g, b) = Self.rgb(h2, s * (1 - unify * 0.85 * far), v)
                let shift = before - Self.luma(r, g, b)
                r = clamp(r + shift); g = clamp(g + shift); b = clamp(b + shift)
            }
        }

        // 3. Saturation around luminance.
        let y = Self.luma(r, g, b)
        if saturation != 1 {
            r = clamp(y + saturation * (r - y))
            g = clamp(y + saturation * (g - y))
            b = clamp(y + saturation * (b - y))
        }

        // 4. Split toning: shadows lean toward one hue, highlights toward another, without
        //    changing brightness (the tint's own luminance is taken out). Each reaches only
        //    its own half of the range and fades out before mid-grey, so mid-tones (and
        //    skin) keep their colour, and a dim room isn't tinted all over.
        if shadowAmount > 0 || highlightAmount > 0 {
            let s = max(0, 1 - y / 0.5), h = max(0, (y - 0.5) / 0.5)
            let shadowWeight = shadowAmount * s * s
            let highlightWeight = highlightAmount * h * h
            let st = Self.tint(shadowHue), ht = Self.tint(highlightHue)
            r = clamp(r + Self.toneReach * (shadowWeight * st.0 + highlightWeight * ht.0))
            g = clamp(g + Self.toneReach * (shadowWeight * st.1 + highlightWeight * ht.1))
            b = clamp(b + Self.toneReach * (shadowWeight * st.2 + highlightWeight * ht.2))
        }
        return (r, g, b)
    }

    /// The grade as colour-cube data for Core Image's CIColorCube: `size`³ RGBA floats,
    /// red changing fastest, then green, then blue.
    func cubeData(size: Int = 33) -> Data {
        var floats = [Float](repeating: 1, count: size * size * size * 4)
        let step = 1 / Double(size - 1)
        var i = 0
        for bi in 0..<size {
            for gi in 0..<size {
                for ri in 0..<size {
                    let (r, g, b) = map(Double(ri) * step, Double(gi) * step, Double(bi) * step)
                    floats[i] = Float(r); floats[i + 1] = Float(g); floats[i + 2] = Float(b)
                    i += 4
                }
            }
        }
        return floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    // MARK: Colour helpers

    static func luma(_ r: Double, _ g: Double, _ b: Double) -> Double {
        0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// A fully saturated colour of this hue, minus its own luminance: the direction to
    /// push a colour to tint it without brightening or darkening it.
    static func tint(_ hue: Double) -> (Double, Double, Double) {
        let (r, g, b) = rgb(hue, 1, 1)
        let y = luma(r, g, b)
        return (r - y, g - y, b - y)
    }

    static func hueDistance(_ a: Double, _ b: Double) -> Double {
        var d = a - b
        if d > 0.5 { d -= 1 }
        if d < -0.5 { d += 1 }
        return d
    }

    static func hsv(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let hi = max(r, g, b), lo = min(r, g, b), d = hi - lo
        var h = 0.0
        if d > 0 {
            if hi == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if hi == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, hi == 0 ? 0 : d / hi, hi)
    }

    static func rgb(_ h: Double, _ s: Double, _ v: Double) -> (Double, Double, Double) {
        let c = v * s
        let hh = (h.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * 6
        let x = c * (1 - abs(hh.truncatingRemainder(dividingBy: 2) - 1))
        let m = v - c
        let (r, g, b): (Double, Double, Double)
        switch hh {
        case ..<1: (r, g, b) = (c, x, 0)
        case ..<2: (r, g, b) = (x, c, 0)
        case ..<3: (r, g, b) = (0, c, x)
        case ..<4: (r, g, b) = (0, x, c)
        case ..<5: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        return (r + m, g + m, b + m)
    }
}

private func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
