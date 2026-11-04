import SwiftUI

private extension Font {
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// The first thing you see: sign in, then pick a @handle and a photo (AccountSetup),
/// then the camera. The camera doesn't need an account (and App Review doesn't let an app
/// insist on one for it), so you can go straight to the camera instead.
struct WelcomeView: View {
    let accent: Color
    /// Finished or skipped: on to the camera.
    let onFinish: () -> Void
    @ObservedObject private var account = Account.shared
    @State private var note: String?
    @State private var settingUp = false

    /// Shown at launch when you're signed out and haven't chosen to go without an account,
    /// or signed in without a handle yet.
    static func isNeeded() -> Bool {
        guard ShareLinks.isConfigured else { return false }
        let account = Account.shared
        if account.isSignedIn { return account.needsSetup }
        return !UserDefaults.standard.bool(forKey: skipKey)
    }

    /// "Use the camera without an account" is remembered until you next sign out.
    static let skipKey = "welcome.skipped"   // Account.forget() clears it

    var body: some View {
        ZStack {
            Color(white: 0.06).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("FILM EXPOSURES").font(.mono(12, .bold)).foregroundStyle(accent)
                        .padding(.top, 24)
                    if (account.isSignedIn && account.needsSetup) || settingUp {
                        Text("SET UP YOUR PROFILE").font(.mono(10, .semibold)).foregroundStyle(.secondary)
                        AccountSetup(accent: accent, onStart: { settingUp = true }, onRefused: { settingUp = false }) {
                            settingUp = false
                            onFinish()
                        }
                    } else {
                        signIn
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 30)
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
    }

    private var signIn: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("A film camera\nfor your iPhone.")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text("Shoot rolls of 36, let them develop, and share them with the people you choose.")
                .font(.mono(12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 10) {
                point("person.crop.circle", "Your profile: a @username, your name and photo.")
                point("person.2", "Share rolls with friends, your followers or everyone.")
                point("heart", "Follow photographers and like their frames.")
            }
            .padding(.vertical, 4)
            if let note {
                Text(note).font(.mono(10, .semibold)).foregroundStyle(accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SignInButtons(onError: { note = $0.uppercased() }, onSignedIn: {
                note = nil
                // A returning account with a handle goes straight to the camera; a new one
                // picks its handle and photo first.
                if !account.needsSetup { onFinish() }
            })
            Button {
                UserDefaults.standard.set(true, forKey: Self.skipKey)
                onFinish()
            } label: {
                Text("USE THE CAMERA WITHOUT AN ACCOUNT")
                    .font(.mono(10, .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(Color(white: 0.6))
            }
            .buttonStyle(.plain)
            Text("You can sign in later from your profile. Your rolls stay on this phone either way.")
                .font(.mono(9)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                Link("PRIVACY", destination: URL(string: "https://filmexposures.com/privacy")!)
                Link("TERMS", destination: URL(string: "https://filmexposures.com/terms")!)
            }
            .font(.mono(9, .semibold))
            .tint(Color(white: 0.55))
        }
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(accent).frame(width: 20)
            Text(text).font(.mono(11)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
        }
    }
}
