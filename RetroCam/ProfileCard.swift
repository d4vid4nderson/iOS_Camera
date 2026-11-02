import UIKit

/// A public profile's share card, in the same style as the roll and film cards: the
/// covers of the person's latest public rolls, their headshot and name, how many rolls and
/// frames they've shared, and a small code for the profile link. Posted with the link.
enum ProfileCard {
    static let size = FilmCodeCard.size

    /// Fetch the headshot and roll covers, then draw the card. nil if it couldn't be drawn.
    static func make(for profile: RollShare.RemoteProfile) async -> UIImage? {
        async let avatar = image(at: profile.avatar)
        let covers = await withTaskGroup(of: (Int, UIImage?).self) { group in
            for (i, roll) in profile.rolls.prefix(6).enumerated() {
                group.addTask { (i, await image(at: roll.cover)) }
            }
            var found: [(Int, UIImage)] = []
            for await (i, image) in group { if let image { found.append((i, image)) } }
            return found.sorted { $0.0 < $1.0 }.map(\.1)
        }
        let frames = profile.rolls.reduce(0) { $0 + $1.frames }
        return render(name: profile.name, avatar: await avatar, rolls: profile.rolls.count,
                      frames: frames, covers: covers, url: profile.url)
    }

    private static func image(at url: URL?) async -> UIImage? {
        guard let url, let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return UIImage(data: data)
    }

    static func render(name: String?, avatar: UIImage?, rolls: Int, frames: Int,
                       covers: [UIImage], url: URL) -> UIImage? {
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

            // The covers of their latest rolls, 3:4 like the profile grid, up to two rows of three.
            let shown = Array(covers.prefix(6))
            let width = size.width - 2 * margin
            let gap: CGFloat = 10
            let gridHeight: CGFloat = 760
            if shown.isEmpty {
                UIColor(white: 0.88, alpha: 1).setFill()
                UIBezierPath(roundedRect: CGRect(x: margin, y: margin, width: width, height: gridHeight), cornerRadius: 12).fill()
            } else {
                let columns = shown.count >= 3 ? 3 : shown.count
                let rows = shown.count > 3 ? 2 : 1
                let cellW = min((width - gap * CGFloat(columns - 1)) / CGFloat(columns),
                                ((gridHeight - gap * CGFloat(rows - 1)) / CGFloat(rows)) * 3 / 4)
                let cellH = cellW * 4 / 3
                let gridW = cellW * CGFloat(columns) + gap * CGFloat(columns - 1)
                let gridH = cellH * CGFloat(rows) + gap * CGFloat(rows - 1)
                let left = (size.width - gridW) / 2
                let top = margin + (gridHeight - gridH) / 2
                for (i, image) in shown.enumerated() {
                    let rect = CGRect(x: left + CGFloat(i % columns) * (cellW + gap),
                                      y: top + CGFloat(i / columns) * (cellH + gap), width: cellW, height: cellH)
                    cg.saveGState()
                    UIBezierPath(roundedRect: rect, cornerRadius: 10).addClip()
                    let scale = max(rect.width / image.size.width, rect.height / image.size.height)
                    let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                    image.draw(in: CGRect(x: rect.midX - drawn.width / 2, y: rect.midY - drawn.height / 2,
                                          width: drawn.width, height: drawn.height))
                    cg.restoreGState()
                }
            }

            // Headshot, name and counts.
            let textTop = margin + gridHeight + 44
            let side: CGFloat = 120
            let avatarRect = CGRect(x: margin, y: textTop, width: side, height: side)
            let displayName = (name?.isEmpty == false ? name! : "Film Exposures photographer")
            FilmCodeCard.drawAvatar(FilmCodeCard.Sharer(name: displayName, avatar: avatar), in: avatarRect,
                                    fill: UIColor(white: 0.86, alpha: 1), initialsColor: ink)
            let textX = avatarRect.maxX + 28
            let textWidth = size.width - margin - textX
            let nameFont = FilmCodeCard.fitted(displayName, weight: .bold, size: 72, minSize: 40, width: textWidth)
            FilmCodeCard.draw(displayName, font: nameFont, color: ink,
                              at: CGPoint(x: textX - 2, y: avatarRect.midY - nameFont.lineHeight + 6),
                              kern: -nameFont.pointSize * 0.02)
            let counts = "\(rolls) \(rolls == 1 ? "roll" : "rolls")  ·  \(frames) \(frames == 1 ? "frame" : "frames")"
            FilmCodeCard.draw(counts, font: .systemFont(ofSize: 29, weight: .regular), color: muted,
                              at: CGPoint(x: textX, y: avatarRect.midY + 10))

            // The link's code, and the mark.
            let codeSide: CGFloat = 180
            let codeRect = CGRect(x: size.width - margin - codeSide, y: size.height - margin - codeSide,
                                  width: codeSide, height: codeSide)
            FilmCodeCard.drawCode(modules, in: codeRect, ink: ink, paper: background, context: cg)
            let mark = UIFont.systemFont(ofSize: 22, weight: .semibold)
            let markWidth = ("FILM EXPOSURES" as NSString).size(withAttributes: [.font: mark, .kern: 1]).width
            let lineY = size.height - margin - mark.lineHeight
            FilmCodeCard.draw("FILM EXPOSURES", font: mark, color: ink, at: CGPoint(x: margin, y: lineY), kern: 1)
            FilmCodeCard.draw("Tap the link to see their rolls", font: .systemFont(ofSize: 22, weight: .regular), color: muted,
                              at: CGPoint(x: margin + markWidth + 12, y: lineY))
        }
    }
}
