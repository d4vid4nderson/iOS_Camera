import AuthenticationServices
import Security
import SwiftUI

/// Your Film Exposures account, made with Sign in with Apple. It's what lets you put rolls on
/// a public profile and like frames in other people's rolls. Signing in is optional: the
/// camera, your rolls and link sharing all work without it.
///
/// The session token lives in the Keychain; the profile the server sent back is cached in
/// UserDefaults so the app can show it offline.
@MainActor
final class Account: ObservableObject {
    static let shared = Account()

    /// You, as the server knows you.
    struct Me: Codable, Equatable {
        var id: String
        var name: String?
        var avatar: URL?
        var url: URL
        var termsAccepted: Bool
    }

    @Published private(set) var me: Me?
    @Published private(set) var working = false

    var isSignedIn: Bool { me != nil && Self.sessionToken != nil }


    private init() {
        if Self.sessionToken != nil,
           let data = UserDefaults.standard.data(forKey: AccountKeys.me),
           let me = try? JSONDecoder().decode(Me.self, from: data) {
            self.me = me
        }
        checkAppleCredential()
    }

    // MARK: Reading the session from anywhere

    /// The session token for the X-Account header, or nil when signed out. Safe off the
    /// main thread (it reads the Keychain).
    nonisolated static var sessionToken: String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AccountKeys.keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Your account id (the one blocking and profiles use), or nil when signed out.
    nonisolated static var storedID: String? {
        guard sessionToken != nil, let data = UserDefaults.standard.data(forKey: AccountKeys.me) else { return nil }
        return (try? JSONDecoder().decode(Me.self, from: data))?.id
    }

    nonisolated private static func storeToken(_ token: String?) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: AccountKeys.keychainService]
        SecItemDelete(base as CFDictionary)
        guard let token else { return }
        var item = base
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    // MARK: Signing in and out

    enum Failure: LocalizedError {
        case notConfigured, noToken, notSetUp
        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Accounts aren't set up yet."
            case .noToken: return "Sign in with Apple didn't send what it should. Try again."
            case .notSetUp: return "Sign in with Apple couldn't start. Check you're signed in to your Apple Account in Settings, then try again."
            }
        }
    }

    /// Finish Sign in with Apple: send Apple's identity token to the server, which checks it
    /// and opens a session. Your name and headshot (if you show them on cards) go to your
    /// profile.
    func signIn(with result: Result<ASAuthorization, Error>) async throws {
        let authorization: ASAuthorization
        switch result {
        case .success(let value): authorization = value
        case .failure(let error):
            if let error = error as? ASAuthorizationError {
                if error.code == .canceled { return }
                if error.code == .unknown { throw Failure.notSetUp }   // no entitlement in this build
            }
            throw error
        }
        guard let base = ShareLinks.base else { throw Failure.notConfigured }
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8) else { throw Failure.noToken }

        working = true
        defer { working = false }
        let profile = Profile.load()
        var body: [String: Any] = ["identityToken": identityToken]
        if profile.showOnCards, !profile.name.isEmpty { body["name"] = profile.name }
        let data = try await ShareAPI.send(base.appendingPathComponent("api/auth/apple"), method: "POST", json: body)
        guard let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = info["token"] as? String,
              let meInfo = info["me"], let meData = try? JSONSerialization.data(withJSONObject: meInfo),
              let me = try? JSONDecoder().decode(Me.self, from: meData) else {
            throw ShareAPI.Failure.server("The share server sent back something unexpected.")
        }
        Self.storeToken(token)
        UserDefaults.standard.set(credential.user, forKey: AccountKeys.appleUser)
        remember(me)
        await syncProfile(profile, avatarChanged: true)
    }

    func signOut() async {
        if let base = ShareLinks.base, let token = Self.sessionToken {
            _ = try? await ShareAPI.send(base.appendingPathComponent("api/auth/signout"), method: "POST", account: token)
        }
        forget()
    }

    /// Delete your account and everything it put on the server: your public rolls, rolls
    /// you shared while signed in, your likes and your headshot. Your rolls stay on this
    /// phone.
    func deleteAccount() async throws {
        guard let base = ShareLinks.base, let token = Self.sessionToken else { forget(); return }
        working = true
        defer { working = false }
        _ = try await ShareAPI.send(base.appendingPathComponent("api/me"), method: "DELETE", account: token)
        if let id = me?.id { RollShare.forgetShares(ownedBy: id) }
        forget()
    }

    // MARK: Your profile

    /// Fetch your profile again (and notice if the session has ended).
    func refresh() async {
        guard let base = ShareLinks.base, let token = Self.sessionToken else { return }
        do {
            let data = try await ShareAPI.send(base.appendingPathComponent("api/me"), method: "GET", account: token)
            if let me = try? JSONDecoder().decode(Me.self, from: data) { remember(me) }
        } catch let error as ShareAPI.HTTPError where error.status == 401 {
            forget()
        } catch {}
    }

    /// Agree to the rules for public rolls.
    func acceptTerms() async throws {
        guard let base = ShareLinks.base, let token = Self.sessionToken else { throw Failure.notConfigured }
        let data = try await ShareAPI.send(base.appendingPathComponent("api/me/terms"), method: "POST", account: token)
        if let me = try? JSONDecoder().decode(Me.self, from: data) { remember(me) }
    }

    /// Put your name (and, if it changed, your headshot) on your profile, or take them off
    /// when you've chosen to hide them on cards.
    func syncProfile(_ profile: Profile, avatarChanged: Bool) async {
        guard let base = ShareLinks.base, let token = Self.sessionToken else { return }
        let show = profile.showOnCards
        do {
            var data = try await ShareAPI.send(base.appendingPathComponent("api/me"), method: "PUT", account: token,
                                               json: ["name": show ? profile.name : ""])
            let avatarURL = base.appendingPathComponent("api/me/avatar")
            if show, let photo = profile.photo, avatarChanged || me?.avatar == nil,
               let jpeg = photo.jpegData(compressionQuality: 0.85) {
                data = try await ShareAPI.send(avatarURL, method: "PUT", account: token, body: jpeg, type: "image/jpeg")
            } else if !show || profile.photo == nil, me?.avatar != nil {
                data = try await ShareAPI.send(avatarURL, method: "DELETE", account: token)
            }
            if let me = try? JSONDecoder().decode(Me.self, from: data) { remember(me) }
        } catch let error as ShareAPI.HTTPError where error.status == 401 {
            forget()
        } catch {}
    }

    // MARK: Keeping track

    private func remember(_ me: Me) {
        self.me = me
        if let data = try? JSONEncoder().encode(me) { UserDefaults.standard.set(data, forKey: AccountKeys.me) }
    }

    private func forget() {
        Self.storeToken(nil)
        UserDefaults.standard.removeObject(forKey: AccountKeys.me)
        UserDefaults.standard.removeObject(forKey: AccountKeys.appleUser)
        me = nil
    }

    /// If you've stopped using Sign in with Apple for Film Exposures (in Settings), sign out.
    private func checkAppleCredential() {
        guard let user = UserDefaults.standard.string(forKey: AccountKeys.appleUser) else { return }
        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: user) { state, _ in
            guard state == .revoked || state == .notFound else { return }
            Task { @MainActor in Account.shared.forget() }
        }
    }
}

private enum AccountKeys {
    static let me = "account.me"
    static let appleUser = "account.appleUser"
    static let keychainService = "com.davidanderson.retrocam.account"
}

/// The Sign in with Apple button, wired to the account. Reports failures through `onError`.
struct AppleSignInButton: View {
    var onError: (String) -> Void = { _ in }
    var onSignedIn: () -> Void = {}
    @ObservedObject private var account = Account.shared

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = [.fullName]
        } onCompletion: { result in
            Task {
                do {
                    try await account.signIn(with: result)
                    if account.isSignedIn { onSignedIn() }
                } catch {
                    onError(error.localizedDescription)
                }
            }
        }
        .signInWithAppleButtonStyle(.white)
        .frame(height: 44)
        .clipShape(Capsule())
        .disabled(account.working)
        .opacity(account.working ? 0.5 : 1)
    }
}
