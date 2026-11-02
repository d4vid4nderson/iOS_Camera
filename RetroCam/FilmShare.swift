import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

private extension Font {
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Share a film's recipe: a QR code a friend scans with their iPhone camera, or a link
/// to send. Either opens Exposures and offers to add the film.
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

            if let url, let card = FilmCodeCard.render(film: film, url: url, accent: UIColor(accent)) {
                Image(uiImage: card)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .frame(maxHeight: 440)
                    .accessibilityLabel("Share code for \(film.name)")

                Text("Scan with the iPhone camera to add this film to Exposures. Every setting comes with it.")
                    .font(.mono(10)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    sharing = ShareItems(items: [card, url])
                } label: {
                    Text("SHARE CODE")
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
}
