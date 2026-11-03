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
        /// Strength of the anodised speckle. Light specks read as dust on dark faces,
        /// so darker finishes get much less.
        let grain: Double
    }

    var palette: Palette {
        switch self {
        case .copper:
            return Palette(faceTop: rgb(0.92, 0.43, 0.13), faceBottom: rgb(0.80, 0.37, 0.11),
                           bevelLight: rgb(1.00, 0.72, 0.48), bevelDark: rgb(0.42, 0.17, 0.04),
                           accent: rgb(0.92, 0.45, 0.13), grain: 1.0)          // 6.0:1
        case .silver:
            return Palette(faceTop: rgb(0.80, 0.80, 0.79), faceBottom: rgb(0.62, 0.62, 0.61),
                           bevelLight: rgb(0.97, 0.97, 0.96), bevelDark: rgb(0.30, 0.30, 0.30),
                           accent: rgb(0.85, 0.85, 0.83), grain: 0.6)          // 12.6:1
        case .black:
            return Palette(faceTop: rgb(0.24, 0.24, 0.24), faceBottom: rgb(0.13, 0.13, 0.13),
                           bevelLight: rgb(0.50, 0.50, 0.50), bevelDark: rgb(0.00, 0.00, 0.00),
                           accent: rgb(0.90, 0.90, 0.88), grain: 0.15)          // 14.3:1
        case .red:
            return Palette(faceTop: rgb(0.78, 0.16, 0.12), faceBottom: rgb(0.62, 0.11, 0.09),
                           bevelLight: rgb(1.00, 0.50, 0.42), bevelDark: rgb(0.30, 0.04, 0.03),
                           accent: rgb(0.95, 0.33, 0.27), grain: 0.7)          // 5.2:1
        case .cobalt:
            return Palette(faceTop: rgb(0.22, 0.40, 0.72), faceBottom: rgb(0.15, 0.29, 0.56),
                           bevelLight: rgb(0.58, 0.74, 1.00), bevelDark: rgb(0.05, 0.10, 0.25),
                           accent: rgb(0.45, 0.62, 0.95), grain: 0.55)          // 6.8:1
        case .olive:
            return Palette(faceTop: rgb(0.44, 0.50, 0.27), faceBottom: rgb(0.34, 0.39, 0.20),
                           bevelLight: rgb(0.72, 0.80, 0.52), bevelDark: rgb(0.13, 0.16, 0.06),
                           accent: rgb(0.64, 0.74, 0.40), grain: 0.55)          // 8.5:1
        case .brass:
            return Palette(faceTop: rgb(0.82, 0.66, 0.31), faceBottom: rgb(0.67, 0.52, 0.22),
                           bevelLight: rgb(1.00, 0.88, 0.58), bevelDark: rgb(0.32, 0.22, 0.06),
                           accent: rgb(0.88, 0.72, 0.36), grain: 0.9)          // 9.5:1
        }
    }
}

extension ShutterFinish {
    /// The app icon in this finish: copper is the main icon, the rest are alternates
    /// (AppIcon-Silver and so on, drawn by design/icon/make_icon.py).
    var appIconName: String? { self == .copper ? nil : "AppIcon-\(name)" }

    /// Switch the home-screen icon to this finish's, if it isn't already.
    @MainActor func applyAppIcon() {
        let app = UIApplication.shared
        guard app.supportsAlternateIcons, app.alternateIconName != appIconName else { return }
        app.setAlternateIconName(appIconName) { _ in }
    }
}

extension ShutterFinish {
    /// A small picture of this finish's shutter face for menus: the face gradient with
    /// its bevel. Rendered as an original-colour image, because menus otherwise tint
    /// icons a single flat colour.
    var swatch: UIImage {
        let size = CGSize(width: 24, height: 24)
        let p = palette
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let cg = ctx.cgContext
            let face = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
            // Dark well around the face, like the shutter's recess.
            UIColor(white: 0.04, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)).fill()
            // Face: top-to-bottom gradient.
            cg.saveGState()
            UIBezierPath(ovalIn: face).addClip()
            let colors = [UIColor(p.faceTop).cgColor, UIColor(p.faceBottom).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                cg.drawLinearGradient(gradient, start: CGPoint(x: face.midX, y: face.minY),
                                      end: CGPoint(x: face.midX, y: face.maxY), options: [])
            }
            cg.restoreGState()
            // Bevel: light along the top edge.
            let rim = UIBezierPath(arcCenter: CGPoint(x: face.midX, y: face.midY), radius: face.width / 2 - 0.6,
                                   startAngle: .pi * 1.1, endAngle: .pi * 1.9, clockwise: true)
            rim.lineWidth = 1
            UIColor(p.bevelLight).withAlphaComponent(0.7).setStroke()
            rim.stroke()
        }
        return image.withRenderingMode(.alwaysOriginal)
    }
}

private func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
    Color(red: r, green: g, blue: b)
}
