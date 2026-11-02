import SwiftUI
import UIKit

/// A film's tone scale as a row of swatches, black to white as the film prints them
/// (toned films show their colour) — the same strip as on its share card.
struct ToneStrip: View {
    let film: FilmStock
    var steps = 7
    var cornerRadius: CGFloat = 2.5
    @State private var tones: [UIColor] = []

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<steps, id: \.self) { i in
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(i < tones.count ? Color(uiColor: tones[i]) : placeholder(i))
            }
        }
        .task(id: film) { tones = await ToneCache.shared.tones(for: film, steps: steps) }
        .accessibilityHidden(true)
    }

    /// A plain grey ramp while the film's tones are worked out.
    private func placeholder(_ i: Int) -> Color {
        Color(white: 0.05 + 0.9 * Double(i) / Double(max(steps - 1, 1)))
    }
}

/// Tone scales, worked out once per film recipe, off the main thread.
actor ToneCache {
    static let shared = ToneCache()
    private var cache: [FilmStock: [UIColor]] = [:]

    func tones(for film: FilmStock, steps: Int) -> [UIColor] {
        if let hit = cache[film], hit.count == steps { return hit }
        let tones = FilmCodeCard.toneScale(for: film, steps: steps)
        cache[film] = tones
        return tones
    }
}
