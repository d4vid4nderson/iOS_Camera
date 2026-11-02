import UIKit

/// A whole roll printed as one contact sheet: strips of six frames on dark film base,
/// sprocket holes along each strip, frame numbers and the roll's details in the
/// orange edge print film carries. Made from the app's own copies, to share.
enum ContactSheet {
    private static let columns = 6
    private static let cell = CGSize(width: 480, height: 640)     // 3:4 frames
    private static let gap: CGFloat = 18
    private static let margin: CGFloat = 60
    private static let rail: CGFloat = 70                         // sprocket band above/below a strip

    static func render(roll: Roll, frames: [Int]) -> UIImage? {
        guard !frames.isEmpty else { return nil }
        let rows = (frames.count + columns - 1) / columns
        let stripHeight = rail + cell.height + rail
        let width = margin * 2 + CGFloat(columns) * cell.width + CGFloat(columns - 1) * gap
        let height = margin * 2 + 90 + CGFloat(rows) * stripHeight + CGFloat(rows - 1) * gap

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        let edge = UIColor(red: 0.95, green: 0.55, blue: 0.2, alpha: 0.9)
        let mono = { (size: CGFloat, weight: UIFont.Weight) in UIFont.monospacedSystemFont(ofSize: size, weight: weight) }

        return renderer.image { ctx in
            UIColor(white: 0.93, alpha: 1).setFill()                 // light-box paper
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

            // Header: roll, film, date.
            var title = String(format: "EXPOSURES   ROLL %02d", roll.number)
            if let film = roll.film { title += "   \(film)" }
            if let started = roll.started {
                title += "   " + started.formatted(.dateTime.month(.abbreviated).day().year()).uppercased()
            }
            (title as NSString).draw(at: CGPoint(x: margin, y: margin),
                                     withAttributes: [.font: mono(44, .bold), .foregroundColor: UIColor(white: 0.12, alpha: 1)])

            for row in 0..<rows {
                let top = margin + 90 + CGFloat(row) * (stripHeight + gap)
                let strip = CGRect(x: margin - gap / 2, y: top, width: width - 2 * margin + gap, height: stripHeight)
                UIColor(white: 0.07, alpha: 1).setFill()             // film base
                ctx.fill(strip)

                // Sprocket holes along both rails.
                UIColor(white: 0.93, alpha: 1).setFill()
                var x = strip.minX + 14
                while x + 22 < strip.maxX {
                    UIBezierPath(roundedRect: CGRect(x: x, y: top + 10, width: 22, height: 22), cornerRadius: 4).fill()
                    UIBezierPath(roundedRect: CGRect(x: x, y: top + stripHeight - 32, width: 22, height: 22), cornerRadius: 4).fill()
                    x += 44
                }

                for col in 0..<columns {
                    let index = row * columns + col
                    guard index < frames.count else { break }
                    let frame = frames[index]
                    let rect = CGRect(x: margin + CGFloat(col) * (cell.width + gap), y: top + rail,
                                      width: cell.width, height: cell.height)
                    if let image = UIImage(contentsOfFile: RollStore.frameURL(roll: roll.number, frame: frame).path) {
                        draw(image, filling: rect, in: ctx.cgContext)
                    }
                    // Edge print under the frame: number and arrow, like real film.
                    let label = "\(frame)  ▸  \(frame)A"
                    (label as NSString).draw(at: CGPoint(x: rect.minX + 6, y: rect.maxY + 6),
                                             withAttributes: [.font: mono(22, .bold), .foregroundColor: edge])
                }
            }
        }
    }

    private static func draw(_ image: UIImage, filling rect: CGRect, in cg: CGContext) {
        let scale = max(rect.width / image.size.width, rect.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        cg.saveGState()
        cg.clip(to: rect)
        image.draw(in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                              width: size.width, height: size.height))
        cg.restoreGState()
    }
}
