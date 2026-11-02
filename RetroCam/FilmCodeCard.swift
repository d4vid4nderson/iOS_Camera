import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// A film's share code as a card in the app's style: a QR drawn with round dots and
/// rounded corner eyes on paper, set on an accent-coloured card with sprocket holes, the
/// film's name and "Exposures". It's still a standard QR code, so the iPhone Camera app
/// scans it; the shapes only change how each module is drawn, not where it is.
enum FilmCodeCard {
    static let size = CGSize(width: 1080, height: 1350)   // 4:5, the portrait size feeds use

    static func render(film: FilmStock, url: URL, accent: UIColor) -> UIImage? {
        guard let modules = modules(for: url.absoluteString) else { return nil }
        let n = modules.count
        let ink = UIColor(white: 0.08, alpha: 1)
        let paper = UIColor(red: 0.97, green: 0.95, blue: 0.92, alpha: 1)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            accent.setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            // Sprocket holes along the top and bottom, centred.
            let hole = CGSize(width: 30, height: 26), gap: CGFloat = 28
            let count = Int((size.width - 80 + gap) / (hole.width + gap))
            let run = CGFloat(count) * hole.width + CGFloat(count - 1) * gap
            UIColor(white: 0.12, alpha: 1).setFill()
            for y in [34, size.height - 34 - hole.height] {
                for i in 0..<count {
                    let x = (size.width - run) / 2 + CGFloat(i) * (hole.width + gap)
                    UIBezierPath(roundedRect: CGRect(x: x, y: y, width: hole.width, height: hole.height),
                                 cornerRadius: 7).fill()
                }
            }

            // Paper square with the code.
            let side: CGFloat = 860
            let square = CGRect(x: (size.width - side) / 2, y: 110, width: side, height: side)
            paper.setFill()
            UIBezierPath(roundedRect: square, cornerRadius: 56).fill()

            let quiet: CGFloat = 3
            let m = side / (CGFloat(n) + 2 * quiet)
            func origin(_ r: Int, _ c: Int) -> CGPoint {
                CGPoint(x: square.minX + (CGFloat(c) + quiet) * m, y: square.minY + (CGFloat(r) + quiet) * m)
            }
            let finders = [(0, 0), (0, n - 7), (n - 7, 0)]
            func inFinder(_ r: Int, _ c: Int) -> Bool {
                finders.contains { r >= $0.0 && r < $0.0 + 7 && c >= $0.1 && c < $0.1 + 7 }
            }

            ink.setFill()
            let pad = m * 0.08
            for r in 0..<n {
                for c in 0..<n where modules[r][c] && !inFinder(r, c) {
                    let p = origin(r, c)
                    cg.fillEllipse(in: CGRect(x: p.x + pad, y: p.y + pad, width: m - 2 * pad, height: m - 2 * pad))
                }
            }
            for (fr, fc) in finders {
                let p = origin(fr, fc)
                ink.setFill()
                UIBezierPath(roundedRect: CGRect(x: p.x, y: p.y, width: 7 * m, height: 7 * m), cornerRadius: 2.2 * m).fill()
                paper.setFill()
                UIBezierPath(roundedRect: CGRect(x: p.x + m, y: p.y + m, width: 5 * m, height: 5 * m), cornerRadius: 1.5 * m).fill()
                ink.setFill()
                UIBezierPath(roundedRect: CGRect(x: p.x + 2 * m, y: p.y + 2 * m, width: 3 * m, height: 3 * m), cornerRadius: 1.0 * m).fill()
            }

            // Film name and the line under it.
            (film.name as NSString).draw(
                at: CGPoint(x: square.minX, y: square.maxY + 44),
                withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 76, weight: .bold), .foregroundColor: ink])
            ("SCAN TO LOAD THIS FILM  ·  EXPOSURES" as NSString).draw(
                at: CGPoint(x: square.minX, y: square.maxY + 150),
                withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 28, weight: .regular),
                                 .foregroundColor: UIColor(white: 0.16, alpha: 1)])
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
