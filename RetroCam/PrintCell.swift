import ImageIO
import SwiftUI

/// How prints sit in a grid. Every cell in a grid is the same shape, and each print is
/// fitted into it whole, border and all, on a dark mat: wide formats (XPAN, 6×17…) no
/// longer get cropped into a zoomed-in middle, and captions line up under every cell.
///
/// A roll shot in a landscape format gets landscape cells, two across; everything else
/// keeps 3:4 cells, three across.
enum PrintLayout {
    /// Width ÷ height of a grid cell for prints of this shape.
    static func cellAspect(for printAspect: CGFloat?) -> CGFloat {
        guard let printAspect, printAspect > 1.05 else { return 3.0 / 4.0 }
        return min(printAspect, 2)
    }

    static func columns(for printAspect: CGFloat?) -> Int {
        (printAspect ?? 0) > 1.05 ? 2 : 3
    }

    /// Width ÷ height of an image file, read from its header (no decoding).
    static func aspect(ofImageAt url: URL) -> CGFloat? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              var w = props[kCGImagePropertyPixelWidth] as? CGFloat,
              var h = props[kCGImagePropertyPixelHeight] as? CGFloat, w > 0, h > 0 else { return nil }
        if let orientation = props[kCGImagePropertyOrientation] as? UInt32, (5...8).contains(orientation) { swap(&w, &h) }
        return w / h
    }
}

/// A grid cell of a fixed shape with a print fitted inside it on a dark mat.
struct PrintCell<Content: View>: View {
    let aspect: CGFloat
    var cornerRadius: CGFloat = 0
    @ViewBuilder var content: Content

    var body: some View {
        Color(white: 0.1)
            .aspectRatio(aspect, contentMode: .fit)
            .overlay { content }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

/// A print loaded from the web, fitted whole. Tells you its shape once it's loaded, so a
/// grid can pick landscape cells for wide rolls.
struct RemotePrint: View {
    let url: URL?
    var onAspect: (CGFloat) -> Void = { _ in }
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Color(white: 0.1)
            }
        }
        .task(id: url) {
            guard let url, let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let loaded = UIImage(data: data) else { return }
            image = loaded
            if loaded.size.height > 0 { onAspect(loaded.size.width / loaded.size.height) }
        }
    }
}
