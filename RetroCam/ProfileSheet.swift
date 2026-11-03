import Combine
import PhotosUI
import SwiftUI

private extension Font {
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Your profile: the headshot and name that go on cards you share, and what film cards
/// show. Opened from your photo in the top-right corner of the camera.
///
/// Signed in with Apple (once sharing is set up), it's also your public profile: choose
/// which rolls are public, see your profile as others do, sign out or delete the account.
struct ProfileSheet: View {
    @ObservedObject var camera: CameraModel
    let accent: Color
    var onChange: (Profile) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var account = Account.shared
    @State private var profile = Profile.load()
    @State private var nameDraft = Profile.load().name
    @State private var pickerItem: PhotosPickerItem?
    @State private var working = false

    @State private var myRolls: [Roll] = []
    @State private var records: [Int: RollShare.Record] = [:]
    @State private var busy: [Int: String] = [:]
    @State private var askingTerms: Roll?
    @State private var note: String?
    @State private var viewingMine: IncomingUser?
    @State private var confirmDeleteAccount = false
    @State private var makingCard = false
    @State private var openRoll: RollRef?
    @State private var sharing: ShareItems?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("YOUR PROFILE").font(.mono(10, .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button("DONE") { save(); dismiss() }.font(.mono(11, .bold)).foregroundStyle(accent)
                }

                HStack(alignment: .top, spacing: 16) {
                    ProfileAvatar(photo: profile.photo, size: 96)
                        .overlay { if working { ProgressView() } }
                    Spacer(minLength: 0)
                    if ShareLinks.isConfigured, let me = account.me, account.isSignedIn {
                        signInCorner(me)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            chipText(profile.photo == nil ? "CHOOSE HEADSHOT" : "CHANGE PHOTO", selected: true)
                        }
                        .buttonStyle(.plain)
                        ForEach(providerPhotos, id: \.self) { provider in
                            chip("USE \(provider.uppercased()) PHOTO", selected: false) { useProviderPhoto(provider) }
                        }
                        if profile.photo != nil {
                            chip("REMOVE PHOTO", selected: false) {
                                Profile.removeHeadshot()
                                profile.photo = nil
                                onChange(profile)
                                syncAccount(avatarChanged: true)
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

                if ShareLinks.isConfigured {
                    accountSection
                    signedOutSection
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("ON SHARE CARDS").font(.mono(9, .semibold)).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        chip("SHOW", selected: profile.showOnCards) { setShow(true) }
                        chip("HIDE", selected: !profile.showOnCards) { setShow(false) }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("FILM CARDS SHOW").font(.mono(9, .semibold)).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        chip("MY LATEST FRAME", selected: profile.filmCardsUsePhoto) { setPhotoCards(true) }
                        chip("TONE SCALE", selected: !profile.filmCardsUsePhoto) { setPhotoCards(false) }
                    }
                    Text("A frame you shot on the film, when there is one; otherwise its tone scale.")
                        .font(.mono(9)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if ShareLinks.isConfigured {
                    accountFooter
                } else {
                    Text("Kept on this phone. Your photo and name only appear on film and roll cards you share.")
                        .font(.mono(10)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // The website's policies and support form (App Review asks for these in the app).
                HStack(spacing: 16) {
                    Link("PRIVACY", destination: URL(string: "https://filmexposures.com/privacy")!)
                    Link("TERMS", destination: URL(string: "https://filmexposures.com/terms")!)
                    Link("SUPPORT", destination: URL(string: "https://filmexposures.com/support")!)
                }
                .font(.mono(9, .semibold))
                .tint(Color(white: 0.55))
                .padding(.top, 6)
            }
            .padding(20)
        }
        .overlay { if let roll = askingTerms { termsCard(roll) } }
        .fullScreenCover(item: $viewingMine) { me in
            UserProfileView(userID: me.id, camera: camera, accent: accent)
        }
        .fullScreenCover(item: $openRoll, onDismiss: loadRolls) { ref in
            RollViewer(camera: camera, accent: accent, opensOnRoll: ref.number)
        }
        .sheet(item: $sharing) { item in
            ActivityView(items: item.items).ignoresSafeArea()
        }
        .onAppear {
            loadRolls()
            // Catch up shared rolls on frames that developed while the app was closed.
            myRolls.forEach(camera.syncShare)
        }
        .task { await account.refresh() }
        .onReceive(account.$headshotVersion.dropFirst()) { _ in
            // A Google or Facebook photo became the headshot.
            profile = Profile.load()
            nameDraft = profile.name
            onChange(profile)
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
                        syncAccount(avatarChanged: true)
                    }
                }
                pickerItem = nil
                working = false
            }
        }
    }

    // MARK: Account and public rolls

    @ViewBuilder private var accountSection: some View {
        if let note {
            Text(note).font(.mono(10, .semibold)).foregroundStyle(accent)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let me = account.me, account.isSignedIn {
            VStack(alignment: .leading, spacing: 8) {
                Text("PUBLIC PROFILE").font(.mono(9, .semibold)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    chip("VIEW MY PROFILE", selected: true) { viewingMine = IncomingUser(id: me.id) }
                    chip(makingCard ? "MAKING CARD…" : "SHARE PROFILE", selected: false) { shareProfile(me) }
                        .disabled(makingCard)
                }
                Text(profile.showOnCards
                     ? "Your name and headshot show on your profile."
                     : "Your name and headshot are hidden, here and on cards. Choose SHOW under ON SHARE CARDS to put them on your profile.")
                    .font(.mono(9)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("YOUR ROLLS").font(.mono(9, .semibold)).foregroundStyle(.secondary)
                if myRolls.isEmpty {
                    Text("Rolls show up here once you've shot a frame.")
                        .font(.mono(10)).foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 14) {
                        ForEach(myRolls, id: \.number) { roll in rollTile(roll) }
                    }
                }
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lock.open.fill").foregroundStyle(accent)
                    Text("Public: on your profile for anyone to see and like.")
                }
                .font(.mono(9)).foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lock.fill")
                    Text("Private: only on this phone. Tap the lock to switch; making a roll private takes it off the server, and links to it stop working.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.mono(9)).foregroundStyle(.secondary)
            }

        }
    }

    /// At the end of the profile: other ways to sign in, and deleting the account.
    @ViewBuilder private var accountFooter: some View {
        if let me = account.me, account.isSignedIn {
            let others = [("apple", true), ("google", SocialSignIn.googleAvailable), ("facebook", SocialSignIn.facebookAvailable)]
                .filter { $0.1 && !me.has($0.0) }.map { $0.0 }
            if !others.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ADD A SIGN-IN").font(.mono(9, .semibold)).foregroundStyle(.secondary)
                    ForEach(others, id: \.self) { provider in
                        if provider == "apple" {
                            AppleSignInButton(onError: { note = $0.uppercased() })
                        } else {
                            ProviderButton(provider: provider, onError: { note = $0.uppercased() })
                        }
                    }
                }
            }

            // Last, on its own: deleting the account (App Review wants it easy to find, not prominent).
            VStack(alignment: .leading, spacing: 8) {
                Divider().overlay(Color(white: 0.2)).padding(.bottom, 4)
                Text("ACCOUNT").font(.mono(9, .semibold)).foregroundStyle(.secondary)
                Button {
                    if confirmDeleteAccount { deleteAccount() } else { confirmDeleteAccount = true }
                } label: {
                    Text(confirmDeleteAccount ? "TAP AGAIN TO DELETE YOUR ACCOUNT" : "DELETE ACCOUNT")
                        .font(.mono(10, .bold))
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Capsule().fill(Color.red.opacity(confirmDeleteAccount ? 0.2 : 0.1)))
                        .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.4))
                }
                .buttonStyle(.plain)
                .disabled(account.working)
                Text("Deletes your profile, your likes and every roll you shared while signed in from the server. Your rolls stay on this phone.")
                    .font(.mono(9)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if confirmDeleteAccount {
                    Button("CANCEL") { confirmDeleteAccount = false }
                        .font(.mono(10, .bold)).foregroundStyle(.white)
                }
            }
        }
    }

    /// Signed out: what an account is for, and the sign-in buttons.
    @ViewBuilder private var signedOutSection: some View {
        if !(account.me != nil && account.isSignedIn) {
            VStack(alignment: .leading, spacing: 8) {
                Text("PUBLIC PROFILE").font(.mono(9, .semibold)).foregroundStyle(.secondary)
                Text("Sign in to put rolls on a public profile people can open from your shares, and to like frames in other people's rolls. Not needed for the camera or for sharing links.")
                    .font(.mono(10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                SignInButtons(onError: { note = $0.uppercased() }, onSignedIn: { note = nil; loadRolls() })
            }
        }
    }

    private func signInsLine(_ me: Account.Me) -> String {
        let names = (me.logins ?? ["apple"]).map { $0 == "google" ? "GOOGLE" : $0 == "facebook" ? "FACEBOOK" : "APPLE" }
        return names.joined(separator: " · ")
    }

    /// Sign-ins whose photo you could switch back to (not the one you're using).
    private var providerPhotos: [String] {
        guard account.isSignedIn, let me = account.me else { return [] }
        return (me.photos ?? []).filter { $0 != me.avatarSource || profile.photo == nil }
    }

    private func useProviderPhoto(_ provider: String) {
        working = true
        Task {
            do {
                try await account.useProviderPhoto(provider)
            } catch {
                note = error.localizedDescription.uppercased()
            }
            working = false
        }
    }

    /// Your account, in the top corner across from your headshot: how you're signed in,
    /// and signing out.
    private func signInCorner(_ me: Account.Me) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text("SIGNED IN WITH").font(.mono(9, .semibold)).foregroundStyle(.secondary)
            HStack(spacing: 5) {
                if me.has("apple") { Image(systemName: "apple.logo").font(.system(size: 12, weight: .semibold)) }
                Text(signInsLine(me)).font(.mono(11, .bold))
            }
            .foregroundStyle(.white)
            chip("SIGN OUT", selected: false) { Task { await account.signOut() } }
        }
    }

    /// A roll on your profile: its cover (tap to see its photos), its name, and a lock:
    /// closed is private, open is public. Tap the lock to switch.
    private func rollTile(_ roll: Roll) -> some View {
        let record = records[roll.number]
        let waiting = record == nil && RollShare.waitsForProfile(roll.number)
        let isPublic = record?.onProfile == true || waiting
        let working = busy[roll.number]
        return VStack(alignment: .leading, spacing: 5) {
            Button { openRoll = RollRef(number: roll.number) } label: {
                thumb(roll)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(roll.title)")
            .overlay(alignment: .topTrailing) {
                Button {
                    if isPublic { makePrivate(roll) } else { makePublic(roll) }
                } label: {
                    Group {
                        if working != nil {
                            ProgressView().controlSize(.mini).tint(.white)
                        } else {
                            Image(systemName: isPublic ? "lock.open.fill" : "lock.fill")
                                .font(.system(size: 12, weight: .bold))
                        }
                    }
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(isPublic ? accent : Color.black.opacity(0.6)))
                    .foregroundStyle(isPublic ? .black : .white)
                    .padding(5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(working != nil)
                .accessibilityLabel(isPublic ? "Public. Make \(roll.title) private" : "Private. Make \(roll.title) public")
            }
            Text(roll.title.uppercased()).font(.mono(10, .bold)).foregroundStyle(.white).lineLimit(1)
            Text(working ?? (waiting ? "PUBLIC WHEN DEVELOPED" : isPublic ? "PUBLIC" : record != nil ? "SHARED BY LINK" : "PRIVATE"))
                .font(.mono(8)).foregroundStyle(isPublic ? accent : .secondary).lineLimit(1)
        }
    }

    private func thumb(_ roll: Roll) -> some View {
        let developed = RollStore.frames(of: roll.number).filter { !RollStore.isPending(roll: roll.number, frame: $0) }
        let first = roll.cover.flatMap { developed.contains($0) ? $0 : nil } ?? developed.first
        let image = first.flatMap { UIImage(contentsOfFile: RollStore.thumbURL(roll: roll.number, frame: $0).path) }
        return Color(white: 0.15)
            .aspectRatio(3 / 4, contentMode: .fit)
            .overlay {
                if let image { Image(uiImage: image).resizable().scaledToFill() }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
    }

    private func loadRolls() {
        // Every roll with frames, including ones still being shot or developing.
        myRolls = RollStore.rolls()
        records = Dictionary(uniqueKeysWithValues: myRolls.compactMap { roll in
            RollShare.record(for: roll.number).map { (roll.number, $0) }
        })
    }

    private func makePublic(_ roll: Roll) {
        guard records[roll.number]?.onProfile != true else { return }
        guard account.me?.termsAccepted == true else {
            withAnimation(.snappy(duration: 0.15)) { askingTerms = roll }
            return
        }
        guard !RollShare.developedFrames(of: roll.number).isEmpty else {
            // Nothing developed yet: it goes on your profile when its first frames do.
            RollShare.setWaitsForProfile(roll.number, true)
            loadRolls()
            return
        }
        busy[roll.number] = "PUTTING ON PROFILE…"
        note = nil
        Task {
            do {
                let record = try await RollShare.makePublic(roll: roll, film: camera.film(ofRoll: roll.number), profile: profile) { done, total in
                    busy[roll.number] = "UPLOADING \(done)/\(total)"
                }
                records[roll.number] = record
            } catch RollShare.ProfileError.terms {
                await account.refresh()
                askingTerms = roll
            } catch {
                note = error.localizedDescription.uppercased()
            }
            busy[roll.number] = nil
        }
    }

    private func makePrivate(_ roll: Roll) {
        if RollShare.waitsForProfile(roll.number) {
            RollShare.setWaitsForProfile(roll.number, false)
            loadRolls()
            return
        }
        guard records[roll.number] != nil else { return }
        busy[roll.number] = "MAKING PRIVATE…"
        note = nil
        Task {
            do {
                try await RollShare.unshare(roll: roll.number)
                records[roll.number] = nil
            } catch {
                note = error.localizedDescription.uppercased()
            }
            busy[roll.number] = nil
        }
    }

    private func deleteAccount() {
        Task {
            do {
                try await account.deleteAccount()
                confirmDeleteAccount = false
                note = "ACCOUNT DELETED"
                loadRolls()
            } catch {
                note = error.localizedDescription.uppercased()
            }
        }
    }

    /// The rules for public rolls (App Review asks for these before people post).
    private func termsCard(_ roll: Roll) -> some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
                .onTapGesture { withAnimation(.snappy(duration: 0.15)) { askingTerms = nil } }
            VStack(alignment: .leading, spacing: 12) {
                Text("BEFORE YOU GO PUBLIC").font(.mono(15, .bold)).foregroundStyle(accent)
                Text("""
                    Public rolls can be seen, liked and reported by anyone.

                    There's no place here for nudity or sexual content, violence, hate, harassment, spam, or photos of people who didn't agree to be shared. Reported rolls are hidden and reviewed, and accounts that break these rules are removed.

                    Only post photos you took. The full terms are at filmexposures.com/terms.
                    """)
                    .font(.mono(10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    askingTerms = nil
                    Task {
                        do {
                            try await account.acceptTerms()
                            makePublic(roll)
                        } catch {
                            note = error.localizedDescription.uppercased()
                        }
                    }
                } label: {
                    Text("I AGREE · MAKE IT PUBLIC")
                        .font(.mono(11, .bold)).frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(Capsule().fill(accent.opacity(0.18)))
                        .overlay(Capsule().stroke(accent, lineWidth: 1))
                        .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
                Button { withAnimation(.snappy(duration: 0.15)) { askingTerms = nil } } label: {
                    Text("CANCEL").font(.mono(11, .bold)).frame(maxWidth: .infinity).padding(.vertical, 11)
                        .foregroundStyle(Color(white: 0.55))
                }
                .buttonStyle(.plain)
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.11)))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(white: 0.2), lineWidth: 1))
            .padding(.horizontal, 22)
        }
        .transition(.opacity)
    }

    // MARK: Settings

    private func save() {
        let name = Profile.cleanName(nameDraft)
        guard name != profile.name else { return }
        profile.name = name
        profile.saveSettings()
        onChange(profile)
        syncAccount(avatarChanged: false)
    }

    private func setPhotoCards(_ on: Bool) {
        profile.filmCardsUsePhoto = on
        profile.saveSettings()
        onChange(profile)
    }

    private func setShow(_ show: Bool) {
        profile.showOnCards = show
        profile.saveSettings()
        onChange(profile)
        syncAccount(avatarChanged: show)
    }

    /// Keep the public profile's name and headshot in step with this one.
    private func syncAccount(avatarChanged: Bool) {
        guard account.isSignedIn else { return }
        let current = profile
        Task { await account.syncProfile(current, avatarChanged: avatarChanged) }
    }

    /// Share your public profile as a card (latest roll covers, headshot, name, counts) with
    /// its link. Just the link if the profile can't be fetched.
    private func shareProfile(_ me: Account.Me) {
        makingCard = true
        Task {
            var card: UIImage?
            if let remote = try? await RollShare.fetchProfile(id: me.id) {
                card = await ProfileCard.make(for: remote)
            }
            makingCard = false
            sharing = ShareItems(items: [card as Any?, me.url].compactMap { $0 })
        }
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

/// A roll to open from your profile.
private struct RollRef: Identifiable {
    let number: Int
    var id: Int { number }
}
