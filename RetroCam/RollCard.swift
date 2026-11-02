import UIKit

/// A shared roll's card, in the same style as the film share cards: a grid of the roll's
/// first frames, the roll and its film, who shared it, and a small code for the link.
/// Posted with the link, and shown as the link's preview image.
enum RollCard {
    static let size = FilmCodeCard.size

    static func render(title: String, filmName: String?, frameCount: Int, frames: [UIImage],
                       url: URL, sharer: FilmCodeCard.Sharer?) -> UIImage? {
        guard let modules = FilmCodeCard.modules(for: url.absoluteString) else { return nil }
        let background = UIColor(red: 0.961, green: 0.953, blue: 0.937, alpha: 1)
        let ink = UIColor(white: 0.067, alpha: 1)
        let muted = UIColor(red: 0.50, green: 0.486, blue: 0.463, alpha: 1)
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
            for (i, image) in shown.enumerated() {
                let rect = CGRect(x: left + CGFloat(i % columns) * (cell + gap),
                                  y: margin + CGFloat(i / columns) * (cell + gap), width: cell, height: cell)
                cg.saveGState()
                UIBezierPath(roundedRect: rect, cornerRadius: 10).addClip()
                let scale = max(rect.width / image.size.width, rect.height / image.size.height)
                let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                image.draw(in: CGRect(x: rect.midX - drawn.width / 2, y: rect.midY - drawn.height / 2,
                                      width: drawn.width, height: drawn.height))
                cg.restoreGState()
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
            FilmCodeCard.drawCode(modules, in: codeRect, ink: ink, paper: background, context: cg)

            let mark = UIFont.systemFont(ofSize: 22, weight: .semibold)
            let markWidth = ("EXPOSURES" as NSString).size(withAttributes: [.font: mark, .kern: 1]).width
            var x = margin
            var lineY = size.height - margin - mark.lineHeight
            if let sharer {
                let side: CGFloat = 76
                let avatarRect = CGRect(x: margin, y: size.height - margin - side, width: side, height: side)
                FilmCodeCard.drawAvatar(sharer, in: avatarRect, fill: UIColor(white: 0.86, alpha: 1), initialsColor: ink)
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
            FilmCodeCard.draw("EXPOSURES", font: mark, color: sharer == nil ? ink : muted, at: CGPoint(x: x, y: lineY), kern: 1)
            FilmCodeCard.draw("Tap the link to see the roll", font: .systemFont(ofSize: 22, weight: .regular), color: muted,
                              at: CGPoint(x: x + markWidth + 12, y: lineY))
        }
    }
}
