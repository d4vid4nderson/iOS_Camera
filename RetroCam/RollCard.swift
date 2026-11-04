import UIKit

/// A shared roll's card, in the same style as the film share cards: a grid of the roll's
/// first frames, the roll and its film, who shared it, and a small code for the link.
/// Posted with the link, and shown as the link's preview image.
enum RollCard {
    static let size = FilmCodeCard.size

    static func render(title: String, filmName: String?, frameCount: Int, frames: [UIImage],
                       url: URL, sharer: FilmCodeCard.Sharer?, style: CardStyle = .light) -> UIImage? {
        guard let modules = FilmCodeCard.modules(for: url.absoluteString) else { return nil }
        let background = style.background
        let ink = style.ink
        let muted = style.muted
        let margin: CGFloat = 56
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            background.setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            // Contact grid: up to nine frames, square-cropped.
            let shown = Array(frames.prefix(9))
            let columns = shown.count >= 5 ? 3 : shown.count >= 2 ? 2 : 1
            let rows = max(1, Int((Double(shown.count) / Double(columns)).rounded(.up)))
            let gap: CGFloat = 8
            let width = size.width - 2 * margin
            let cell = min((width - gap * CGFloat(columns - 1)) / CGFloat(columns),
                           (900 - gap * CGFloat(rows - 1)) / CGFloat(rows))
            let gridWidth = cell * CGFloat(columns) + gap * CGFloat(columns - 1)
            let left = (size.width - gridWidth) / 2
            if shown.isEmpty {
                // No developed frames yet: the app's icon.
                style.drawEmpty(in: CGRect(x: margin, y: margin, width: width, height: cell), context: cg)
            }
            for (i, image) in shown.enumerated() {
                let rect = CGRect(x: left + CGFloat(i % columns) * (cell + gap),
                                  y: margin + CGFloat(i / columns) * (cell + gap), width: cell, height: cell)
                style.drawPhoto(image, in: rect, context: cg)
            }
            let gridBottom = margin + CGFloat(rows) * cell + CGFloat(rows - 1) * gap

            let textTop = gridBottom + 44
            let titleFont = FilmCodeCard.fitted(title, weight: .bold, size: 92, minSize: 54, width: width)
            FilmCodeCard.draw(title, font: titleFont, color: ink, at: CGPoint(x: margin - 3, y: textTop),
                              kern: -titleFont.pointSize * 0.02)
            var line = "\(frameCount) \(frameCount == 1 ? "frame" : "frames")"
            if let filmName, !filmName.isEmpty { line = "Shot on \(filmName)  ·  " + line }
            FilmCodeCard.draw(line, font: .systemFont(ofSize: 29, weight: .regular), color: muted,
                              at: CGPoint(x: margin, y: textTop + titleFont.lineHeight + 8))

            let codeSide: CGFloat = 180
            let codeRect = CGRect(x: size.width - margin - codeSide, y: size.height - margin - codeSide,
                                  width: codeSide, height: codeSide)
            style.drawCode(modules, in: codeRect, context: cg)

            let mark = UIFont.systemFont(ofSize: 22, weight: .semibold)
            let markWidth = ("FILM EXPOSURES" as NSString).size(withAttributes: [.font: mark, .kern: 1]).width
            var x = margin
            var lineY = size.height - margin - mark.lineHeight
            if let sharer {
                let side: CGFloat = 76
                let avatarRect = CGRect(x: margin, y: size.height - margin - side, width: side, height: side)
                FilmCodeCard.drawAvatar(sharer, in: avatarRect, fill: style.avatarFill, initialsColor: ink)
                x = avatarRect.maxX + 18
                let nameFont = UIFont.systemFont(ofSize: 28, weight: .semibold)
                if !sharer.name.isEmpty {
                    let top = avatarRect.midY - (nameFont.lineHeight + mark.lineHeight + 2) / 2
                    FilmCodeCard.draw(sharer.name, font: nameFont, color: ink, at: CGPoint(x: x, y: top))
                    lineY = top + nameFont.lineHeight + 2
                } else {
                    lineY = avatarRect.midY - mark.lineHeight / 2
                }
            }
            FilmCodeCard.draw("FILM EXPOSURES", font: mark, color: sharer == nil ? ink : muted, at: CGPoint(x: x, y: lineY), kern: 1)
            FilmCodeCard.draw("Tap the link to see the roll", font: .systemFont(ofSize: 22, weight: .regular), color: muted,
                              at: CGPoint(x: x + markWidth + 12, y: lineY))
        }
    }
}
