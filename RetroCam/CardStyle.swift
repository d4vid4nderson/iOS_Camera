import SwiftUI
import UIKit

private extension Font {
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// How a share card (a profile's or a roll's) looks: LIGHT (cream paper, the original),
/// DARK (the app's near-black), or SLIDE (each photo in a cream slide mount on near-black,
/// like the SLIDE border). Picked when sharing; remembered for next time.
enum CardStyle: String, CaseIterable, Identifiable {
    case light, dark, slide

    var id: String { rawValue }
    var label: String { rawValue.uppercased() }

    static let storageKey = "card.style"

    var background: UIColor {
        switch self {
        case .light: return UIColor(red: 0.961, green: 0.953, blue: 0.937, alpha: 1)
        case .dark, .slide: return UIColor(red: 0.059, green: 0.051, blue: 0.047, alpha: 1)
        }
    }
    var ink: UIColor {
        self == .light ? UIColor(white: 0.067, alpha: 1) : UIColor(red: 0.95, green: 0.93, blue: 0.89, alpha: 1)
    }
    var muted: UIColor {
        self == .light ? UIColor(red: 0.50, green: 0.486, blue: 0.463, alpha: 1) : UIColor(red: 0.62, green: 0.59, blue: 0.55, alpha: 1)
    }
    /// Behind an empty grid, and a headshot without a photo.
    var placeholder: UIColor {
        self == .light ? UIColor(white: 0.88, alpha: 1) : UIColor(white: 0.14, alpha: 1)
    }
    var avatarFill: UIColor { self == .light ? UIColor(white: 0.86, alpha: 1) : UIColor(white: 0.22, alpha: 1) }

    private static let mount = UIColor(red: 0.925, green: 0.89, blue: 0.81, alpha: 1)
    private static let mountShade = UIColor(red: 0.866, green: 0.82, blue: 0.714, alpha: 1)

    private static let mountInk = UIColor(red: 0.227, green: 0.176, blue: 0.122, alpha: 1)

    /// A cream slide mount filling `rect` (a light-to-dark sweep, rounded corners, an
    /// optional label printed across the wider top band). Returns the window inside it.
    private func drawMount(in rect: CGRect, label: String? = nil, context cg: CGContext) -> CGRect {
        let side = min(rect.width, rect.height) * 0.11
        let mount = UIBezierPath(roundedRect: rect, cornerRadius: min(rect.width, rect.height) * 0.06)
        cg.saveGState()
        mount.addClip()
        let colors = [Self.mount.cgColor, Self.mountShade.cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            cg.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.minY), end: CGPoint(x: rect.maxX, y: rect.maxY), options: [])
        }
        cg.restoreGState()
        let window = CGRect(x: rect.minX + side, y: rect.minY + side * 1.35,
                            width: rect.width - 2 * side, height: rect.height - side * 2.35)
        if let label {
            let font = UIFont.monospacedSystemFont(ofSize: side * 0.36, weight: .bold)
            let y = rect.minY + (side * 1.35 - font.lineHeight) / 2
            FilmCodeCard.draw(label, font: font, color: Self.mountInk, at: CGPoint(x: window.minX, y: y), kern: side * 0.04)
            let count = "36"
            let w = (count as NSString).size(withAttributes: [.font: font]).width
            FilmCodeCard.draw(count, font: font, color: Self.mountInk, at: CGPoint(x: window.maxX - w, y: y))
        }
        return window
    }

    /// A photo in `rect`, cropped to fill it: rounded on LIGHT and DARK, in a slide mount on SLIDE.
    func drawPhoto(_ image: UIImage, in rect: CGRect, context cg: CGContext) {
        var window = rect
        if self == .slide {
            // The mount fills the cell; the picture sits in a window with a wider top.
            window = drawMount(in: rect, context: cg)
        }
        cg.saveGState()
        UIBezierPath(roundedRect: window, cornerRadius: self == .slide ? window.width * 0.03 : 10).addClip()
        let scale = max(window.width / image.size.width, window.height / image.size.height)
        let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: CGRect(x: window.midX - drawn.width / 2, y: window.midY - drawn.height / 2,
                              width: drawn.width, height: drawn.height))
        cg.restoreGState()
    }

    /// Nothing to show yet: the Film Exposures icon, large, on a soft panel (LIGHT, DARK)
    /// or in the window of a labelled slide mount (SLIDE).
    func drawEmpty(in rect: CGRect, context cg: CGContext) {
        var area = rect
        if self == .slide {
            area = drawMount(in: rect, label: "FILM EXPOSURES", context: cg)
            UIColor(red: 0.09, green: 0.08, blue: 0.07, alpha: 1).setFill()
            UIBezierPath(roundedRect: area, cornerRadius: min(area.width, area.height) * 0.03).fill()
        } else {
            placeholder.setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 12).fill()
        }
        guard let logo = UIImage(named: "CardLogo") else { return }
        let side = min(area.width, area.height) * 0.62
        let logoRect = CGRect(x: area.midX - side / 2, y: area.midY - side / 2, width: side, height: side)
        UIGraphicsGetCurrentContext()?.saveGState()
        UIBezierPath(roundedRect: logoRect, cornerRadius: side * 0.225).addClip()
        logo.draw(in: logoRect)
        UIGraphicsGetCurrentContext()?.restoreGState()
    }

    /// The link's code: dark on the card on LIGHT; on a light tile otherwise, so every
    /// camera can read it.
    func drawCode(_ modules: [[Bool]], in rect: CGRect, context cg: CGContext) {
        if self == .light {
            FilmCodeCard.drawCode(modules, in: rect, ink: ink, paper: background, context: cg)
            return
        }
        let paper = UIColor(red: 0.95, green: 0.93, blue: 0.89, alpha: 1)
        paper.setFill()
        UIBezierPath(roundedRect: rect.insetBy(dx: -14, dy: -14), cornerRadius: 18).fill()
        FilmCodeCard.drawCode(modules, in: rect, ink: UIColor(white: 0.067, alpha: 1), paper: paper, context: cg)
    }
}

/// A share card that can be drawn in any style, with the link it goes out with.
struct CardShare {
    let link: URL
    let make: (CardStyle) -> UIImage?
}

/// The share sheet for `ShareItems`: straight to the system sheet, or, for a card that
/// comes in styles, a preview with LIGHT / DARK / SLIDE first.
struct ShareSheetView: View {
    let item: ShareItems

    var body: some View {
        if let card = item.card {
            CardShareSheet(card: card, activities: item.activities)
        } else {
            ActivityView(items: item.items, activities: item.activities).ignoresSafeArea()
        }
    }
}

/// Pick how the card looks, then share it (with its link) through the system sheet.
struct CardShareSheet: View {
    let card: CardShare
    let activities: [UIActivity]
    @AppStorage(CardStyle.storageKey) private var styleName = CardStyle.light.rawValue
    @State private var image: UIImage?
    @State private var sharing: ShareItems?
    @Environment(\.dismiss) private var dismiss

    private let accent = Color(red: 0.91, green: 0.46, blue: 0.18)
    private var style: CardStyle { CardStyle(rawValue: styleName) ?? .light }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text("SHARE CARD").font(.mono(11, .bold)).foregroundStyle(.secondary)
                Spacer()
                Button("CANCEL") { dismiss() }.font(.mono(11, .bold)).foregroundStyle(Color(white: 0.6))
            }
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(white: 0.2), lineWidth: 1))
                        .accessibilityLabel("Card preview, \(style.label.lowercased()) style")
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
            HStack(spacing: 8) {
                ForEach(CardStyle.allCases) { option in
                    let on = option == style
                    Button { styleName = option.rawValue } label: {
                        Text(option.label).font(.mono(11, .bold))
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(Capsule().fill(on ? accent.opacity(0.18) : Color(white: 0.16)))
                            .overlay(Capsule().stroke(on ? accent : .clear, lineWidth: 1))
                            .foregroundStyle(on ? accent : .white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Button {
                sharing = ShareItems(items: [image as Any?, card.link].compactMap { $0 }, activities: activities)
            } label: {
                Text("SHARE").font(.mono(12, .bold))
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(Capsule().fill(accent))
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
            .disabled(image == nil)
        }
        .padding(20)
        .background(Color(white: 0.06).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task(id: styleName) { image = card.make(style) }
        .sheet(item: $sharing) { item in
            ActivityView(items: item.items, activities: item.activities).ignoresSafeArea()
        }
    }
}
