import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

private extension Font {
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Share a film's recipe: a QR code a friend scans with their iPhone camera, or a link
/// to send. Either opens Mono36 and offers to add the film.
struct FilmShareSheet: View {
    let film: FilmStock
    let accent: Color
    @Environment(\.dismiss) private var dismiss
    @State private var sharing: ShareItems?

    private var url: URL? { FilmCode.url(for: film) }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("SHARE FILM").font(.mono(10, .semibold)).foregroundStyle(.secondary)
                Spacer()
                Button("DONE") { dismiss() }.font(.mono(11, .bold)).foregroundStyle(accent)
            }
            Text(film.name).font(.mono(20, .bold)).foregroundStyle(accent)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let url, let qr = Self.qrImage(for: url) {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                    .frame(maxWidth: 240)
                    .accessibilityLabel("QR code for \(film.name)")

                Text("Scan with the iPhone camera to add this film to Mono36. Every setting comes with it.")
                    .font(.mono(10)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    sharing = ShareItems(items: [url, qr])
                } label: {
                    Text("SEND LINK")
                        .font(.mono(12, .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(accent.opacity(0.18)))
                        .overlay(Capsule().stroke(accent, lineWidth: 1))
                        .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
            } else {
                Text("This film couldn't be packed into a code.").font(.mono(11)).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .presentationDetents([.large])
        .presentationBackground(Color(white: 0.09))
        .preferredColorScheme(.dark)
        .sheet(item: $sharing) { item in
            ActivityView(items: item.items).ignoresSafeArea()
        }
    }

    /// Black-on-white QR code, sharp at any size.
    static func qrImage(for url: URL) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let code = filter.outputImage?.samplingNearest().transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let cg = CIContext().createCGImage(code, from: code.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
