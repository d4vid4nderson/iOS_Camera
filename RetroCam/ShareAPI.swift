import Foundation

/// Talking to the share server (server/): one request, with the errors people see.
enum ShareAPI {
    enum Failure: LocalizedError {
        case server(String)
        var errorDescription: String? {
            switch self { case .server(let message): return message }
        }
    }

    /// `token` is a roll's own token (Authorization); `account` is the signed-in session
    /// (X-Account).
    static func send(_ url: URL, method: String, token: String? = nil, account: String? = nil,
                     json: [String: Any]? = nil, body: Data? = nil, type: String? = nil,
                     notFound: String? = nil) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 90
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let account { request.setValue(account, forHTTPHeaderField: "X-Account") }
        var payload = body
        if let json {
            payload = try JSONSerialization.data(withJSONObject: json)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let type { request.setValue(type, forHTTPHeaderField: "Content-Type") }

        let (data, response): (Data, URLResponse)
        do {
            if let payload {
                (data, response) = try await URLSession.shared.upload(for: request, from: payload)
            } else {
                (data, response) = try await URLSession.shared.data(for: request)
            }
        } catch {
            throw Failure.server("Couldn't reach the share server. Check your connection and try again.")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if status == 404, let notFound { throw Failure.server(notFound) }
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw HTTPError(status: status, message: message)
        }
        return data
    }

    /// A refusal from the server, kept apart so callers can react to e.g. 401 (signed out)
    /// or 403 "terms".
    struct HTTPError: LocalizedError {
        let status: Int
        let message: String?
        var errorDescription: String? { "The share server said: \(message ?? "error \(status)")." }
    }

    static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}
