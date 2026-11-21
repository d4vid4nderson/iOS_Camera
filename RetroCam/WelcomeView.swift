import SwiftUI

/// The first thing you see: start shooting straight away (the camera needs no account, and
/// App Review doesn't let an app insist on one for it), or sign in to share rolls, then pick
/// a @username and a photo (AccountSetup).
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
                    Text("Film Exposures").font(.system(size: 15, weight: .semibold)).foregroundStyle(accent)
                        .padding(.top, 24)
                    if (account.isSignedIn && account.needsSetup) || settingUp {
                        FieldLabel("Set up your profile")
                        AccountSetup(accent: accent, onStart: { settingUp = true }, onRefused: { settingUp = false }) {
                            settingUp = false
                            onFinish()
                        }
                    } else {
                        start
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 30)
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
    }

    /// The camera first (it needs no account), then signing in for sharing.
    private var start: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Share the roll,\nnot just the shot.")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("A film camera for your iPhone: load a film, shoot a roll of 36, share the whole roll.")
                .font(.system(size: 16)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            PillButton(text: "Start shooting", filled: true, accent: accent) {
                UserDefaults.standard.set(true, forKey: Self.skipKey)
                onFinish()
            }
            FootnoteText("Frames develop instantly. Prefer to wait? Choose Roll end or Next morning in your rolls.")

            Divider().overlay(ProfileStyle.divider).padding(.vertical, 6)

            Text("Sign in to share rolls").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 10) {
                point("person.crop.circle", "Your profile: a @username, your name and photo.")
                point("person.2", "Share rolls with friends, your followers or everyone.")
                point("heart", "Follow photographers and like their frames.")
            }
            if let note { NoteText(text: note, accent: accent) }
            SignInButtons(onError: { note = $0 }, onSignedIn: {
                note = nil
                // A returning account with a username goes straight to the camera; a new one
                // picks its username and photo first.
                if !account.needsSetup { onFinish() }
            })
            FootnoteText("You can sign in later from your profile. Your rolls stay on this phone either way.")
            HStack(spacing: 8) {
                Link("Privacy", destination: URL(string: "https://filmexposures.com/privacy")!)
                    .frame(minWidth: 44, minHeight: 44)
                Link("Terms", destination: URL(string: "https://filmexposures.com/terms")!)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .font(.system(size: 14, weight: .medium))
            .tint(Color(white: 0.6))
        }
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(accent).frame(width: 22)
                .accessibilityHidden(true)
            Text(text).font(.system(size: 15)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
        }
    }
}
