import UIKit

/// A public profile's share card, in the same style as the roll and film cards: the
/// covers of the person's latest public rolls, their headshot and name, how many rolls and
/// frames they've shared, and a small code for the profile link. Posted with the link.
enum ProfileCard {
    static let size = FilmCodeCard.size

    /// What the card shows, fetched once so it can be drawn in each style.
    struct Content {
        var name: String?
        var avatar: UIImage?
        var rolls: Int
        var frames: Int
        var covers: [UIImage]
        var url: URL
    }

    /// Fetch the headshot and roll covers, then draw the card. nil if it couldn't be drawn.
    static func make(for profile: RollShare.RemoteProfile, style: CardStyle = .light) async -> UIImage? {
        render(await content(for: profile), style: style)
    }

    static func render(_ c: Content, style: CardStyle) -> UIImage? {
        render(name: c.name, avatar: c.avatar, rolls: c.rolls, frames: c.frames, covers: c.covers, url: c.url, style: style)
    }

    /// The headshot and the covers of the latest public rolls.
    static func content(for profile: RollShare.RemoteProfile) async -> Content {
        // The card goes out to anyone: only public rolls on it, never ones shared with
        // followers or specific people (your own profile lists those too).
        let open = profile.rolls.filter { $0.audience == nil || $0.audience == "public" }
        async let avatar = image(at: profile.avatar)
        let covers = await withTaskGroup(of: (Int, UIImage?).self) { group in
            for (i, roll) in open.prefix(6).enumerated() {
                group.addTask { (i, await image(at: roll.cover)) }
            }
            var found: [(Int, UIImage)] = []
            for await (i, image) in group { if let image { found.append((i, image)) } }
            return found.sorted { $0.0 < $1.0 }.map(\.1)
        }
        let frames = open.reduce(0) { $0 + $1.frames }
        return Content(name: profile.name, avatar: await avatar, rolls: open.count, frames: frames, covers: covers, url: profile.url)
    }

    private static func image(at url: URL?) async -> UIImage? {
        guard let url, let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return UIImage(data: data)
    }

    static func render(name: String?, avatar: UIImage?, rolls: Int, frames: Int,
                       covers: [UIImage], url: URL, style: CardStyle = .light) -> UIImage? {
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

            // The covers of their latest rolls, 3:4 like the profile grid, up to two rows of three.
            let shown = Array(covers.prefix(6))
            let width = size.width - 2 * margin
            let gap: CGFloat = 10
            let gridHeight: CGFloat = 760
            if shown.isEmpty {
                style.drawEmpty(in: CGRect(x: margin, y: margin, width: width, height: gridHeight), context: cg)
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
                    style.drawPhoto(image, in: rect, context: cg)
                }
            }

            // Headshot, name and counts.
            let textTop = margin + gridHeight + 44
            let side: CGFloat = 120
            let avatarRect = CGRect(x: margin, y: textTop, width: side, height: side)
            let displayName = (name?.isEmpty == false ? name! : "Film Exposures photographer")
            FilmCodeCard.drawAvatar(FilmCodeCard.Sharer(name: displayName, avatar: avatar), in: avatarRect,
                                    fill: style.avatarFill, initialsColor: ink)
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
            style.drawCode(modules, in: codeRect, context: cg)
            let mark = UIFont.systemFont(ofSize: 22, weight: .semibold)
            let markWidth = ("FILM EXPOSURES" as NSString).size(withAttributes: [.font: mark, .kern: 1]).width
            let lineY = size.height - margin - mark.lineHeight
            FilmCodeCard.draw("FILM EXPOSURES", font: mark, color: ink, at: CGPoint(x: margin, y: lineY), kern: 1)
            FilmCodeCard.draw("Tap the link to see their rolls", font: .systemFont(ofSize: 22, weight: .regular), color: muted,
                              at: CGPoint(x: margin + markWidth + 12, y: lineY))
        }
    }

    // MARK: Link preview

    /// The picture a profile link shows in Messages, Threads, Slack… (1200×630, the shape
    /// link previews use): headshot, name, @handle, counts and up to three roll covers on
    /// the website's near-black. Only public rolls: the image is public.
    static let previewSize = CGSize(width: 1200, height: 630)

    static func makePreview(for profile: RollShare.RemoteProfile) async -> UIImage? {
        let open = profile.rolls.filter { $0.audience == nil || $0.audience == "public" }
        async let avatar = image(at: profile.avatar)
        var covers: [UIImage] = []
        for roll in open.prefix(3) {
            if let cover = await image(at: roll.cover) { covers.append(cover) }
        }
        return preview(name: profile.name, handle: profile.handle, avatar: await avatar,
                       rolls: open.count, frames: open.reduce(0) { $0 + $1.frames }, covers: covers)
    }

    static func preview(name: String?, handle: String?, avatar: UIImage?, rolls: Int, frames: Int,
                        covers: [UIImage]) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let copper = UIColor(red: 0.91, green: 0.46, blue: 0.18, alpha: 1)
        let cream = UIColor(red: 0.95, green: 0.93, blue: 0.89, alpha: 1)
        let muted = UIColor(red: 0.56, green: 0.53, blue: 0.49, alpha: 1)
        return UIGraphicsImageRenderer(size: previewSize, format: format).image { ctx in
            let g = ctx.cgContext
            UIColor(red: 0.059, green: 0.051, blue: 0.047, alpha: 1).setFill()
            g.fill(CGRect(origin: .zero, size: previewSize))

            // Who: headshot, name, handle, counts.
            let face = CGRect(x: 72, y: 96, width: 176, height: 176)
            g.saveGState()
            UIBezierPath(ovalIn: face).addClip()
            if let avatar {
                let scale = max(face.width / avatar.size.width, face.height / avatar.size.height)
                let size = CGSize(width: avatar.size.width * scale, height: avatar.size.height * scale)
                avatar.draw(in: CGRect(x: face.midX - size.width / 2, y: face.midY - size.height / 2, width: size.width, height: size.height))
            } else {
                UIColor(white: 0.2, alpha: 1).setFill()
                g.fill(face)
            }
            g.restoreGState()

            func text(_ string: String, _ font: UIFont, _ color: UIColor, at point: CGPoint, width: CGFloat) {
                let style = NSMutableParagraphStyle()
                style.lineBreakMode = .byTruncatingTail
                (string as NSString).draw(in: CGRect(x: point.x, y: point.y, width: width, height: font.lineHeight + 4),
                                          withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
            }
            let left: CGFloat = 72
            let textWidth: CGFloat = covers.isEmpty ? 1056 : 560
            let shownName = (name?.isEmpty == false ? name! : handle.map { "@\($0)" } ?? "A photographer").uppercased()
            text(shownName, .monospacedSystemFont(ofSize: 52, weight: .bold), cream, at: CGPoint(x: left, y: 306), width: textWidth)
            if let handle, name?.isEmpty == false {
                text("@\(handle)", .monospacedSystemFont(ofSize: 30, weight: .semibold), copper, at: CGPoint(x: left, y: 376), width: textWidth)
            }
            text("\(rolls) \(rolls == 1 ? "ROLL" : "ROLLS")  ·  \(frames) \(frames == 1 ? "FRAME" : "FRAMES")",
                 .monospacedSystemFont(ofSize: 24, weight: .medium), muted, at: CGPoint(x: left, y: 430), width: textWidth)
            text("FILM EXPOSURES", .monospacedSystemFont(ofSize: 22, weight: .bold), copper, at: CGPoint(x: left, y: 534), width: 400)

            // Their latest public rolls, as prints.
            let tile = CGSize(width: 168, height: 224)
            var x: CGFloat = 1200 - 72 - tile.width
            for cover in covers.prefix(3).reversed() {
                let rect = CGRect(x: x, y: (630 - tile.height) / 2, width: tile.width, height: tile.height)
                g.saveGState()
                UIBezierPath(roundedRect: rect, cornerRadius: 12).addClip()
                let scale = max(rect.width / cover.size.width, rect.height / cover.size.height)
                let size = CGSize(width: cover.size.width * scale, height: cover.size.height * scale)
                cover.draw(in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
                g.restoreGState()
                x -= tile.width + 20
            }
        }
    }
}
