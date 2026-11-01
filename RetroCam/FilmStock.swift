import CoreGraphics

/// A black & white "film stock": how it sees colour, how contrasty it is,
/// how much grain it has, and what paper it's printed on.
struct FilmStock: Identifiable, Hashable {
    enum PaperTone: Hashable {
        case neutral
        case warm   // sepia / fibre paper
        case cool   // selenium-ish blue-black
    }

    let id: String
    let name: String
    let iso: Int
    let blurb: String

    /// Spectral sensitivity. Weights for R, G, B (should sum to ~1).
    /// Panchromatic film is roughly luminance; a red filter darkens skies;
    /// orthochromatic film is blind to red.
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat

    /// 0 = flat, 1 = very punchy S-curve.
    let contrast: CGFloat
    /// Lifted blacks (faded print). 0 = true black.
    let blackLift: CGFloat
    /// Dimmed whites. 1 = paper white.
    let whitePoint: CGFloat

    /// Grain strength 0...1 and clump size (1 = fine).
    var grain: CGFloat
    let grainSize: CGFloat

    /// Lens vignette strength 0...1.
    let vignette: CGFloat

    let paper: PaperTone

    /// Glow around bright areas, 0...1 (diffusion / halation-like).
    var bloom: CGFloat = 0
    /// Lens softness toward the corners, 0...1.
    var edgeSoftness: CGFloat = 0
    /// Exposure push in stops, applied before the film (pushed-processing look).
    var exposure: CGFloat = 0
}

extension FilmStock {
    static let pan50 = FilmStock(
        id: "pan50", name: "PAN 50", iso: 50,
        blurb: "Fine grain, smooth tones",
        red: 0.30, green: 0.59, blue: 0.11,
        contrast: 0.15, blackLift: 0.01, whitePoint: 1.0,
        grain: 0.10, grainSize: 1.0,
        vignette: 0.25, paper: .neutral)

    static let classic400 = FilmStock(
        id: "classic400", name: "CLASSIC 400", iso: 400,
        blurb: "The everyday street film",
        red: 0.34, green: 0.50, blue: 0.16,
        contrast: 0.30, blackLift: 0.02, whitePoint: 0.98,
        grain: 0.30, grainSize: 1.4,
        vignette: 0.45, paper: .neutral)

    static let push3200 = FilmStock(
        id: "push3200", name: "PUSH 3200", iso: 3200,
        blurb: "Pushed two stops. Gritty, inky blacks",
        red: 0.36, green: 0.44, blue: 0.20,
        contrast: 0.55, blackLift: 0.0, whitePoint: 0.97,
        grain: 0.65, grainSize: 2.2,
        vignette: 0.7, paper: .neutral)

    static let redFilter = FilmStock(
        id: "red25", name: "RED FILTER", iso: 100,
        blurb: "Dramatic dark skies, glowing skin",
        red: 0.78, green: 0.22, blue: 0.0,
        contrast: 0.40, blackLift: 0.0, whitePoint: 1.0,
        grain: 0.22, grainSize: 1.2,
        vignette: 0.5, paper: .neutral)

    static let ortho = FilmStock(
        id: "ortho", name: "ORTHO 80", iso: 80,
        blurb: "Red-blind. Dark lips, moody portraits",
        red: 0.0, green: 0.50, blue: 0.50,
        contrast: 0.35, blackLift: 0.02, whitePoint: 1.0,
        grain: 0.18, grainSize: 1.1,
        vignette: 0.5, paper: .cool)

    static let sepia = FilmStock(
        id: "sepia", name: "DARKROOM SEPIA", iso: 200,
        blurb: "Faded fibre print, warm toned",
        red: 0.33, green: 0.55, blue: 0.12,
        contrast: 0.20, blackLift: 0.06, whitePoint: 0.94,
        grain: 0.28, grainSize: 1.5,
        vignette: 0.6, paper: .warm)

    // Tuned against measured tones of reference B&W film looks (Nov 2026):
    // faded vs crushed blacks, whites capped short of paper white, highlight glow,
    // softer corners.

    static let steel400 = FilmStock(
        id: "steel400", name: "STEEL 400", iso: 400,
        blurb: "Faded blacks, rich mids, glowing lights",
        red: 0.30, green: 0.55, blue: 0.15,
        contrast: 0.45, blackLift: 0.05, whitePoint: 0.95,
        grain: 0.35, grainSize: 1.3,
        vignette: 0.4, paper: .neutral,
        bloom: 0.35, edgeSoftness: 0.2)

    static let satin400 = FilmStock(
        id: "satin400", name: "SATIN 400", iso: 400,
        blurb: "Deep blacks, punchy, fine smooth grain",
        red: 0.32, green: 0.53, blue: 0.15,
        contrast: 0.60, blackLift: 0.02, whitePoint: 0.96,
        grain: 0.20, grainSize: 1.0,
        vignette: 0.3, paper: .neutral,
        bloom: 0.15, edgeSoftness: 0.1)

    static let press400 = FilmStock(
        id: "press400", name: "PRESS 400", iso: 400,
        blurb: "Pushed hard: crushed blacks, blown highs",
        red: 0.34, green: 0.48, blue: 0.18,
        contrast: 0.85, blackLift: 0.0, whitePoint: 0.96,
        grain: 0.55, grainSize: 1.8,
        vignette: 0.6, paper: .neutral,
        bloom: 0.4, edgeSoftness: 0.5, exposure: 0.4)

    static let frost400 = FilmStock(
        id: "frost400", name: "FROST 400", iso: 400,
        blurb: "Hazy and airy, soft-cornered lens",
        red: 0.30, green: 0.56, blue: 0.14,
        contrast: 0.30, blackLift: 0.06, whitePoint: 1.0,
        grain: 0.40, grainSize: 1.6,
        vignette: 0.5, paper: .neutral,
        bloom: 0.5, edgeSoftness: 0.6, exposure: 0.2)

    /// This stock with its grain scaled by the user's GRAIN setting (0 = off).
    func withGrain(scaledBy factor: Double) -> FilmStock {
        var copy = self
        copy.grain = grain * CGFloat(factor)
        return copy
    }

    static let all: [FilmStock] = [.pan50, .classic400, .steel400, .satin400, .press400, .frost400,
                                   .push3200, .redFilter, .ortho, .sepia]
}
