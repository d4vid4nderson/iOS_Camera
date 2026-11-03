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
            Text(step == .age ? "STEP 1 OF 3" : step == .handle ? "STEP 2 OF 3" : "STEP 3 OF 3").font(.mono(9, .semibold)).foregroundStyle(.secondary)
            switch step {
            case .age: ageStep
            case .handle: handleStep
            case .photo: photoStep
            }
            if let note {
                Text(note).font(.mono(10, .semibold)).foregroundStyle(accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("SIGN OUT") { Task { await account.signOut() } }
                .font(.mono(10, .bold)).foregroundStyle(Color(white: 0.55))
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
            Text("YOUR DATE OF BIRTH").font(.mono(15, .bold)).foregroundStyle(accent)
            Text("We ask everyone before they make a profile. It isn't shown on your profile or saved with your account.")
                .font(.mono(10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            DatePicker("Date of birth", selection: $born, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .onChange(of: born) { _, _ in bornPicked = true }
            primary(working ? "CHECKING…" : "CONTINUE", enabled: bornPicked && !working, action: saveAge)
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
                note = error.localizedDescription.uppercased()
            }
            working = false
        }
    }

    // MARK: Handle

    private var handleStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PICK YOUR HANDLE").font(.mono(15, .bold)).foregroundStyle(accent)
            Text("It's how people find you and know who's asking to follow them. Letters, numbers, _ and . (3 to 20).")
                .font(.mono(10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            field("@", prompt: "yourname", text: $handle)
                .onChange(of: handle) { _, new in
                    let cleaned = String(new.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }.prefix(20))
                    if cleaned != new { handle = cleaned }
                }
            VStack(alignment: .leading, spacing: 6) {
                Text("NAME").font(.mono(9, .semibold)).foregroundStyle(.secondary)
                field(nil, prompt: "YOUR NAME", text: $name)
                    .onChange(of: name) { _, new in
                        if new.count > Profile.maxNameLength { name = String(new.prefix(Profile.maxNameLength)) }
                    }
            }
            primary(working ? "CHECKING…" : "CONTINUE", enabled: handle.count >= 3 && !working, action: saveHandle)
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
                note = error.localizedDescription.uppercased()
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
            Text("ADD YOUR PHOTO").font(.mono(15, .bold)).foregroundStyle(accent)
            HStack(spacing: 16) {
                ProfileAvatar(photo: photo, size: 96)
                    .overlay { if working { ProgressView() } }
                VStack(alignment: .leading, spacing: 3) {
                    if let handle = account.me?.handle {
                        Text("@\(handle)").font(.mono(13, .bold)).foregroundStyle(.white)
                    }
                    if !name.isEmpty {
                        Text(name.uppercased()).font(.mono(10)).foregroundStyle(.secondary)
                    }
                }
            }
            Text(providerPhotos.isEmpty
                 ? "Choose one from your photos. It shows on your profile and next to your likes."
                 : "Use the photo from your sign-in, or choose one from your photos.")
                .font(.mono(10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(providerPhotos, id: \.self) { provider in
                secondary("USE MY \(provider.uppercased()) PHOTO") { useProviderPhoto(provider) }
            }
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Text(photo == nil ? "CHOOSE FROM PHOTOS" : "CHOOSE ANOTHER")
                    .font(.mono(11, .bold))
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Capsule().fill(Color(white: 0.16)))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(working)
            primary(photo == nil ? "SKIP FOR NOW" : "DONE", enabled: !working, action: onDone)
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
                note = error.localizedDescription.uppercased()
            }
            working = false
        }
    }

    // MARK: Pieces

    private func field(_ prefix: String?, prompt: String, text: Binding<String>) -> some View {
        HStack(spacing: 2) {
            if let prefix { Text(prefix).font(.mono(14, .semibold)).foregroundStyle(.secondary) }
            TextField("", text: text, prompt: Text(prompt).foregroundStyle(Color(white: 0.4)))
                .font(.mono(14, .semibold))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Capsule().fill(Color(white: 0.16)))
    }

    private func primary(_ text: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.mono(11, .bold))
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(Capsule().fill(accent.opacity(enabled ? 0.18 : 0.08)))
                .overlay(Capsule().stroke(accent.opacity(enabled ? 1 : 0.4), lineWidth: 1))
                .foregroundStyle(enabled ? accent : accent.opacity(0.5))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func secondary(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.mono(11, .bold))
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(Capsule().fill(Color(white: 0.16)))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(working)
    }
}
