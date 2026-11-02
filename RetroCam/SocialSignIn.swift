import AuthenticationServices
import CryptoKit
import UIKit

/// Sign in with Google and Facebook through the system's web sign-in sheet (no SDKs).
///
/// Google: OAuth with PKCE straight from the app, which ends with an ID token the server
/// checks. Facebook: its login page sends a one-time code back through the share server
/// (/auth/facebook/callback, which opens the app); the server swaps the code for who you
/// are, since that needs the Facebook app secret.
///
/// Each is hidden until its ID below is filled in (and matching settings are on the server).
enum SocialSignIn {
    /// The iOS OAuth client ID from Google Cloud ("1234-abc.apps.googleusercontent.com").
    static let googleClientID = ""
    /// The Meta app's App ID.
    static let facebookAppID = ""

    static var googleAvailable: Bool { ShareLinks.isConfigured && googleClientID.hasSuffix(".apps.googleusercontent.com") }
    static var facebookAvailable: Bool { ShareLinks.isConfigured && !facebookAppID.isEmpty }

    enum Failure: LocalizedError {
        case cancelled, failed(String)
        var errorDescription: String? {
            switch self {
            case .cancelled: return nil
            case .failed(let message): return message
            }
        }
    }

    // MARK: Google

    /// Google's reversed client ID, which iOS clients use as their redirect scheme.
    private static var googleScheme: String {
        "com.googleusercontent.apps." + googleClientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
    }

    /// Returns a Google ID token for this app.
    @MainActor
    static func googleIDToken() async throws -> String {
        let verifier = randomString(64)
        let state = randomString(24)
        let redirect = "\(googleScheme):/oauth2redirect"
        var auth = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        auth.queryItems = [
            .init(name: "client_id", value: googleClientID),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "openid profile"),
            .init(name: "code_challenge", value: challenge(for: verifier)),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "prompt", value: "select_account"),
        ]
        let callback = try await WebSignIn.run(url: auth.url!, scheme: googleScheme)
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value else {
            throw Failure.failed("Google didn't finish signing you in. Try again.")
        }

        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            .init(name: "client_id", value: googleClientID),
            .init(name: "code", value: code),
            .init(name: "code_verifier", value: verifier),
            .init(name: "grant_type", value: "authorization_code"),
            .init(name: "redirect_uri", value: redirect),
        ]
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        guard let result = try? await URLSession.shared.data(for: request),
              let info = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any],
              let idToken = info["id_token"] as? String else {
            throw Failure.failed("Couldn't reach Google. Check your connection and try again.")
        }
        return idToken
    }

    // MARK: Facebook

    /// Returns the one-time code Facebook's login page sent back, for the server to swap.
    @MainActor
    static func facebookCode() async throws -> String {
        guard let base = ShareLinks.base else { throw Failure.failed("Accounts aren't set up yet.") }
        let state = randomString(24)
        var auth = URLComponents(string: "https://www.facebook.com/v19.0/dialog/oauth")!
        auth.queryItems = [
            .init(name: "client_id", value: facebookAppID),
            .init(name: "redirect_uri", value: base.appendingPathComponent("auth/facebook/callback").absoluteString),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "public_profile"),
            .init(name: "state", value: state),
        ]
        let callback = try await WebSignIn.run(url: auth.url!, scheme: "exposures")
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value else {
            if items.contains(where: { $0.name == "error" }) { throw Failure.cancelled }
            throw Failure.failed("Facebook didn't finish signing you in. Try again.")
        }
        return code
    }

    // MARK: PKCE

    private static func randomString(_ length: Int) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in alphabet.randomElement(using: &generator)! })
    }

    private static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// One run of the system web sign-in sheet, as async/await.
@MainActor
private final class WebSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    private static var running: WebSignIn?
    private var session: ASWebAuthenticationSession?

    static func run(url: URL, scheme: String) async throws -> URL {
        let runner = WebSignIn()
        running = runner
        defer { running = nil }
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: SocialSignIn.Failure.cancelled)
                } else {
                    continuation.resume(throwing: SocialSignIn.Failure.failed(error?.localizedDescription ?? "Sign-in didn't finish."))
                }
            }
            session.presentationContextProvider = runner
            runner.session = session
            if !session.start() {
                continuation.resume(throwing: SocialSignIn.Failure.failed("Couldn't open the sign-in page."))
            }
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first ?? ASPresentationAnchor()
        }
    }
}
