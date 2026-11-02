import Foundation

/// Share a film's whole recipe (filter, curve, toning, grain, lens, FX) as a link or QR
/// code: mono36://film?d=<code>. The code is the film's JSON, zlib-compressed and
/// base64url-encoded, so it fits comfortably in a QR code.
enum FilmCode {
    static let scheme = "mono36"

    static func url(for film: FilmStock) -> URL? {
        var shared = film
        shared.id = "shared"                     // ids are local; the receiver gets a new one
        guard let json = try? JSONEncoder().encode(shared),
              let packed = try? (json as NSData).compressed(using: .zlib) as Data else { return nil }
        var parts = URLComponents()
        parts.scheme = scheme
        parts.host = "film"
        parts.queryItems = [URLQueryItem(name: "d", value: base64url(packed))]
        return parts.url
    }

    /// The film in a shared link, ready to save as one of the user's own. nil if the link
    /// isn't a film link or is damaged.
    static func film(from url: URL) -> FilmStock? {
        guard url.scheme == scheme, url.host == "film",
              let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "d" })?.value,
              let packed = data(base64url: code),
              let json = try? (packed as NSData).decompressed(using: .zlib) as Data,
              var film = try? JSONDecoder().decode(FilmStock.self, from: json) else { return nil }
        film.id = FilmStock.customPrefix + UUID().uuidString
        film.name = FilmLibrary.cleanName(film.name)
        film.blurb = "Shared with you"
        return film
    }

    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func data(base64url string: String) -> Data? {
        var s = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        return Data(base64Encoded: s)
    }
}
