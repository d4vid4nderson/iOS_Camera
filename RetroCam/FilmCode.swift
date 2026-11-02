import CoreGraphics
import Foundation

/// Share a film's whole recipe (filter, curve, toning, grain, lens, FX) as a link or QR
/// code: exposures://f/<code>.
///
/// The code packs each setting into one byte (its position within the range the app
/// allows), plus the ISO and the name: about 32 bytes, 43 characters. That keeps the QR
/// small and easy to scan. Rounding to 1/255 of a setting's range is far finer than the
/// dials click.
///
/// Older links (exposures://film?d=…, zlib-compressed JSON) still open.
enum FilmCode {
    static let scheme = "exposures"
    private static let version: UInt8 = 1

    /// Every packed setting and the range it's packed into, in code order.
    private static let fields: [(WritableKeyPath<FilmStock, CGFloat>, ClosedRange<CGFloat>)] = [
        (\.red, -1...2), (\.green, -1...2), (\.blue, -1...2),
        (\.contrast, 0...1), (\.key, -1...1), (\.blackLift, 0...0.25), (\.whitePoint, 0.75...1),
        (\.grain, 0...1), (\.grainSize, 0.6...3), (\.vignette, 0...1.2),
        (\.toneAmount, 0...1), (\.bloom, 0...1), (\.edgeSoftness, 0...1), (\.exposure, -1...1), (\.fog, 0...1),
        (\.effectAmount, 0...1), (\.effectX, 0...1), (\.effectY, 0...1),
    ]

    static func url(for film: FilmStock) -> URL? {
        var bytes: [UInt8] = [version]
        for (path, range) in fields {
            let t = (film[keyPath: path] - range.lowerBound) / (range.upperBound - range.lowerBound)
            bytes.append(UInt8((min(max(t, 0), 1) * 255).rounded()))
        }
        bytes.append(UInt8(Toning.allCases.firstIndex(of: film.tone) ?? 0))
        bytes.append(UInt8(LensEffect.allCases.firstIndex(of: film.effect) ?? 0))
        let iso = UInt16(clamping: film.iso)
        bytes.append(UInt8(iso >> 8)); bytes.append(UInt8(iso & 0xFF))
        bytes.append(contentsOf: Array(FilmLibrary.cleanName(film.name).utf8))
        return URL(string: "\(scheme)://f/\(base64url(Data(bytes)))")
    }

    /// The film in a shared link, ready to save as one of the user's own. nil if the link
    /// isn't a film link or is damaged.
    static func film(from url: URL) -> FilmStock? {
        guard url.scheme == scheme else { return nil }
        var film: FilmStock?
        if url.host == "f" {
            film = unpack(String(url.path.dropFirst()))
        } else if url.host == "film" {
            film = legacy(url)
        }
        guard var received = film else { return nil }
        received.id = FilmStock.customPrefix + UUID().uuidString
        received.name = FilmLibrary.cleanName(received.name)
        received.blurb = "Shared with you"
        return received
    }

    private static func unpack(_ code: String) -> FilmStock? {
        guard let data = data(base64url: code) else { return nil }
        let bytes = [UInt8](data)
        let fixed = 1 + fields.count + 2 + 2
        guard bytes.count >= fixed, bytes[0] == version else { return nil }
        var film = FilmStock.classic400
        for (i, (path, range)) in fields.enumerated() {
            let t = CGFloat(bytes[1 + i]) / 255
            film[keyPath: path] = range.lowerBound + t * (range.upperBound - range.lowerBound)
        }
        var at = 1 + fields.count
        let tones = Toning.allCases, effects = LensEffect.allCases
        guard Int(bytes[at]) < tones.count, Int(bytes[at + 1]) < effects.count else { return nil }
        film.tone = tones[Int(bytes[at])]
        film.effect = effects[Int(bytes[at + 1])]
        at += 2
        film.iso = Int(bytes[at]) << 8 | Int(bytes[at + 1])
        at += 2
        guard let name = String(bytes: bytes[at...], encoding: .utf8) else { return nil }
        film.name = name
        return film
    }

    /// Links made by the first build that had film sharing.
    private static func legacy(_ url: URL) -> FilmStock? {
        guard let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "d" })?.value,
              let packed = data(base64url: code),
              let json = try? (packed as NSData).decompressed(using: .zlib) as Data else { return nil }
        return try? JSONDecoder().decode(FilmStock.self, from: json)
    }

    static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func data(base64url string: String) -> Data? {
        var s = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        return Data(base64Encoded: s)
    }
}
