import PhotosUI
import SwiftUI

private extension Font {
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Share a film's recipe: a card with a QR code a friend scans with their iPhone camera,
/// plus the link. Either opens Exposures and offers to add the film.
///
/// The card shows your latest frame shot on the film when there is one (PHOTO), or the
/// film's tone scale (TONES) — also the choice for anyone who'd rather not share a photo.
/// Your headshot and name (set here, kept on this phone) go in the card's corner.
struct FilmShareSheet: View {
    let film: FilmStock
    let accent: Color
    @Environment(\.dismiss) private var dismiss
    @State private var sharing: ShareItems?
    @State private var photo: UIImage?
    @State private var lookedForPhoto = false
    @State private var usePhoto = true
    @State private var card: UIImage?
    @State private var profile = Profile.load()
    @State private var editingProfile = false
    @State private var nameDraft = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var avatarVersion = 0

    /// Re-render the card when any of these change.
    private var cardKey: String {
        "\(usePhoto)|\(profile.name)|\(profile.showOnCards)|\(avatarVersion)"
    }

    private var url: URL? { FilmCode.url(for: film) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Text("SHARE FILM").font(.mono(10, .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button("DONE") { dismiss() }.font(.mono(11, .bold)).foregroundStyle(accent)
                }
                HStack {
                    Text(film.name).font(.mono(20, .bold)).foregroundStyle(accent)
                    Spacer()
                    if photo != nil {
                        chip("PHOTO", selected: usePhoto) { usePhoto = true }
                        chip("TONES", selected: !usePhoto) { usePhoto = false }
                    }
                }
                profileRow

                if let url {
                    ZStack {
                        if let card {
                            Image(uiImage: card)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                                .accessibilityLabel("Share card for \(film.name)")
                        } else {
                            RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.14))
                                .aspectRatio(FilmCodeCard.size.width / FilmCodeCard.size.height, contentMode: .fit)
                                .overlay(ProgressView())
                        }
                    }
                    .frame(maxHeight: 440)

                    Text(lookedForPhoto && photo == nil
                         ? "Shoot a frame on this film to put it on the card. Scanning the code adds the film to Exposures, every setting included."
                         : "Scan with the iPhone camera to add this film to Exposures. Every setting comes with it.")
                        .font(.mono(10)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        if let card { sharing = ShareItems(items: [card, url]) }
                    } label: {
                        Text("SHARE CARD")
                            .font(.mono(12, .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(accent.opacity(0.18)))
                            .overlay(Capsule().stroke(accent, lineWidth: 1))
                            .foregroundStyle(accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(card == nil)
                } else {
                    Text("This film couldn't be packed into a code.").font(.mono(11)).foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .presentationDetents([.large])
        .presentationBackground(Color(white: 0.09))
        .preferredColorScheme(.dark)
        .task(id: cardKey) { await makeCard() }
        .sheet(item: $sharing) { item in
            ActivityView(items: item.items).ignoresSafeArea()
        }
    }

    private func makeCard() async {
        guard let url else { return }
        let film = self.film
        if !lookedForPhoto {
            photo = await Task.detached(priority: .userInitiated) {
                RollStore.latestFrame(filmID: film.id)
            }.value
            lookedForPhoto = true
        }
        let chosen = usePhoto ? photo : nil
        let sharer = profile.showOnCards && !profile.isEmpty
            ? FilmCodeCard.Sharer(name: profile.name, avatar: profile.photo) : nil
        card = await Task.detached(priority: .userInitiated) {
            FilmCodeCard.render(film: film, url: url, photo: chosen, sharer: sharer)
        }.value
    }

    // MARK: Your photo & name

    @ViewBuilder private var profileRow: some View {
        if editingProfile {
            profileEditor
        } else {
            HStack(spacing: 10) {
                avatar(size: 30)
                Text(profile.isEmpty ? "ADD YOUR PHOTO & NAME"
                     : profile.name.isEmpty ? "YOUR PHOTO" : profile.name)
                    .font(.mono(11, .bold))
                    .foregroundStyle(profile.isEmpty ? accent : .white)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if !profile.isEmpty {
                    chip(profile.showOnCards ? "ON CARD" : "HIDDEN", selected: profile.showOnCards) {
                        profile.showOnCards.toggle()
                        profile.saveSettings()
                    }
                }
                chip(profile.isEmpty ? "ADD" : "EDIT", selected: false) {
                    nameDraft = profile.name
                    withAnimation(.snappy(duration: 0.2)) { editingProfile = true }
                }
            }
        }
    }

    private var profileEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                avatar(size: 64)
                VStack(alignment: .leading, spacing: 8) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        chipText(profile.photo == nil ? "CHOOSE HEADSHOT" : "CHANGE PHOTO", selected: false)
                    }
                    .buttonStyle(.plain)
                    if profile.photo != nil {
                        chip("REMOVE PHOTO", selected: false) {
                            Profile.removeHeadshot()
                            profile.photo = nil
                            avatarVersion += 1
                        }
                    }
                }
            }
            TextField("", text: $nameDraft,
                      prompt: Text("YOUR NAME OR @HANDLE").foregroundStyle(Color(white: 0.4)))
                .font(.mono(13, .semibold))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(saveName)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Capsule().fill(Color(white: 0.16)))
                .onChange(of: nameDraft) { _, new in
                    if new.count > Profile.maxNameLength { nameDraft = String(new.prefix(Profile.maxNameLength)) }
                }
            HStack {
                Text("Kept on this phone. Only appears on cards you share.")
                    .font(.mono(9)).foregroundStyle(.secondary)
                Spacer()
                chip("DONE", selected: true) { saveName() }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.12)))
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let headshot = await Task.detached(priority: .userInitiated) {
                        Profile.saveHeadshot(from: data)
                    }.value
                    if let headshot {
                        profile.photo = headshot
                        avatarVersion += 1
                    }
                }
                pickerItem = nil
            }
        }
    }

    private func saveName() {
        profile.name = Profile.cleanName(nameDraft)
        profile.saveSettings()
        withAnimation(.snappy(duration: 0.2)) { editingProfile = false }
    }

    private func avatar(size: CGFloat) -> some View {
        ZStack {
            if let image = profile.photo {
                Image(uiImage: image).resizable().scaledToFill()
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
