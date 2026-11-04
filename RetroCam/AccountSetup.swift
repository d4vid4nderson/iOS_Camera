import PhotosUI
import SwiftUI

private extension Font {
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Right after signing in: your date of birth (accounts are for people 13 and older; it's
/// checked, not kept), then your @handle (and name), then your photo, from your Google or
/// Facebook sign-in or from your library. Shown in your profile until you have a handle; a
/// handle is how people find you and know who's asking to follow them.
struct AccountSetup: View {
    let accent: Color
    var onStart: () -> Void = {}
    /// Under 13: the account was deleted and this phone is signed out.
    var onRefused: () -> Void = {}
    /// Setup is finished: your profile shows.
    let onDone: () -> Void

    enum Step { case age, handle, photo }

    @ObservedObject private var account = Account.shared
    @State private var step: Step = .age
    // Starts on today, so nothing suggests an answer; CONTINUE waits until a date is picked.
    @State private var born = Date()
    @State private var bornPicked = false
    @State private var name = ""
    @State private var handle = ""
    @State private var note: String?
    @State private var working = false
    @State private var photo: UIImage?
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FieldLabel(step == .age ? "Step 1 of 3" : step == .handle ? "Step 2 of 3" : "Step 3 of 3")
            switch step {
            case .age: ageStep
            case .handle: handleStep
            case .photo: photoStep
            }
            if let note { NoteText(text: note, accent: accent) }
            Button("Sign out") { Task { await account.signOut() } }
                .font(.system(size: 15, weight: .medium)).foregroundStyle(Color(white: 0.55))
                .padding(.top, 6)
        }
        .onAppear {
            onStart()
            let saved = Profile.load()
            name = saved.name.isEmpty ? (account.me?.name ?? "") : saved.name
            photo = saved.photo
            if account.me?.ageConfirmed == true { step = account.me?.handle == nil ? .handle : .photo }
        }
        .onChange(of: account.headshotVersion) { _, _ in photo = Profile.load().photo }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            working = true
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let headshot = await Task.detached(priority: .userInitiated) { Profile.saveHeadshot(from: data) }.value
                    if let headshot {
                        photo = headshot
                        var profile = Profile.load()
                        profile.photo = headshot
                        await account.syncProfile(profile, avatarChanged: true)
                    }
                }
                pickerItem = nil
                working = false
            }
        }
    }

    // MARK: Date of birth

    private var ageStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            title("Your date of birth")
            FootnoteText("We ask everyone before they make a profile. It isn't shown on your profile or saved with your account.")
            DatePicker("Date of birth", selection: $born, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .onChange(of: born) { _, _ in bornPicked = true }
            primary(working ? "Checking…" : "Continue", enabled: bornPicked && !working, action: saveAge)
        }
    }

    private func saveAge() {
        working = true
        note = nil
        Task {
            do {
                switch try await account.confirmAge(born: born) {
                case .confirmed: step = account.me?.handle == nil ? .handle : .photo
                case .tooYoung: onRefused()
                }
            } catch {
                note = error.localizedDescription
            }
            working = false
        }
    }

    // MARK: Handle

    private var handleStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            title("Pick your username")
            FootnoteText("It's how people find you and know who's asking to follow them. Letters, numbers, _ and . (3 to 20).")
            ProfileField(prefix: "@", prompt: "yourname", text: $handle)
                .onChange(of: handle) { _, new in
                    let cleaned = String(new.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }.prefix(20))
                    if cleaned != new { handle = cleaned }
                }
            VStack(alignment: .leading, spacing: 8) {
                FieldLabel("Name")
                ProfileField(prompt: "Your name", text: $name, capitalization: .words)
                    .onChange(of: name) { _, new in
                        if new.count > Profile.maxNameLength { name = String(new.prefix(Profile.maxNameLength)) }
                    }
            }
            primary(working ? "Checking…" : "Continue", enabled: handle.count >= 3 && !working, action: saveHandle)
        }
    }

    private func saveHandle() {
        working = true
        note = nil
        Task {
            do {
                try await account.updateSocial(handle: handle)
                var profile = Profile.load()
                profile.name = Profile.cleanName(name)
                profile.saveSettings()
                await account.syncProfile(profile, avatarChanged: false)
                step = .photo
            } catch {
                note = error.localizedDescription
            }
            working = false
        }
    }

    // MARK: Photo

    private var providerPhotos: [String] {
        (account.me?.photos ?? []).filter { $0 == "google" || $0 == "facebook" }
    }

    private var photoStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            title("Add your photo")
            HStack(spacing: 16) {
                ProfileAvatar(photo: photo, size: 96)
                    .overlay { if working { ProgressView() } }
                VStack(alignment: .leading, spacing: 3) {
                    if !name.isEmpty {
                        Text(name).font(.system(size: 20, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                    }
                    if let handle = account.me?.handle {
                        Text("@\(handle)").font(.mono(14, .bold)).foregroundStyle(accent).lineLimit(1)
                    }
                }
            }
            FootnoteText(providerPhotos.isEmpty
                 ? "Choose one from your photos. It shows on your profile and next to your likes."
                 : "Use the photo from your sign-in, or choose one from your photos.")
            ForEach(providerPhotos, id: \.self) { provider in
                secondary("Use my \(provider.capitalized) photo") { useProviderPhoto(provider) }
            }
            PhotosPicker(selection: $pickerItem, matching: .images) {
                PillLabel(text: photo == nil ? "Choose from photos" : "Choose another", accent: accent)
            }
            .buttonStyle(.plain)
            .disabled(working)
            primary(photo == nil ? "Skip for now" : "Done", enabled: !working, action: onDone)
        }
    }

    private func useProviderPhoto(_ provider: String) {
        working = true
        note = nil
        Task {
            do {
                try await account.useProviderPhoto(provider)
                photo = Profile.load().photo
            } catch {
                note = error.localizedDescription
            }
            working = false
        }
    }

    // MARK: Pieces

    private func title(_ text: String) -> some View {
        Text(text).font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
    }

    private func primary(_ text: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        PillButton(text: text, filled: true, accent: accent, action: action)
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.4)
    }

    private func secondary(_ text: String, action: @escaping () -> Void) -> some View {
        PillButton(text: text, accent: accent, action: action)
            .disabled(working)
    }
}
