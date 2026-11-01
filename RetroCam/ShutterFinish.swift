import SwiftUI

/// Anodised finishes for the shutter button. The chosen finish is also the app's accent,
/// so the frame counter, chips and toggles always match the shutter.
/// Every accent is checked for at least 4.5:1 contrast on the dark body.
enum ShutterFinish: String, CaseIterable, Identifiable {
    case copper, silver, black, red, cobalt, olive, brass

    static let storageKey = "shutterFinish"

    var id: String { rawValue }
    var name: String { rawValue.capitalized }

    struct Palette {
        let faceTop: Color
        let faceBottom: Color
        let bevelLight: Color
        let bevelDark: Color
        let accent: Color
    }

    var palette: Palette {
        switch self {
        case .copper:
            return Palette(faceTop: rgb(0.92, 0.43, 0.13), faceBottom: rgb(0.80, 0.37, 0.11),
                           bevelLight: rgb(1.00, 0.72, 0.48), bevelDark: rgb(0.42, 0.17, 0.04),
                           accent: rgb(0.92, 0.45, 0.13))          // 6.0:1
        case .silver:
            return Palette(faceTop: rgb(0.80, 0.80, 0.79), faceBottom: rgb(0.62, 0.62, 0.61),
                           bevelLight: rgb(0.97, 0.97, 0.96), bevelDark: rgb(0.30, 0.30, 0.30),
                           accent: rgb(0.85, 0.85, 0.83))          // 12.6:1
        case .black:
            return Palette(faceTop: rgb(0.24, 0.24, 0.24), faceBottom: rgb(0.13, 0.13, 0.13),
                           bevelLight: rgb(0.50, 0.50, 0.50), bevelDark: rgb(0.00, 0.00, 0.00),
                           accent: rgb(0.90, 0.90, 0.88))          // 14.3:1
        case .red:
            return Palette(faceTop: rgb(0.78, 0.16, 0.12), faceBottom: rgb(0.62, 0.11, 0.09),
                           bevelLight: rgb(1.00, 0.50, 0.42), bevelDark: rgb(0.30, 0.04, 0.03),
                           accent: rgb(0.95, 0.33, 0.27))          // 5.2:1
        case .cobalt:
            return Palette(faceTop: rgb(0.22, 0.40, 0.72), faceBottom: rgb(0.15, 0.29, 0.56),
                           bevelLight: rgb(0.58, 0.74, 1.00), bevelDark: rgb(0.05, 0.10, 0.25),
                           accent: rgb(0.45, 0.62, 0.95))          // 6.8:1
        case .olive:
            return Palette(faceTop: rgb(0.44, 0.50, 0.27), faceBottom: rgb(0.34, 0.39, 0.20),
                           bevelLight: rgb(0.72, 0.80, 0.52), bevelDark: rgb(0.13, 0.16, 0.06),
                           accent: rgb(0.64, 0.74, 0.40))          // 8.5:1
        case .brass:
            return Palette(faceTop: rgb(0.82, 0.66, 0.31), faceBottom: rgb(0.67, 0.52, 0.22),
                           bevelLight: rgb(1.00, 0.88, 0.58), bevelDark: rgb(0.32, 0.22, 0.06),
                           accent: rgb(0.88, 0.72, 0.36))          // 9.5:1
        }
    }
}

private func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
    Color(red: r, green: g, blue: b)
}
