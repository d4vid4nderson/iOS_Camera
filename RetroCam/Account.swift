import AuthenticationServices
import Security
import SwiftUI

/// Your Film Exposures account, made with Sign in with Apple, Google or Facebook (several can
/// be added to one account). It's what lets you put rolls on
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
        /// "apple", "google", "facebook": the sign-ins on this account.
        var logins: [String]?
        /// Where the profile photo came from: "own", "google" or "facebook".
        var avatarSource: String?
        /// Sign-ins whose photo you can go back to.
        var photos: [String]?
        /// Your @handle (without the @): how people find and follow you.
        var handle: String?
        /// Whether search finds you (on unless you turn it off).
        var discoverable: Bool?

        func has(_ provider: String) -> Bool { logins?.contains(provider) == true }
    }

    @Published private(set) var me: Me?
    @Published private(set) var working = false
    /// Bumped when a Google or Facebook photo becomes your headshot on this phone.
    @Published private(set) var headshotVersion = 0

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
        guard ShareLinks.isConfigured else { throw Failure.notConfigured }
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8) else { throw Failure.noToken }

        let profile = Profile.load()
        var body: [String: Any] = ["identityToken": identityToken]
        if profile.showOnCards, !profile.name.isEmpty { body["name"] = profile.name }
        try await finish("api/auth/apple", body: body)
        UserDefaults.standard.set(credential.user, forKey: AccountKeys.appleUser)
    }

    /// Sign in with Google (or, signed in already, add Google to this account).
    func signInWithGoogle() async throws {
        do {
            let idToken = try await SocialSignIn.googleIDToken()
            try await finish("api/auth/google", body: ["idToken": idToken])
        } catch SocialSignIn.Failure.cancelled {
            return
        }
    }

    /// Sign in with Facebook (or, signed in already, add Facebook to this account).
    func signInWithFacebook() async throws {
        do {
            let code = try await SocialSignIn.facebookCode()
            try await finish("api/auth/facebook", body: ["code": code])
        } catch SocialSignIn.Failure.cancelled {
            return
        }
    }

    /// Send a verified sign-in to the server. Signed in already, this adds it to the account
    /// (the server keeps the session); otherwise it starts a session. Then a Google or
    /// Facebook photo becomes your headshot if you haven't chosen one, and your name and
    /// headshot go to your profile.
    private func finish(_ path: String, body: [String: Any]) async throws {
        guard let base = ShareLinks.base else { throw Failure.notConfigured }
        working = true
        defer { working = false }
        let existing = isSignedIn ? Self.sessionToken : nil
        let data = try await ShareAPI.send(base.appendingPathComponent(path), method: "POST", account: existing, json: body)
        guard let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let meInfo = info["me"], let meData = try? JSONSerialization.data(withJSONObject: meInfo),
              let me = try? JSONDecoder().decode(Me.self, from: meData),
              let token = (info["token"] as? String) ?? existing else {
            throw ShareAPI.Failure.server("The share server sent back something unexpected.")
        }
        Self.storeToken(token)
        remember(me)

        var profile = Profile.load()
        if profile.photo == nil, me.avatarSource == "google" || me.avatarSource == "facebook",
           let photo = await downloadHeadshot(me.avatar) {
            profile.photo = photo
            if profile.name.isEmpty, let name = me.name {
                profile.name = Profile.cleanName(name)
                profile.saveSettings()
            }
            headshotVersion += 1
            await syncProfile(profile, avatarChanged: false)
        } else {
            await syncProfile(profile, avatarChanged: profile.photo != nil && me.avatarSource != "own")
        }
    }

    /// Make the photo from a Google or Facebook sign-in your headshot again.
    func useProviderPhoto(_ provider: String) async throws {
        guard let base = ShareLinks.base, let token = Self.sessionToken else { throw Failure.notConfigured }
        working = true
        defer { working = false }
        let data = try await ShareAPI.send(base.appendingPathComponent("api/me/avatar/use"), method: "POST",
                                           account: token, json: ["provider": provider])
        guard let me = try? JSONDecoder().decode(Me.self, from: data) else { return }
        remember(me)
        if await downloadHeadshot(me.avatar) != nil { headshotVersion += 1 }
    }

    /// Fetch a profile photo and save it as this phone's headshot.
    private func downloadHeadshot(_ url: URL?) async -> UIImage? {
        guard let url, let result = try? await URLSession.shared.data(from: url),
              (result.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let data = result.0
        return await Task.detached(priority: .userInitiated) { Profile.saveHeadshot(from: data) }.value
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

    /// Your @handle and whether search finds you. Throws the server's reason when a handle
    /// is taken or not allowed.
    func updateSocial(handle: String? = nil, discoverable: Bool? = nil) async throws {
        guard let base = ShareLinks.base, let token = Self.sessionToken else { throw Failure.notConfigured }
        var body: [String: Any] = [:]
        if let handle { body["handle"] = handle }
        if let discoverable { body["discoverable"] = discoverable }
        let data = try await ShareAPI.send(base.appendingPathComponent("api/me"), method: "PUT", account: token, json: body)
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
            } else if me?.avatar != nil, !show || (avatarChanged && profile.photo == nil) {
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
            guard state == .revoked else { return }
            Task { @MainActor in Account.shared.forget() }
        }
    }
}

private enum AccountKeys {
    static let me = "account.me"
    static let appleUser = "account.appleUser"
    static let keychainService = "com.davidanderson.retrocam.account"
}

/// Every way to sign in that's set up: Apple always, Google and Facebook once configured.
struct SignInButtons: View {
    var onError: (String) -> Void = { _ in }
    var onSignedIn: () -> Void = {}

    var body: some View {
        VStack(spacing: 8) {
            AppleSignInButton(onError: onError, onSignedIn: onSignedIn)
            if SocialSignIn.googleAvailable {
                ProviderButton(provider: "google", onError: onError, onSignedIn: onSignedIn)
            }
            if SocialSignIn.facebookAvailable {
                ProviderButton(provider: "facebook", onError: onError, onSignedIn: onSignedIn)
            }
        }
    }
}

/// "Continue with Google" / "Continue with Facebook" (or "Add …" when signed in already).
struct ProviderButton: View {
    let provider: String
    var onError: (String) -> Void = { _ in }
    var onSignedIn: () -> Void = {}
    @ObservedObject private var account = Account.shared

    private var name: String { provider == "google" ? "Google" : "Facebook" }

    var body: some View {
        Button {
            Task {
                do {
                    if provider == "google" { try await account.signInWithGoogle() } else { try await account.signInWithFacebook() }
                    if account.isSignedIn { onSignedIn() }
                } catch {
                    onError(error.localizedDescription)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(provider == "google" ? "G" : "f")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(provider == "google" ? Color(red: 0.26, green: 0.52, blue: 0.96) : .white)
                Text(account.isSignedIn ? "Add \(name) sign-in" : "Continue with \(name)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(provider == "google" ? Color.black : .white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Capsule().fill(provider == "google" ? Color.white : Color(red: 0.09, green: 0.47, blue: 0.95)))
        }
        .buttonStyle(.plain)
        .disabled(account.working)
        .opacity(account.working ? 0.5 : 1)
        .accessibilityLabel(account.isSignedIn ? "Add \(name) sign-in" : "Continue with \(name)")
    }
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
