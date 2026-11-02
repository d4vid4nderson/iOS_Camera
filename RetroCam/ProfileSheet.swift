import PhotosUI
import SwiftUI

private extension Font {
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Your profile: the headshot and name that go on cards you share. Opened from your
/// photo in the top-right corner of the camera, or from a share sheet. Kept on this
/// phone only.
struct ProfileSheet: View {
    let accent: Color
    var onChange: (Profile) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var profile = Profile.load()
    @State private var nameDraft = Profile.load().name
    @State private var pickerItem: PhotosPickerItem?
    @State private var working = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("YOUR PROFILE").font(.mono(10, .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button("DONE") { save(); dismiss() }.font(.mono(11, .bold)).foregroundStyle(accent)
                }

                HStack(spacing: 16) {
                    ProfileAvatar(photo: profile.photo, size: 96)
                        .overlay { if working { ProgressView() } }
                    VStack(alignment: .leading, spacing: 8) {
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            chipText(profile.photo == nil ? "CHOOSE HEADSHOT" : "CHANGE PHOTO", selected: true)
                        }
                        .buttonStyle(.plain)
                        if profile.photo != nil {
                            chip("REMOVE PHOTO", selected: false) {
                                Profile.removeHeadshot()
                                profile.photo = nil
                                onChange(profile)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("NAME").font(.mono(9, .semibold)).foregroundStyle(.secondary)
                    TextField("", text: $nameDraft,
                              prompt: Text("YOUR NAME OR @HANDLE").foregroundStyle(Color(white: 0.4)))
                        .font(.mono(14, .semibold))
                        .foregroundStyle(.white)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(save)
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .background(Capsule().fill(Color(white: 0.16)))
                        .onChange(of: nameDraft) { _, new in
                            if new.count > Profile.maxNameLength { nameDraft = String(new.prefix(Profile.maxNameLength)) }
                        }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("ON SHARE CARDS").font(.mono(9, .semibold)).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        chip("SHOW", selected: profile.showOnCards) { setShow(true) }
                        chip("HIDE", selected: !profile.showOnCards) { setShow(false) }
                    }
                }

                Text("Kept on this phone. Your photo and name only appear on film and roll cards you share.")
                    .font(.mono(10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .presentationDetents([.medium, .large])
        .presentationBackground(Color(white: 0.09))
        .preferredColorScheme(.dark)
        .onDisappear(perform: save)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            working = true
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let headshot = await Task.detached(priority: .userInitiated) {
                        Profile.saveHeadshot(from: data)
                    }.value
                    if let headshot {
                        profile.photo = headshot
                        onChange(profile)
                    }
                }
                pickerItem = nil
                working = false
            }
        }
    }

    private func save() {
        let name = Profile.cleanName(nameDraft)
        guard name != profile.name else { return }
        profile.name = name
        profile.saveSettings()
        onChange(profile)
    }

    private func setShow(_ show: Bool) {
        profile.showOnCards = show
        profile.saveSettings()
        onChange(profile)
    }

    private func chip(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { chipText(text, selected: selected) }
            .buttonStyle(.plain)
    }

    private func chipText(_ text: String, selected: Bool) -> some View {
        Text(text)
            .font(.mono(10, .bold))
            .lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Capsule().fill(selected ? accent.opacity(0.18) : Color(white: 0.15)))
            .overlay(Capsule().stroke(selected ? accent : .clear, lineWidth: 1))
            .foregroundStyle(selected ? accent : .white)
    }
}

/// A round headshot, or a person glyph when there's none.
struct ProfileAvatar: View {
    let photo: UIImage?
    let size: CGFloat

    var body: some View {
        ZStack {
            if let photo {
                Image(uiImage: photo).resizable().scaledToFill()
            } else {
                Color(white: 0.18)
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(Color(white: 0.5))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
