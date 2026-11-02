import Foundation

/// The web address share links use (the server in server/, on Cloudflare Workers).
///
///   https://<host>/f/<code>   a film: opens Film Exposures and offers to add it
///   https://<host>/r/<id>     a shared roll: opens in Film Exposures' viewer
///
/// Until `host` is set, film links fall back to exposures://f/<code> and roll sharing
/// is hidden.
enum ShareLinks {
    static let host = ""

    static var isConfigured: Bool { !host.isEmpty }

    static var base: URL? { isConfigured ? URL(string: "https://\(host)") : nil }

    /// A shared roll's id if `url` is a roll link (https://<host>/r/<id> or exposures://r/<id>).
    static func rollID(from url: URL, host expected: String = host) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        let id: String?
        if url.scheme == "exposures", url.host == "r" {
            id = parts.first
        } else if url.scheme == "https", !expected.isEmpty, url.host == expected, parts.count == 2, parts[0] == "r" {
            id = parts[1]
        } else {
            id = nil
        }
        guard let id, id.count == 10, id.allSatisfy({ $0.isLetter || $0.isNumber }), id.allSatisfy(\.isASCII) else { return nil }
        return id
    }
}
