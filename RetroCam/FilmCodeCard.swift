import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// A film's share card. Two layouts in one style:
///
/// - **Photo**: a frame you shot on the film fills the top, with the film's name, a short
///   description and a small code below. Shows what the film does.
/// - **Tones**: for a film with no frames yet (or when you'd rather not share a photo):
///   the name large on a dark card, the film's tone scale (black to white, developed
///   through the film, so toned films show their colour) and the code on a light tile.
///
/// The code is a standard QR code drawn with joined round modules, so the iPhone Camera
/// app scans it; the shapes only change how each module is drawn, not where it is.
enum FilmCodeCard {
    static let size = CGSize(width: 1080, height: 1350)   // 4:5, the portrait size feeds use

    /// Who shared the card: shown as a round headshot and a name.
    struct Sharer {
        var name: String
        var avatar: UIImage?
    }

    /// `style` picks LIGHT / DARK / SLIDE (the share card picker); nil keeps each layout's
    /// own look (the photo card light, the tone card dark).
    static func render(film: FilmStock, url: URL, photo: UIImage?, sharer: Sharer? = nil, style: CardStyle? = nil) -> UIImage? {
        guard let modules = modules(for: url.absoluteString) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            if let photo {
                drawPhotoCard(film: film, photo: photo, sharer: sharer, modules: modules, style: style ?? .light, in: ctx.cgContext)
            } else {
                drawToneCard(film: film, sharer: sharer, modules: modules, style: style ?? .dark, in: ctx.cgContext)
            }
        }
    }

    // MARK: Layouts

    private static func drawPhotoCard(film: FilmStock, photo: UIImage, sharer: Sharer?, modules: [[Bool]],
                                      style: CardStyle, in cg: CGContext) {
        let background = style.background
        let ink = style.ink
        let muted = style.muted
        let margin: CGFloat = 56

        background.setFill()
        cg.fill(CGRect(origin: .zero, size: size))

        // The frame, whole (prints may have borders), as large as fits the top.
        let area = CGRect(x: margin, y: margin, width: size.width - 2 * margin, height: 880)
        let aspect = photo.size.width / max(photo.size.height, 1)
        var frame = area
        if aspect > area.width / area.height {
            frame.size.height = area.width / aspect
        } else {
            frame.size.width = area.height * aspect
            frame.origin.x = area.midX - frame.width / 2
        }
        var bottom = frame.maxY
        if style == .slide {
            // The frame in a slide mount labelled with the film's name, filling the same area.
            let mount = area
            let window = style.drawMount(in: mount, label: film.name.uppercased(), context: cg)
            cg.saveGState()
            UIBezierPath(roundedRect: window, cornerRadius: window.width * 0.02).addClip()
            let scale = max(window.width / photo.size.width, window.height / photo.size.height)
            let drawn = CGSize(width: photo.size.width * scale, height: photo.size.height * scale)
            photo.draw(in: CGRect(x: window.midX - drawn.width / 2, y: window.midY - drawn.height / 2,
                                  width: drawn.width, height: drawn.height))
            cg.restoreGState()
            bottom = mount.maxY
        } else {
            cg.saveGState()
            UIBezierPath(roundedRect: frame, cornerRadius: 20).addClip()
            photo.draw(in: frame)
            cg.restoreGState()
        }

        let textTop = bottom + 52
        let maxWidth = size.width - 2 * margin
        let title = fitted(film.name, weight: .bold, size: 92, minSize: 54, width: maxWidth)
        draw(film.name, font: title, color: ink, at: CGPoint(x: margin - 3, y: textTop), kern: -title.pointSize * 0.02)
        draw(film.shareCaption, font: .systemFont(ofSize: 29, weight: .regular), color: muted,
             at: CGPoint(x: margin, y: textTop + title.lineHeight + 8))

        let codeSide: CGFloat = 210
        let codeRect = CGRect(x: size.width - margin - codeSide, y: size.height - margin - codeSide,
                              width: codeSide, height: codeSide)
        style.drawCode(modules, in: codeRect, context: cg)

        let mark = UIFont.systemFont(ofSize: 22, weight: .semibold)
        let markWidth = ("FILM EXPOSURES" as NSString).size(withAttributes: [.font: mark, .kern: 1]).width
        if let sharer {
            // Headshot + name, with the wordmark and the hint under the name.
            let side: CGFloat = 76
            let avatarRect = CGRect(x: margin, y: size.height - margin - side, width: side, height: side)
            drawAvatar(sharer, in: avatarRect, fill: style.avatarFill, initialsColor: ink)
            let x = avatarRect.maxX + 18
            let nameFont = UIFont.systemFont(ofSize: 28, weight: .semibold)
            let textHeight = nameFont.lineHeight + mark.lineHeight + 2
            let top = avatarRect.midY - textHeight / 2
            if !sharer.name.isEmpty {
                draw(sharer.name, font: nameFont, color: ink, at: CGPoint(x: x, y: top))
            }
            let lineY = sharer.name.isEmpty ? avatarRect.midY - mark.lineHeight / 2 : top + nameFont.lineHeight + 2
            draw("FILM EXPOSURES", font: mark, color: muted, at: CGPoint(x: x, y: lineY), kern: 1)
            draw("Scan to load this film", font: .systemFont(ofSize: 22, weight: .regular), color: muted,
                 at: CGPoint(x: x + markWidth + 12, y: lineY))
        } else {
            let markY = size.height - margin - mark.lineHeight
            draw("FILM EXPOSURES", font: mark, color: ink, at: CGPoint(x: margin, y: markY), kern: 1)
            draw("Scan to load this film", font: .systemFont(ofSize: 22, weight: .regular), color: muted,
                 at: CGPoint(x: margin + markWidth + 14, y: markY))
        }
    }

    private static func drawToneCard(film: FilmStock, sharer: Sharer?, modules: [[Bool]], style: CardStyle, in cg: CGContext) {
        let background = style.background
        let light = style.ink          // the text colour: light on DARK / SLIDE, near-black on LIGHT
        let muted = style.muted
        let margin: CGFloat = 64

        background.setFill()
        cg.fill(CGRect(origin: .zero, size: size))

        let mark = UIFont.systemFont(ofSize: 22, weight: .semibold)
        if let sharer {
            // Headshot + name top left, the wordmark top right.
            let side: CGFloat = 64
            let avatarRect = CGRect(x: margin, y: 40, width: side, height: side)
            drawAvatar(sharer, in: avatarRect, fill: style.avatarFill, initialsColor: light)
            if !sharer.name.isEmpty {
                let nameFont = UIFont.systemFont(ofSize: 28, weight: .semibold)
                draw(sharer.name, font: nameFont, color: light,
                     at: CGPoint(x: avatarRect.maxX + 16, y: avatarRect.midY - nameFont.lineHeight / 2))
            }
            let markWidth = ("FILM EXPOSURES" as NSString).size(withAttributes: [.font: mark, .kern: 1]).width
            draw("FILM EXPOSURES", font: mark, color: muted,
                 at: CGPoint(x: size.width - margin - markWidth, y: avatarRect.midY - mark.lineHeight / 2), kern: 1)
        } else {
            draw("FILM EXPOSURES", font: mark, color: muted, at: CGPoint(x: margin, y: 52), kern: 1)
        }
        let title = fitted(film.name, weight: .bold, size: 150, minSize: 64, width: size.width - 2 * margin)
        let titleTop: CGFloat = 150 + (150 - title.pointSize) * 0.6
        draw(film.name, font: title, color: light, at: CGPoint(x: margin - 5, y: titleTop), kern: -title.pointSize * 0.025)
        draw(film.shareCaption, font: .systemFont(ofSize: 30, weight: .regular), color: muted,
             at: CGPoint(x: margin + 2, y: 340))

        // Tone scale: an even grey ramp developed through the film (in a slide mount on SLIDE).
        let tones = toneScale(for: film, steps: 11)
        var strip = CGRect(x: margin, y: 430, width: size.width - 2 * margin, height: 150)
        if style == .slide {
            strip = style.drawMount(in: CGRect(x: margin, y: 400, width: size.width - 2 * margin, height: 250),
                                    label: "TONE SCALE", context: cg)
        }
        let gap: CGFloat = 6
        let step = (strip.width - gap * CGFloat(tones.count - 1)) / CGFloat(tones.count)
        for (i, tone) in tones.enumerated() {
            tone.setFill()
            UIBezierPath(roundedRect: CGRect(x: strip.minX + CGFloat(i) * (step + gap), y: strip.minY, width: step, height: strip.height),
                         cornerRadius: style == .slide ? 4 : 10).fill()
        }
        if style != .slide {
            draw("TONE SCALE", font: .systemFont(ofSize: 20, weight: .medium), color: muted,
                 at: CGPoint(x: margin, y: strip.maxY + 16), kern: 1)
        }

        // The code on a light tile (dark-on-light scans most reliably); on LIGHT the tile
        // gets an edge so it doesn't vanish into the paper.
        let tileSide: CGFloat = 520, codeSide: CGFloat = 400
        let tile = CGRect(x: (size.width - tileSide) / 2, y: 760, width: tileSide, height: tileSide)
        let tilePath = UIBezierPath(roundedRect: tile, cornerRadius: 44)
        Brand.light.setFill()
        tilePath.fill()
        if style == .light {
            UIColor(white: 0, alpha: 0.12).setStroke()
            tilePath.lineWidth = 2
            tilePath.stroke()
        }
        drawCode(modules, in: tile.insetBy(dx: (tileSide - codeSide) / 2, dy: (tileSide - codeSide) / 2),
                 ink: Brand.ink, paper: Brand.light, context: cg)
    }

    // MARK: Pieces

    /// A round headshot, or the name's initials on a plain disc.
    static func drawAvatar(_ sharer: Sharer, in rect: CGRect, fill: UIColor, initialsColor: UIColor) {
        let circle = UIBezierPath(ovalIn: rect)
        if let avatar = sharer.avatar {
            UIGraphicsGetCurrentContext()?.saveGState()
            circle.addClip()
            avatar.draw(in: rect)
            UIGraphicsGetCurrentContext()?.restoreGState()
        } else {
            fill.setFill()
            circle.fill()
            let initials = sharer.name.split(separator: " ").prefix(2)
                .compactMap { $0.first(where: { $0.isLetter || $0.isNumber }) }
                .map { String($0).uppercased() }.joined()
            let font = UIFont.systemFont(ofSize: rect.height * 0.38, weight: .semibold)
            let textSize = (initials as NSString).size(withAttributes: [.font: font])
            draw(initials, font: font, color: initialsColor,
                 at: CGPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2))
        }
    }

    static func draw(_ text: String, font: UIFont, color: UIColor, at point: CGPoint, kern: CGFloat = 0) {
        (text as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color, .kern: kern])
    }

    /// The largest bold size (down to `minSize`) at which `text` fits on one line.
    static func fitted(_ text: String, weight: UIFont.Weight, size: CGFloat, minSize: CGFloat, width: CGFloat) -> UIFont {
        var pointSize = size
        while pointSize > minSize {
            let font = UIFont.systemFont(ofSize: pointSize, weight: weight)
            if (text as NSString).size(withAttributes: [.font: font]).width <= width { return font }
            pointSize -= 2
        }
        return UIFont.systemFont(ofSize: minSize, weight: weight)
    }

    /// The QR modules as round dots joined to their neighbours, with rounded corner eyes.
    static func drawCode(_ modules: [[Bool]], in rect: CGRect, ink: UIColor, paper: UIColor, context cg: CGContext) {
        let n = modules.count
        let m = rect.width / CGFloat(n)
        let finders = [(0, 0), (0, n - 7), (n - 7, 0)]
        func inFinder(_ r: Int, _ c: Int) -> Bool {
            finders.contains { r >= $0.0 && r < $0.0 + 7 && c >= $0.1 && c < $0.1 + 7 }
        }
        func on(_ r: Int, _ c: Int) -> Bool {
            r >= 0 && r < n && c >= 0 && c < n && modules[r][c] && !inFinder(r, c)
        }
        let dot = m * 0.84, pad = (m - dot) / 2

        ink.setFill()
        for r in 0..<n {
            for c in 0..<n where on(r, c) {
                let x = rect.minX + CGFloat(c) * m, y = rect.minY + CGFloat(r) * m
                cg.fillEllipse(in: CGRect(x: x + pad, y: y + pad, width: dot, height: dot))
                if on(r, c + 1) { cg.fill(CGRect(x: x + m / 2, y: y + pad, width: m, height: dot)) }
                if on(r + 1, c) { cg.fill(CGRect(x: x + pad, y: y + m / 2, width: dot, height: m)) }
            }
        }
        for (fr, fc) in finders {
            let x = rect.minX + CGFloat(fc) * m, y = rect.minY + CGFloat(fr) * m
            ink.setFill()
            UIBezierPath(roundedRect: CGRect(x: x, y: y, width: 7 * m, height: 7 * m), cornerRadius: 2.3 * m).fill()
            paper.setFill()
            UIBezierPath(roundedRect: CGRect(x: x + m, y: y + m, width: 5 * m, height: 5 * m), cornerRadius: 1.6 * m).fill()
            ink.setFill()
            UIBezierPath(roundedRect: CGRect(x: x + 2 * m, y: y + 2 * m, width: 3 * m, height: 3 * m), cornerRadius: 1.2 * m).fill()
        }
    }

    private static let context = CIContext()

    /// `steps` greys from black to white as the film prints them: its curve, filter and
    /// toning, without grain, fog, vignette or lens effects.
    static func toneScale(for film: FilmStock, steps: Int) -> [UIColor] {
        var flat = film
        flat.grain = 0
        flat.vignette = 0
        flat.fog = 0
        flat.bloom = 0
        flat.halation = 0
        flat.edgeSoftness = 0
        flat.effect = .none

        // A ramp of even sRGB greys, one 8x8 patch per step.
        let patch = 8, width = steps * patch
        var pixels = [UInt8](repeating: 255, count: width * patch * 4)
        for i in 0..<steps {
            let v = UInt8((Double(i) / Double(max(steps - 1, 1)) * 255).rounded())
            for y in 0..<patch {
                for x in i * patch..<(i + 1) * patch {
                    let p = (y * width + x) * 4
                    pixels[p] = v; pixels[p + 1] = v; pixels[p + 2] = v
                }
            }
        }
        let fallback = (0..<steps).map { UIColor(white: CGFloat($0) / CGFloat(max(steps - 1, 1)), alpha: 1) }
        guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(pixels) as CFData),
              let ramp = CGImage(width: width, height: patch, bitsPerComponent: 8, bitsPerPixel: 32,
                                 bytesPerRow: width * 4, space: sRGB,
                                 bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                 provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return fallback }

        let developed = FilmLook.apply(flat, to: CIImage(cgImage: ramp))
        guard let out = context.createCGImage(developed, from: developed.extent, format: .RGBA8, colorSpace: sRGB),
              let data = out.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return fallback }
        let rowBytes = out.bytesPerRow, y = out.height / 2
        return (0..<steps).map { i in
            let x = min(i * patch + patch / 2, out.width - 1)
            let p = y * rowBytes + x * 4
            return UIColor(red: CGFloat(bytes[p]) / 255, green: CGFloat(bytes[p + 1]) / 255,
                           blue: CGFloat(bytes[p + 2]) / 255, alpha: 1)
        }
    }

    /// The QR code's modules (true = dark), row by row from the top, without quiet zone.
    static func modules(for text: String) -> [[Bool]]? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let image = filter.outputImage,
              let cg = CIContext().createCGImage(image, from: image.extent) else { return nil }
        let w = cg.width, h = cg.height
        var pixels = [UInt8](repeating: 255, count: w * h)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        let dark = { (x: Int, y: Int) in pixels[y * w + x] < 128 }

        // Trim the generator's quiet zone: the finder patterns reach three edges.
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h { for x in 0..<w where dark(x, y) {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        let n = maxX - minX + 1
        guard n > 20, n == maxY - minY + 1 else { return nil }
        var grid = (0..<n).map { r in (0..<n).map { c in dark(minX + c, minY + r) } }

        // Corner eyes must sit top-left, top-right and bottom-left; flip if the bitmap
        // came out upside down.
        func isEye(_ r0: Int, _ c0: Int) -> Bool {
            (0..<7).allSatisfy { i in grid[r0][c0 + i] && grid[r0 + 6][c0 + i] && grid[r0 + i][c0] && grid[r0 + i][c0 + 6] }
                && grid[r0 + 3][c0 + 3] && !grid[r0 + 1][c0 + 1]
        }
        if !isEye(0, n - 7), isEye(n - 7, n - 7) { grid.reverse() }
        return grid
    }
}
