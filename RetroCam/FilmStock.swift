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
    let grain: CGFloat
    let grainSize: CGFloat

    /// Lens vignette strength 0...1.
    let vignette: CGFloat

    let paper: PaperTone
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

    static let all: [FilmStock] = [.pan50, .classic400, .push3200, .redFilter, .ortho, .sepia]
}
