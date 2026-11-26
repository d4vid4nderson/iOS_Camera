import CoreGraphics
import Foundation

/// A "film stock": black & white (how it sees colour, its tonal curve, how the print is
/// toned) or colour (white balance and a colour grade, see `ColorGrade`), plus its grain
/// and the lens character it's paired with.
///
/// Every value is editable (the ADJUST panel), and a whole stock can be saved as the
/// user's own film, so the type is `Codable`. Decoding tolerates missing keys, so films
/// saved by an older build keep working when new settings are added.
struct FilmStock: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var iso: Int
    var blurb: String

    /// Spectral sensitivity: weights for R, G, B (summing to ~1). Panchromatic film is
    /// roughly luminance; a red filter darkens skies; orthochromatic film is blind to
    /// red; the infrared mix uses a negative blue weight. See `ColorFilter`.
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat

    /// 0 = flat, 1 = very punchy S-curve.
    var contrast: CGFloat
    /// Lifted blacks (faded print). 0 = true black.
    var blackLift: CGFloat
    /// Dimmed whites. 1 = paper white.
    var whitePoint: CGFloat

    /// Grain strength 0...1 and clump size (1 = fine).
    var grain: CGFloat
    var grainSize: CGFloat

    /// Lens vignette strength 0...1.2.
    var vignette: CGFloat

    /// Print toning and how strongly it's applied (0 = neutral grey).
    var tone: Toning = .neutral
    var toneAmount: CGFloat = 0

    /// Glow around bright areas, 0...1 (diffusion / halation-like).
    var bloom: CGFloat = 0
    /// Lens softness toward the corners, 0...1.
    var edgeSoftness: CGFloat = 0
    /// Exposure push in stops, applied before the film (pushed-processing look).
    var exposure: CGFloat = 0
    /// Mid-tone brightness, -1 (low key, moody) ... +1 (high key, airy).
    var key: CGFloat = 0
    /// Uneven chemical fog, as on old or expired film, 0...1.
    var fog: CGFloat = 0

    /// Optional lens / print effect (FX panel), how strong it is, and where it's centred
    /// (0...1 across and down the frame, top-left origin, like the screen).
    var effect: LensEffect = .none
    var effectAmount: CGFloat = 0.5
    var effectX: CGFloat = 0.5
    var effectY: CGFloat = 0.5

    // Colour film. When `color` is false (black & white) none of these are used.

    /// A colour film: skips the black & white conversion and the print toning.
    var color: Bool = false
    /// How much of the film's colour and tone to apply: 0 = the scene as shot, 1 = the
    /// full look.
    var strength: CGFloat = 1
    /// 0 = no colour, 1 = as seen, up to 1.6.
    var saturation: CGFloat = 1
    /// White balance: cool (-1) ... warm (+1), and green (-1) ... magenta (+1).
    var warmth: CGFloat = 0
    var tint: CGFloat = 0
    /// Split toning: shadow and highlight colours (hue 0...1) and their strength (0...1).
    var shadowHue: CGFloat = 0.58
    var shadowAmount: CGFloat = 0
    var highlightHue: CGFloat = 0.1
    var highlightAmount: CGFloat = 0
    /// Blues toward aqua (+) or navy (-).
    var aqua: CGFloat = 0
    /// Colour unity (0...1) and the hue colours gather toward. See `ColorGrade.unify`.
    var unify: CGFloat = 0
    var unifyHue: CGFloat = 0.11
    /// RGB curves: each channel lifted (+) or lowered (-) in its shadows and highlights.
    var redShadows: CGFloat = 0
    var redHighlights: CGFloat = 0
    var greenShadows: CGFloat = 0
    var greenHighlights: CGFloat = 0
    var blueShadows: CGFloat = 0
    var blueHighlights: CGFloat = 0
    /// Red-orange glow around bright lights, from light bouncing back through the film.
    var halation: CGFloat = 0

    /// This film's colour grade.
    var grade: ColorGrade {
        ColorGrade(saturation: Double(saturation),
                   shadowHue: Double(shadowHue), shadowAmount: Double(shadowAmount),
                   highlightHue: Double(highlightHue), highlightAmount: Double(highlightAmount),
                   aqua: Double(aqua), unify: Double(unify), unifyHue: Double(unifyHue),
                   redShadows: Double(redShadows), redHighlights: Double(redHighlights),
                   greenShadows: Double(greenShadows), greenHighlights: Double(greenHighlights),
                   blueShadows: Double(blueShadows), blueHighlights: Double(blueHighlights))
    }

    /// True for films the user saved (they can be renamed and deleted).
    var isCustom: Bool { id.hasPrefix(Self.customPrefix) }
    static let customPrefix = "custom-"
}

// MARK: - Lens and print effects

/// Distortions a real lens, camera or print process can make, applied live.
enum LensEffect: String, CaseIterable, Codable, Identifiable {
    case none, fisheye, swirl, tiltShift, zoomBurst, drag, double, prism, ripple, halftone, etch, kaleido

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "NONE"
        case .fisheye: return "FISHEYE"
        case .swirl: return "SWIRL"
        case .tiltShift: return "TILT-SHIFT"
        case .zoomBurst: return "ZOOM"
        case .drag: return "DRAG"
        case .double: return "DOUBLE"
        case .prism: return "PRISM"
        case .ripple: return "RIPPLE"
        case .halftone: return "HALFTONE"
        case .etch: return "ETCH"
        case .kaleido: return "KALEIDO"
        }
    }

    /// Whether the effect has a centre worth moving (drag / tilt on the viewfinder).
    var usesCenter: Bool {
        switch self {
        case .none, .drag, .halftone, .etch: return false
        default: return true
        }
    }

    /// Print-stage effects work on the developed grey image; the rest act like the lens.
    var isPrintEffect: Bool { self == .halftone || self == .etch }
}

// MARK: - Toning

/// How the print is toned: the colour of the deepest black (ink), of a mid grey and
/// of the paper white. In between, the colour follows a smooth curve through the
/// three, which gives split toning (e.g. cold shadows, warm highlights) for free.
enum Toning: String, CaseIterable, Codable, Identifiable {
    case neutral, warm, cool, selenium, split, gold, platinum, cyanotype, tintype

    var id: String { rawValue }

    var label: String {
        switch self {
        case .neutral: return "NEUTRAL"
        case .warm: return "SEPIA"
        case .cool: return "COOL"
        case .selenium: return "SELENIUM"
        case .split: return "SPLIT"
        case .gold: return "GOLD"
        case .platinum: return "PLATINUM"
        case .cyanotype: return "CYANO"
        case .tintype: return "TINTYPE"
        }
    }

    struct RGB: Hashable { var r, g, b: CGFloat }

    /// Colours at grey 0 (ink), 0.5 (mid) and 1 (paper).
    var stops: (ink: RGB, mid: RGB, paper: RGB) {
        switch self {
        case .neutral:
            return (RGB(r: 0, g: 0, b: 0), RGB(r: 0.5, g: 0.5, b: 0.5), RGB(r: 1, g: 1, b: 1))
        case .warm:       // sepia-toned fibre print
            return (RGB(r: 0.03, g: 0.015, b: 0), RGB(r: 0.57, g: 0.47, b: 0.35), RGB(r: 1, g: 0.95, b: 0.85))
        case .cool:       // blue-black developer
            return (RGB(r: 0, g: 0.005, b: 0.025), RGB(r: 0.46, g: 0.5, b: 0.56), RGB(r: 0.97, g: 1, b: 1))
        case .selenium:   // purple-brown blacks, clean whites
            return (RGB(r: 0.04, g: 0, b: 0.035), RGB(r: 0.51, g: 0.46, b: 0.49), RGB(r: 1, g: 1, b: 0.99))
        case .split:      // lith: cold shadows, peach highlights
            return (RGB(r: 0, g: 0.01, b: 0.045), RGB(r: 0.53, g: 0.48, b: 0.46), RGB(r: 1, g: 0.9, b: 0.8))
        case .gold:       // gold-toned: blue-black shadows, neutral-cool paper
            return (RGB(r: 0, g: 0.01, b: 0.04), RGB(r: 0.46, g: 0.49, b: 0.54), RGB(r: 1, g: 0.99, b: 0.97))
        case .platinum:   // warm brown-grey, soft paper
            return (RGB(r: 0.05, g: 0.04, b: 0.03), RGB(r: 0.55, g: 0.5, b: 0.44), RGB(r: 0.97, g: 0.94, b: 0.88))
        case .cyanotype:  // Prussian blue on white
            return (RGB(r: 0.02, g: 0.1, b: 0.28), RGB(r: 0.28, g: 0.45, b: 0.62), RGB(r: 0.96, g: 0.97, b: 0.95))
        case .tintype:    // dark metal-brown plate, creamy highlights
            return (RGB(r: 0.04, g: 0.03, b: 0.02), RGB(r: 0.48, g: 0.44, b: 0.38), RGB(r: 0.88, g: 0.85, b: 0.76))
        }
    }

    /// Polynomial (c0 + c1 x + c2 x^2) per channel through ink, mid and paper, blended
    /// with neutral grey by `amount`. amount 0 gives exactly c = (0, 1, 0): unchanged.
    func coefficients(amount: CGFloat) -> (r: (CGFloat, CGFloat, CGFloat),
                                           g: (CGFloat, CGFloat, CGFloat),
                                           b: (CGFloat, CGFloat, CGFloat)) {
        let a = min(max(amount, 0), 1)
        let s = stops
        func channel(_ k: CGFloat, _ m: CGFloat, _ p: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
            // Blend each stop toward neutral (0, 0.5, 1), then fit the quadratic.
            let k2 = a * k, m2 = 0.5 + a * (m - 0.5), p2 = 1 + a * (p - 1)
            return (k2, -3 * k2 + 4 * m2 - p2, 2 * k2 - 4 * m2 + 2 * p2)
        }
        return (channel(s.ink.r, s.mid.r, s.paper.r),
                channel(s.ink.g, s.mid.g, s.paper.g),
                channel(s.ink.b, s.mid.b, s.paper.b))
    }
}

// MARK: - Colour filters (spectral response presets)

/// The coloured filter in front of the lens, or the film's own colour sensitivity.
enum ColorFilter: String, CaseIterable, Identifiable {
    case pan, yellow, orange, red, green, blue, ortho, infrared

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pan: return "NONE"
        case .yellow: return "YELLOW"
        case .orange: return "ORANGE"
        case .red: return "RED"
        case .green: return "GREEN"
        case .blue: return "BLUE"
        case .ortho: return "ORTHO"
        case .infrared: return "IR"
        }
    }

    var weights: (r: CGFloat, g: CGFloat, b: CGFloat) {
        switch self {
        case .pan: return (0.30, 0.59, 0.11)
        case .yellow: return (0.42, 0.50, 0.08)      // a touch darker skies
        case .orange: return (0.58, 0.38, 0.04)
        case .red: return (0.78, 0.22, 0.0)          // dramatic skies, smooth skin
        case .green: return (0.15, 0.75, 0.10)       // lighter foliage, darker skin
        case .blue: return (0.05, 0.20, 0.75)        // wet-plate-like: bright skies, rough skin
        case .ortho: return (0.0, 0.50, 0.50)        // red-blind
        case .infrared: return (0.50, 1.30, -0.80)   // white foliage, black skies and water
        }
    }

    /// The preset these weights match (within a little tolerance), if any.
    static func matching(red: CGFloat, green: CGFloat, blue: CGFloat) -> ColorFilter? {
        allCases.first {
            let w = $0.weights
            return abs(w.r - red) < 0.035 && abs(w.g - green) < 0.035 && abs(w.b - blue) < 0.035
        }
    }
}

extension FilmStock {
    var colorFilter: ColorFilter? { ColorFilter.matching(red: red, green: green, blue: blue) }

    mutating func apply(_ filter: ColorFilter) {
        let w = filter.weights
        red = w.r; green = w.g; blue = w.b
    }
}

// MARK: - Codable (tolerant of missing keys)

extension FilmStock {
    private enum CodingKeys: String, CodingKey {
        case id, name, iso, blurb, red, green, blue, contrast, blackLift, whitePoint
        case grain, grainSize, vignette, tone, toneAmount, bloom, edgeSoftness, exposure, key, fog
        case effect, effectAmount, effectX, effectY
        case color, strength, saturation, warmth, tint, shadowHue, shadowAmount, highlightHue, highlightAmount, aqua, unify, unifyHue
        case redShadows, redHighlights, greenShadows, greenHighlights, blueShadows, blueHighlights, halation
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let base = FilmStock.classic400
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        id = try c.decode(String.self, forKey: .id)
        name = value(.name, "MY FILM")
        iso = value(.iso, 400)
        blurb = value(.blurb, "")
        red = value(.red, base.red); green = value(.green, base.green); blue = value(.blue, base.blue)
        contrast = value(.contrast, base.contrast)
        blackLift = value(.blackLift, base.blackLift)
        whitePoint = value(.whitePoint, base.whitePoint)
        grain = value(.grain, base.grain)
        grainSize = value(.grainSize, base.grainSize)
        vignette = value(.vignette, base.vignette)
        tone = value(.tone, Toning.neutral)
        toneAmount = value(.toneAmount, 0)
        bloom = value(.bloom, 0)
        edgeSoftness = value(.edgeSoftness, 0)
        exposure = value(.exposure, 0)
        key = value(.key, 0)
        fog = value(.fog, 0)
        effect = value(.effect, LensEffect.none)
        effectAmount = value(.effectAmount, 0.5)
        effectX = value(.effectX, 0.5)
        effectY = value(.effectY, 0.5)
        color = value(.color, false)
        strength = value(.strength, 1)
        saturation = value(.saturation, 1)
        warmth = value(.warmth, 0)
        tint = value(.tint, 0)
        shadowHue = value(.shadowHue, 0.58)
        shadowAmount = value(.shadowAmount, 0)
        highlightHue = value(.highlightHue, 0.1)
        highlightAmount = value(.highlightAmount, 0)
        aqua = value(.aqua, 0)
        unify = value(.unify, 0)
        unifyHue = value(.unifyHue, 0.11)
        redShadows = value(.redShadows, 0); redHighlights = value(.redHighlights, 0)
        greenShadows = value(.greenShadows, 0); greenHighlights = value(.greenHighlights, 0)
        blueShadows = value(.blueShadows, 0); blueHighlights = value(.blueHighlights, 0)
        halation = value(.halation, 0)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name)
        try c.encode(iso, forKey: .iso); try c.encode(blurb, forKey: .blurb)
        try c.encode(red, forKey: .red); try c.encode(green, forKey: .green); try c.encode(blue, forKey: .blue)
        try c.encode(contrast, forKey: .contrast); try c.encode(blackLift, forKey: .blackLift)
        try c.encode(whitePoint, forKey: .whitePoint)
        try c.encode(grain, forKey: .grain); try c.encode(grainSize, forKey: .grainSize)
        try c.encode(vignette, forKey: .vignette)
        try c.encode(tone, forKey: .tone); try c.encode(toneAmount, forKey: .toneAmount)
        try c.encode(bloom, forKey: .bloom); try c.encode(edgeSoftness, forKey: .edgeSoftness)
        try c.encode(exposure, forKey: .exposure); try c.encode(key, forKey: .key); try c.encode(fog, forKey: .fog)
        try c.encode(effect, forKey: .effect); try c.encode(effectAmount, forKey: .effectAmount)
        try c.encode(effectX, forKey: .effectX); try c.encode(effectY, forKey: .effectY)
        if color {
            try c.encode(color, forKey: .color)
            try c.encode(strength, forKey: .strength)
            try c.encode(saturation, forKey: .saturation)
            try c.encode(warmth, forKey: .warmth); try c.encode(tint, forKey: .tint)
            try c.encode(shadowHue, forKey: .shadowHue); try c.encode(shadowAmount, forKey: .shadowAmount)
            try c.encode(highlightHue, forKey: .highlightHue); try c.encode(highlightAmount, forKey: .highlightAmount)
            try c.encode(aqua, forKey: .aqua)
            try c.encode(unify, forKey: .unify); try c.encode(unifyHue, forKey: .unifyHue)
            try c.encode(redShadows, forKey: .redShadows); try c.encode(redHighlights, forKey: .redHighlights)
            try c.encode(greenShadows, forKey: .greenShadows); try c.encode(greenHighlights, forKey: .greenHighlights)
            try c.encode(blueShadows, forKey: .blueShadows); try c.encode(blueHighlights, forKey: .blueHighlights)
            try c.encode(halation, forKey: .halation)
        }
    }
}

// MARK: - The film stocks

extension FilmStock {
    // Everyday films.

    static let classic400 = FilmStock(
        id: "classic400", name: "CLASSIC 400", iso: 400,
        blurb: "The everyday street film",
        red: 0.33, green: 0.52, blue: 0.15,
        contrast: 0.42, blackLift: 0.03, whitePoint: 0.97,
        grain: 0.30, grainSize: 1.35,
        vignette: 0.4,
        bloom: 0.2, edgeSoftness: 0.12)

    static let pan50 = FilmStock(
        id: "pan50", name: "PAN 50", iso: 50,
        blurb: "Fine grain, smooth tones",
        red: 0.30, green: 0.59, blue: 0.11,
        contrast: 0.15, blackLift: 0.01, whitePoint: 1.0,
        grain: 0.10, grainSize: 1.0,
        vignette: 0.25)

    /// Bright daylight film: clean, crisp whites and deep but clean blacks, fine sharp grain.
    static let silver100 = FilmStock(
        id: "silver100", name: "SILVER 100", iso: 100,
        blurb: "Bright and crisp, fine sharp grain",
        red: 0.30, green: 0.56, blue: 0.14,
        contrast: 0.55, blackLift: 0.0, whitePoint: 1.0,
        grain: 0.14, grainSize: 0.9,
        vignette: 0.2,
        bloom: 0.1, edgeSoftness: 0.05, exposure: 0.1, key: 0.15)

    /// A modern scanned negative: lifted, matte blacks, soft highlights, medium grain.
    static let matte400 = FilmStock(
        id: "matte400", name: "MATTE 400", iso: 400,
        blurb: "Faded blacks, soft highlights",
        red: 0.31, green: 0.55, blue: 0.14,
        contrast: 0.25, blackLift: 0.16, whitePoint: 0.9,
        grain: 0.32, grainSize: 1.4,
        vignette: 0.3,
        bloom: 0.15, edgeSoftness: 0.1, key: 0.05)

    static let push3200 = FilmStock(
        id: "push3200", name: "PUSH 3200", iso: 3200,
        blurb: "Pushed hard: gritty, crushed blacks",
        red: 0.35, green: 0.46, blue: 0.19,
        contrast: 0.75, blackLift: 0.0, whitePoint: 0.97,
        grain: 0.65, grainSize: 2.1,
        vignette: 0.65,
        bloom: 0.35, edgeSoftness: 0.4, exposure: 0.3)

    // Colour films. Original looks, tuned against reference photos: a warm portrait
    // negative (highlights well below white, warm mids, neutral shadows) and four
    // cinematic grades, kept subtle: STRENGTH starts at 70, and each tint stays in its
    // own end of the tonal range so dim interiors aren't washed in one colour.

    /// Warm portrait negative: highlights that roll off below white, warm cream mids,
    /// near-neutral deep shadows, calm colour, fine grain.
    static let warm400 = FilmStock(
        id: "warm400", name: "WARM 400", iso: 400,
        blurb: "Warm skin, soft highlights",
        red: 0.33, green: 0.52, blue: 0.15,
        contrast: 0.22, blackLift: 0.03, whitePoint: 0.9,
        grain: 0.16, grainSize: 1.1,
        vignette: 0.2,
        bloom: 0.12,
        color: true, strength: 0.7, saturation: 0.9, warmth: 0.3, tint: 0.04,
        shadowHue: 0.5, shadowAmount: 0.12, highlightHue: 0.09, highlightAmount: 0.15,
        aqua: 0.25, redShadows: 0.1, redHighlights: 0.15, greenShadows: -0.1, greenHighlights: -0.05,
        blueShadows: -0.25, blueHighlights: -0.15,
        halation: 0.12)

    /// Cold northern light: deep blue shadows, quiet cool mids, a touch of warm in the
    /// light itself, blues toward aqua.
    static let north400 = FilmStock(
        id: "north400", name: "NORTH 400", iso: 400,
        blurb: "Blue shadows, a warm glow",
        red: 0.33, green: 0.52, blue: 0.15,
        contrast: 0.3, blackLift: 0.035, whitePoint: 1.0,
        grain: 0.22, grainSize: 1.3,
        vignette: 0.45,
        bloom: 0.25,
        color: true, strength: 0.7, saturation: 0.88, warmth: -0.1,
        shadowHue: 0.555, shadowAmount: 0.55, highlightHue: 0.1, highlightAmount: 0.35,
        aqua: 0.4, redShadows: -0.12, blueShadows: 0.12)

    /// Dusk turned teal-green: green lifted, blue held down in the highlights (so a
    /// violet sky goes pale gold), teal shadows.
    static let dusk800 = FilmStock(
        id: "dusk800", name: "DUSK 800", iso: 800,
        blurb: "Teal-green evenings, gold skies",
        red: 0.33, green: 0.52, blue: 0.15,
        contrast: 0.3, blackLift: 0.05, whitePoint: 0.95,
        grain: 0.3, grainSize: 1.5,
        vignette: 0.4,
        bloom: 0.3,
        color: true, strength: 0.7, saturation: 0.9, warmth: 0.05, tint: -0.06,
        shadowHue: 0.48, shadowAmount: 0.35, highlightHue: 0.13, highlightAmount: 0.25,
        aqua: 0.3, redShadows: -0.15, redHighlights: 0.1, greenShadows: 0.05, greenHighlights: 0.2,
        blueShadows: 0.1, blueHighlights: -0.4,
        halation: 0.2)

    /// Teal and orange: a firm S-curve with deep shadows, teal sea and sky, warm skin and sun.
    static let tide200 = FilmStock(
        id: "tide200", name: "TIDE 200", iso: 200,
        blurb: "Teal water, orange light",
        red: 0.33, green: 0.52, blue: 0.15,
        contrast: 0.45, blackLift: 0.02, whitePoint: 0.96,
        grain: 0.18, grainSize: 1.2,
        vignette: 0.5,
        bloom: 0.15,
        color: true, strength: 0.7, saturation: 1.0,
        shadowHue: 0.52, shadowAmount: 0.45, highlightHue: 0.08, highlightAmount: 0.4,
        aqua: 0.4, redShadows: -0.15, redHighlights: 0.1, blueShadows: 0.15, blueHighlights: -0.15,
        halation: 0.15)

    /// Golden hour: rich contrast, warm highlights and mids, deep warm shadows.
    static let golden100 = FilmStock(
        id: "golden100", name: "GOLDEN 100", iso: 100,
        blurb: "Low sun, rich and warm",
        red: 0.33, green: 0.52, blue: 0.15,
        contrast: 0.35, blackLift: 0.02, whitePoint: 0.95,
        grain: 0.12, grainSize: 1.0,
        vignette: 0.45,
        bloom: 0.35,
        color: true, strength: 0.7, saturation: 1.04, warmth: 0.3,
        shadowHue: 0.06, shadowAmount: 0.2, highlightHue: 0.1, highlightAmount: 0.45,
        redHighlights: 0.1, blueShadows: -0.05, blueHighlights: -0.15,
        halation: 0.3)

    /// Earth tones: every colour gathered into tan, khaki and olive, skies and greens
    /// muted, whites kept clean, deep blacks. Moody window light, deserts, dark suits.
    static let earth200 = FilmStock(
        id: "earth200", name: "EARTH 200", iso: 200,
        blurb: "Tan and olive, clean whites",
        red: 0.33, green: 0.52, blue: 0.15,
        contrast: 0.5, blackLift: 0.0, whitePoint: 0.97,
        grain: 0.2, grainSize: 1.2,
        vignette: 0.45,
        bloom: 0.1, key: -0.1,
        color: true, strength: 0.7, saturation: 0.85, warmth: 0.12,
        shadowHue: 0.09, shadowAmount: 0.15,
        aqua: 0, unify: 0.7, unifyHue: 0.105,
        redShadows: 0.05, blueShadows: -0.1)

    /// Bright and hazy: high key, soft contrast, warm tan mids, whites that open up,
    /// colours gathered into the same earthy family.
    static let meadow400 = FilmStock(
        id: "meadow400", name: "MEADOW 400", iso: 400,
        blurb: "Bright, hazy, sun-bleached",
        red: 0.33, green: 0.52, blue: 0.15,
        contrast: 0.22, blackLift: 0.04, whitePoint: 1.0,
        grain: 0.22, grainSize: 1.3,
        vignette: 0.2,
        bloom: 0.35, exposure: 0.15, key: 0.3,
        color: true, strength: 0.7, saturation: 0.7, warmth: 0.15,
        unify: 0.75, unifyHue: 0.115,
        halation: 0.1)

    // More colour films. Original looks again, each a familiar kind of in-camera profile
    // (natural, vivid, rosy portrait, muted, faded cinema, cold bleach, magenta, flat,
    // warm cinema, steel, teal, amber). They
    // follow the same rule as the films above: STRENGTH starts at 70.

    /// The scene as it was: gentle contrast, honest colour, almost no grain. The film to
    /// start from when making your own.
    static let standard200 = FilmStock(
        id: "standard200", name: "STANDARD 200", iso: 200,
        blurb: "Colors as they were, gentle contrast",
        red: 0.33, green: 0.52, blue: 0.15,
        contrast: 0.18, blackLift: 0.01, whitePoint: 1.0,
        grain: 0.12, grainSize: 1.0,
        vignette: 0.15,
        bloom: 0.05,
        color: true, strength: 0.7, saturation: 1.02)

    /// Loud and punchy: saturated colour on a firm S-curve, true blacks, clean whites.
    static let vivid100 = FilmStock(
        id: "vivid100", name: "VIVID 100", iso: 100,
        blurb: "Bold color, strong contrast",
        red: 0.33, green: 0.52, blue: 0.15,
        contrast: 0.55, blackLift: 0.0, whitePoint: 1.0,
        grain: 0.1, grainSize: 1.0,
        vignette: 0.25,
        bloom: 0.1,
        color: true, strength: 0.7, saturation: 1.45,
        aqua: 0.1)

    /// A modern portrait film: open shadows, a soft curve, natural colour and a faint
    /// rosy tint that is kind to skin.
    static let contemporary160 = FilmStock(
        id: "contemporary160", name: "CONTEMPORARY 160", iso: 160,
        blurb: "Open shadows, a rosy tint",
        red: 0.33, green: 0.52, blue: 0.15,
        contrast: 0.12, blackLift: 0.05, whitePoint: 0.98,
        grain: 0.14, grainSize: 1.0,
        vignette: 0.15,
        bloom: 0.18, key: 0.18,
        color: true, strength: 0.7, saturation: 0.95, warmth: 0.08, tint: 0.3,
        shadowHue: 0.97, shadowAmount: 0.2,
        redShadows: 0.25, redHighlights: 0.1, greenShadows: -0.05)

    /// Muted and composed: colour pulled well back, a quiet curve, a trace of cool green
    /// in the shadows.
    static let chrome100 = FilmStock(
        id: "chrome100", name: "CHROME 100", iso: 100,
        blurb: "Muted color, quiet contrast",
        red: 0.33, green: 0.52, blue: 0.15,
        contrast: 0.32, blackLift: 0.02, whitePoint: 0.97,
        grain: 0.14, grainSize: 1.1,
        vignette: 0.3,
        bloom: 0.05,
        color: true, strength: 0.7, saturation: 0.55, warmth: 0.05,
        shadowHue: 0.45, shadowAmount: 0.15)

    /// An old cinema print: firm contrast, colour worn soft, warm and slightly washed
    /// out, blacks that never quite reach black.
    static let classic250 = FilmStock(
        id: "classic250", name: "CLASSIC 250", iso: 250,
        blurb: "Warm and faded, firm contrast",
        red: 0.33, green: 0.52, blue: 0.15,
        contrast: 0.55, blackLift: 0.07, whitePoint: 0.93,
        grain: 0.28, grainSize: 1.4,
        vignette: 0.4,
        bloom: 0.2,
        color: true, strength: 0.7, saturation: 0.72, warmth: 0.3,
        shadowHue: 0.08, shadowAmount: 0.2, highlightHue: 0.12, highlightAmount: 0.3,
        redShadows: 0.12, blueShadows: -0.12, blueHighlights: -0.1,
        halation: 0.15)

    /// Cold and washed out: colour drained, blue air in the shadows and the light, a
    /// firm curve and visible grain.
    static let bleach400 = FilmStock(
        id: "bleach400", name: "BLEACH 400", iso: 400,
        blurb: "Drained color, cold blue air",
        red: 0.33, green: 0.52, blue: 0.15,
        contrast: 0.42, blackLift: 0.03, whitePoint: 0.98,
        grain: 0.3, grainSize: 1.4,
        vignette: 0.4,
        bloom: 0.1,
        color: true, strength: 0.7, saturation: 0.5, warmth: -0.4,
        shadowHue: 0.6, shadowAmount: 0.45, highlightHue: 0.57, highlightAmount: 0.2,
        redShadows: -0.12, blueShadows: 0.18)

    /// Striking and modern: hard contrast, bold colour and a magenta cast through the
    /// shadows and the light.
    static let eternal400 = FilmStock(
        id: "eternal400", name: "ETERNAL 400", iso: 400,
        blurb: "Bold color, a magenta cast",
        red: 0.33, green: 0.52, blue: 0.15,
        contrast: 0.6, blackLift: 0.0, whitePoint: 1.0,
        grain: 0.2, grainSize: 1.2,
        vignette: 0.4,
        bloom: 0.15,
        color: true, strength: 0.7, saturation: 1.3, tint: 0.5,
        shadowHue: 0.85, shadowAmount: 0.4, highlightHue: 0.9, highlightAmount: 0.2,
        greenShadows: -0.2, greenHighlights: -0.12)

    /// A light, even base: low contrast, highlights held back, clean colour just under
    /// natural. Good for flat light, and for building your own film on.
    static let pure100 = FilmStock(
        id: "pure100", name: "PURE 100", iso: 100,
        blurb: "Light and even, soft highlights",
        red: 0.33, green: 0.52, blue: 0.15,
        contrast: 0.08, blackLift: 0.03, whitePoint: 0.95,
        grain: 0.08, grainSize: 1.0,
        vignette: 0.1,
        bloom: 0.05, key: 0.05,
        color: true, strength: 0.7, saturation: 0.92)

    /// Motion-picture warmth: gentle contrast, highlights that roll off, a warm balanced
    /// palette and a little glow around lights.
    static let cine500 = FilmStock(
        id: "cine500", name: "CINE 500", iso: 500,
        blurb: "Warm and gentle, like a film print",
        red: 0.33, green: 0.52, blue: 0.15,
        contrast: 0.2, blackLift: 0.04, whitePoint: 0.93,
        grain: 0.24, grainSize: 1.3,
        vignette: 0.3,
        bloom: 0.25,
        color: true, strength: 0.7, saturation: 0.92, warmth: 0.22, tint: 0.03,
        shadowHue: 0.55, shadowAmount: 0.1, highlightHue: 0.1, highlightAmount: 0.2,
        redHighlights: 0.08, blueHighlights: -0.12,
        halation: 0.25)

    /// Cool and steely: restrained colour, smooth contrast, shadows opened up, clear
    /// bright lights.
    static let silver400 = FilmStock(
        id: "silver400", name: "SILVER 400", iso: 400,
        blurb: "Cool and steely, open shadows",
        red: 0.33, green: 0.52, blue: 0.15,
        contrast: 0.25, blackLift: 0.05, whitePoint: 1.0,
        grain: 0.2, grainSize: 1.2,
        vignette: 0.3,
        bloom: 0.1, key: 0.1,
        color: true, strength: 0.7, saturation: 0.75, warmth: -0.2,
        shadowHue: 0.6, shadowAmount: 0.2, highlightHue: 0.58, highlightAmount: 0.1,
        blueShadows: 0.08)

    /// Blue-green all the way through: teal shadows, a cool cast in the light, blues
    /// pulled toward aqua. Cities and coastlines.
    static let teal200 = FilmStock(
        id: "teal200", name: "TEAL 200", iso: 200,
        blurb: "Cool blue-green, calm and cinematic",
        red: 0.33, green: 0.52, blue: 0.15,
        contrast: 0.35, blackLift: 0.02, whitePoint: 0.98,
        grain: 0.18, grainSize: 1.2,
        vignette: 0.4,
        bloom: 0.12,
        color: true, strength: 0.7, saturation: 0.9, warmth: -0.12, tint: -0.15,
        shadowHue: 0.5, shadowAmount: 0.5, highlightHue: 0.48, highlightAmount: 0.2,
        aqua: 0.6, redShadows: -0.2, redHighlights: -0.08, greenShadows: 0.08,
        blueShadows: 0.1)

    /// A golden glow in the mids and the light, with shadows left alone: brighter and
    /// lighter than GOLDEN 100.
    static let brass200 = FilmStock(
        id: "brass200", name: "BRASS 200", iso: 200,
        blurb: "A golden glow in the light",
        red: 0.33, green: 0.52, blue: 0.15,
        contrast: 0.25, blackLift: 0.03, whitePoint: 0.97,
        grain: 0.14, grainSize: 1.1,
        vignette: 0.3,
        bloom: 0.4, key: 0.12,
        color: true, strength: 0.7, saturation: 1.05, warmth: 0.4,
        highlightHue: 0.11, highlightAmount: 0.55,
        redHighlights: 0.15, blueHighlights: -0.3,
        halation: 0.3)

    static let noir = FilmStock(
        id: "noir", name: "NOIR 400", iso: 400,
        blurb: "Low key: deep shadows, bright highlights",
        red: 0.32, green: 0.55, blue: 0.13,
        contrast: 0.7, blackLift: 0.0, whitePoint: 1.0,
        grain: 0.35, grainSize: 1.4,
        vignette: 0.8,
        bloom: 0.25, edgeSoftness: 0.15, key: -0.45)

    // Darkroom prints.

    static let expired = FilmStock(
        id: "expired", name: "EXPIRED 200", iso: 200,
        blurb: "Foggy, flat and grainy. Out of date in '98",
        red: 0.36, green: 0.50, blue: 0.14,
        contrast: 0.1, blackLift: 0.14, whitePoint: 0.88,
        grain: 0.6, grainSize: 2.0,
        vignette: 0.55,
        tone: .warm, toneAmount: 0.25,
        bloom: 0.3, edgeSoftness: 0.3, key: 0.1, fog: 0.6)

    /// This stock with its grain scaled by the user's GRAIN setting (0 = off).
    func withGrain(scaledBy factor: Double) -> FilmStock {
        var copy = self
        copy.grain = grain * CGFloat(factor)
        return copy
    }

    /// Built-in films, in picker order (the picker shows black & white and colour films on
    /// separate shelves: seven black & white, nineteen colour).
    static let all: [FilmStock] = [
        .classic400, .pan50, .silver100, .push3200, .noir, .matte400, .expired,
        .warm400, .golden100, .earth200, .meadow400, .tide200, .dusk800, .north400,
        .standard200, .vivid100, .contemporary160, .chrome100, .classic250, .bleach400, .eternal400,
        .pure100, .cine500, .silver400, .teal200, .brass200,
    ]

    static func builtIn(id: String) -> FilmStock? { all.first { $0.id == id } }
}

extension FilmStock {
    /// One line for share cards: "Black & white · ISO 50 · Fine grain",
    /// "Selenium toned · ISO 100 · Medium grain".
    var shareCaption: String {
        let kind: String
        if color {
            kind = "Color"
        } else if tone == .neutral || toneAmount < 0.3 {
            kind = "Black & white"
        } else {
            let names: [Toning: String] = [
                .warm: "Sepia", .cool: "Cool", .selenium: "Selenium", .split: "Split",
                .gold: "Gold", .platinum: "Platinum", .cyanotype: "Cyanotype", .tintype: "Tintype",
            ]
            kind = "\(names[tone] ?? "Toned") toned"
        }
        let texture: String
        switch grain {
        case ..<0.2: texture = "Fine grain"
        case ..<0.45: texture = "Medium grain"
        default: texture = "Heavy grain"
        }
        return "\(kind)  ·  ISO \(iso)  ·  \(texture)"
    }
}
