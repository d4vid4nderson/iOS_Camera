import Foundation

/// The web address share links use (the server in server/, on Cloudflare Workers).
///
///   https://<host>/f/<code>   a film: opens Film Exposures and offers to add it
///   https://<host>/r/<id>     a shared roll: opens in Film Exposures' viewer
///   https://<host>/u/<id>     someone's profile and their public rolls
///
/// Until `host` is set, film links fall back to exposures://f/<code> and roll sharing
/// is hidden.
enum ShareLinks {
    static let host = "filmexposures.com"

    static var isConfigured: Bool { !host.isEmpty }

    static var base: URL? { isConfigured ? URL(string: "https://\(host)") : nil }

    /// A shared roll's id if `url` is a roll link (https://<host>/r/<id> or exposures://r/<id>).
    static func rollID(from url: URL, host expected: String = host) -> String? {
        id(from: url, kind: "r", length: 10, host: expected)
    }

    /// Someone's account id if `url` is a profile link (https://<host>/u/<id> or exposures://u/<id>).
    static func userID(from url: URL, host expected: String = host) -> String? {
        id(from: url, kind: "u", length: 12, host: expected)
    }

    private static func id(from url: URL, kind: String, length: Int, host expected: String) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        let id: String?
        if url.scheme == "exposures", url.host == kind, parts.count == 1 {
            id = parts.first
        } else if url.scheme == "https", !expected.isEmpty, url.host == expected, parts.count == 2, parts[0] == kind {
            id = parts[1]
        } else {
            id = nil
        }
        guard let id, id.count == length, id.allSatisfy({ $0.isLetter || $0.isNumber }), id.allSatisfy(\.isASCII) else { return nil }
        return id
    }
}
