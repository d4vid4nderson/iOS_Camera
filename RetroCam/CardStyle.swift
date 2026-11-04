import SwiftUI
import UIKit

private extension Font {
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// The brand's palette: neutral greys, orange and a light grey (no warm browns). Shared by
/// the share cards, the film cards and the profile link preview.
enum Brand {
    static let dark = UIColor(white: 0.071, alpha: 1)        // #121212
    static let panel = UIColor(white: 0.141, alpha: 1)       // #242424
    static let ink = UIColor(white: 0.067, alpha: 1)         // #111111
    static let muted = UIColor(red: 0.557, green: 0.557, blue: 0.576, alpha: 1)   // #8E8E93
    static let mutedOnLight = UIColor(red: 0.43, green: 0.43, blue: 0.45, alpha: 1)
    static let light = UIColor(white: 0.949, alpha: 1)       // #F2F2F2
    static let paper = UIColor(white: 0.957, alpha: 1)       // #F4F4F4
    static let orange = UIColor(red: 0.91, green: 0.463, blue: 0.18, alpha: 1)    // #E8762E
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
        case .light: return Brand.paper
        case .dark, .slide: return Brand.dark
        }
    }
    var ink: UIColor {
        self == .light ? Brand.ink : Brand.light
    }
    var muted: UIColor {
        self == .light ? Brand.mutedOnLight : Brand.muted
    }
    /// Behind an empty grid, and a headshot without a photo.
    var placeholder: UIColor {
        self == .light ? UIColor(white: 0.88, alpha: 1) : UIColor(white: 0.14, alpha: 1)
    }
    var avatarFill: UIColor { self == .light ? UIColor(white: 0.86, alpha: 1) : UIColor(white: 0.22, alpha: 1) }

    private static let mount = UIColor(white: 0.93, alpha: 1)
    private static let mountShade = UIColor(white: 0.84, alpha: 1)

    private static let mountInk = UIColor(white: 0.25, alpha: 1)

    /// A light grey slide mount filling `rect` (a light-to-dark sweep, rounded corners, an
    /// optional label printed across the wider top band). Returns the window inside it.
    func drawMount(in rect: CGRect, label: String? = nil, context cg: CGContext) -> CGRect {
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

    /// Nothing to show yet: the brand's stripe (black, orange, light grey, as in the icon)
    /// filling the panel, with the orange dot and the FILM EXPOSURES wordmark; on SLIDE, the
    /// stripe sits in the window of a labelled mount.
    func drawEmpty(in rect: CGRect, context cg: CGContext) {
        let area = self == .slide ? drawMount(in: rect, label: "FILM EXPOSURES", context: cg) : rect
        let radius = self == .slide ? min(area.width, area.height) * 0.03 : 14
        let panel = UIBezierPath(roundedRect: area, cornerRadius: radius)
        cg.saveGState()
        panel.addClip()
        Brand.ink.setFill()
        cg.fill(area)
        // The orange band and the light edge: the icon's steep diagonal, across the panel.
        let w = area.width, h = area.height, x = area.minX, y = area.minY
        func band(_ bottom: CGFloat, _ top: CGFloat, _ topEnd: CGFloat, _ bottomEnd: CGFloat, _ colour: UIColor) {
            let path = UIBezierPath()
            path.move(to: CGPoint(x: x + w * bottom, y: y + h))
            path.addLine(to: CGPoint(x: x + w * top, y: y))
            path.addLine(to: CGPoint(x: x + w * topEnd, y: y))
            path.addLine(to: CGPoint(x: x + w * bottomEnd, y: y + h))
            path.close()
            colour.setFill()
            path.fill()
        }
        band(0.40, 0.62, 1.2, 1.2, Brand.light)
        band(0.40, 0.62, 0.80, 0.58, Brand.orange)
        cg.restoreGState()
        if self == .dark {
            // On the dark card the black panel needs an edge.
            Brand.panel.setStroke()
            panel.lineWidth = 2
            panel.stroke()
        }
        // The dot, and (outside the mount, which already carries the name) the wordmark.
        let dot = min(w, h) * 0.06
        Brand.orange.setFill()
        UIBezierPath(ovalIn: CGRect(x: x + dot * 0.9, y: y + dot * 0.9, width: dot, height: dot)).fill()
        if self != .slide {
            let film = UIFont.systemFont(ofSize: h * 0.13, weight: .heavy)
            let exposures = UIFont.monospacedSystemFont(ofSize: h * 0.06, weight: .bold)
            let bottom = y + h - h * 0.07
            FilmCodeCard.draw("EXPOSURES", font: exposures, color: Brand.orange,
                              at: CGPoint(x: x + dot * 0.9, y: bottom - exposures.lineHeight), kern: h * 0.004)
            FilmCodeCard.draw("FILM", font: film, color: Brand.light,
                              at: CGPoint(x: x + dot * 0.9 - film.pointSize * 0.04, y: bottom - exposures.lineHeight - film.lineHeight + film.pointSize * 0.12),
                              kern: -film.pointSize * 0.02)
        }
    }

    /// The link's code: dark on the card on LIGHT; on a light tile otherwise, so every
    /// camera can read it.
    func drawCode(_ modules: [[Bool]], in rect: CGRect, context cg: CGContext) {
        if self == .light {
            FilmCodeCard.drawCode(modules, in: rect, ink: ink, paper: background, context: cg)
            return
        }
        let paper = Brand.light
        paper.setFill()
        UIBezierPath(roundedRect: rect.insetBy(dx: -14, dy: -14), cornerRadius: 18).fill()
        FilmCodeCard.drawCode(modules, in: rect, ink: UIColor(white: 0.067, alpha: 1), paper: paper, context: cg)
    }
}

/// A share card that can be drawn in any style, with the link it goes out with.
struct CardShare {
    let link: URL
    /// What it is, for the words shared with it (#filmexposures and the link).
    var kind: ShareCaption.Kind = .roll
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
                Text("Share card").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                Button("Cancel") { dismiss() }.font(.system(size: 16, weight: .semibold)).foregroundStyle(accent)
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
            ChoicePills(options: CardStyle.allCases.map { ($0.rawValue, $0.rawValue.capitalized) },
                        selection: $styleName, accent: accent)
            Text(ShareCaption.text(card.kind, link: card.link))
                .font(.system(size: 13)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Posted with: \(ShareCaption.text(card.kind, link: card.link))")
            PillButton(text: "Share", filled: true, accent: accent) {
                sharing = ShareItems(items: [image.map(SharedPicture.init) as Any?, ShareCaption.text(card.kind, link: card.link)].compactMap { $0 },
                                     activities: activities)
            }
            .disabled(image == nil)
            .opacity(image == nil ? 0.5 : 1)
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

/// The words that go with anything shared outside the app: what it is, #filmexposures,
/// and a link back to it (or to the app, when there's nothing to link to). Shared as text
/// next to the picture; apps that keep text put it in the post.
enum ShareCaption {
    static let hashtag = "#filmexposures"

    enum Kind { case roll, frame, contactSheet, profile, film }

    static func text(_ kind: Kind, link: URL?) -> String {
        let line: String
        switch kind {
        case .roll, .contactSheet: line = "A roll shot on Film Exposures \(hashtag)"
        case .frame: line = "Shot on Film Exposures \(hashtag)"
        case .profile: line = "My film photos on Film Exposures \(hashtag)"
        case .film: line = "A film for Film Exposures. Tap to load it \(hashtag)"
        }
        let url = link ?? ShareLinks.base ?? URL(string: "https://\(ShareLinks.host)")
        return [line, url?.absoluteString].compactMap { $0 }.joined(separator: "\n")
    }
}

/// A picture shared through the system sheet. Instagram crops whatever it's handed to its
/// own shapes (9:16 for reels and stories, 4:5 for posts), so XPAN and 16:9 frames came
/// out as a zoomed-in middle. For Instagram the picture goes on a 9:16 near-black canvas,
/// fitted inside the middle 4:5: every Instagram shape then shows it whole. Every other
/// app gets the picture as it is.
final class SharedPicture: NSObject, UIActivityItemSource {
    let image: UIImage

    init(_ image: UIImage) { self.image = image }

    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any { image }

    func activityViewController(_ controller: UIActivityViewController,
                                itemForActivityType type: UIActivity.ActivityType?) -> Any? {
        guard let type, Self.crops(type) else { return image }
        return Self.fittedCanvas(image)
    }

    /// Share targets that crop pictures to their own shape.
    static func crops(_ type: UIActivity.ActivityType) -> Bool {
        type.rawValue.lowercased().contains("instagram")
    }

    /// The picture fitted, whole, in the middle 4:5 of a 1080×1920 canvas.
    static func fittedCanvas(_ image: UIImage) -> UIImage {
        let size = CGSize(width: 1080, height: 1920)
        let post = CGRect(x: 0, y: (size.height - 1350) / 2, width: 1080, height: 1350)
        let safe = post.insetBy(dx: 54, dy: 54)
        let source = image.size
        guard source.width > 0, source.height > 0 else { return image }
        let scale = min(safe.width / source.width, safe.height / source.height)
        let drawn = CGSize(width: source.width * scale, height: source.height * scale)
        let rect = CGRect(x: safe.midX - drawn.width / 2, y: safe.midY - drawn.height / 2,
                          width: drawn.width, height: drawn.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            Brand.dark.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            image.draw(in: rect)
        }
    }
}
