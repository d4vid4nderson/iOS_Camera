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
    @State private var socialTab: SocialTabRef?
    @State private var pickingPeople: RollRef?
    @State private var follows: (followers: Int, following: Int)?
    @State private var listing: ProfileListRef?
    /// Picking a handle and photo after signing in (stays up until you finish the photo step).
    @State private var settingUp = false
    /// The EDIT PROFILE sheet: photo, name, username, card options and the account.
    @State private var editing = false
    /// The audience a roll was going to get when the rules had to be agreed to first.
    @State private var pendingAudience: (Audience, [String]) = (.everyone, [])

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Profile").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    Spacer()
                    Button("Done") { save(); dismiss() }.font(.system(size: 16, weight: .semibold)).foregroundStyle(accent)
                }

                if needsSignIn {
                    signInFirst
                } else if needsSetup || settingUp {
                    AccountSetup(accent: accent, onStart: { settingUp = true }, onRefused: { settingUp = false }) {
                        settingUp = false
                        profile = Profile.load()
                        nameDraft = profile.name
                        onChange(profile)
                        loadRolls()
                    }
                } else {
                    profileHeader
                    if ShareLinks.isConfigured {
                        accountSection
                    } else {
                        // No share server: the profile is only the name and photo on cards.
                        editFields
                    }
                }

                // The website's policies and support form (App Review asks for these in the app).
                HStack(spacing: 16) {
                    Link("Privacy", destination: URL(string: "https://filmexposures.com/privacy")!)
                    Link("Terms", destination: URL(string: "https://filmexposures.com/terms")!)
                    Link("Support", destination: URL(string: "https://filmexposures.com/support")!)
                }
                .font(.system(size: 13, weight: .medium))
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
            ShareSheetView(item: item)
        }
        .sheet(isPresented: $editing, onDismiss: save) { editProfile }
        .fullScreenCover(item: $socialTab) { ref in
            SocialView(camera: camera, accent: accent, tab: ref.tab)
        }
        .sheet(item: $listing, onDismiss: { follows = nil; Task { await refreshFollows() } }) { ref in
            PeopleListSheet(userID: ref.user, which: ref.which, camera: camera, accent: accent)
        }
        .sheet(item: $pickingPeople) { ref in
            PeoplePicker(accent: accent, initial: records[ref.number]?.people ?? []) { people in
                if let roll = myRolls.first(where: { $0.number == ref.number }) { apply(.people, people: people, to: roll) }
            }
        }
        .onAppear {
            loadRolls()
            // Catch up shared rolls on frames that developed while the app was closed.
            myRolls.forEach(camera.syncShare)
        }
        .task { await account.refresh() }
        .onChange(of: account.me?.id) { _, id in if id == nil { settingUp = false } }
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

    // MARK: Profile header and EDIT PROFILE

    /// Who you are, at a glance: headshot, name, @username, and the way into editing them.
    private var profileHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            ProfileAvatar(photo: profile.photo, size: 88)
                .overlay { if working { ProgressView() } }
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name.isEmpty ? "Add your name" : profile.name)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(profile.name.isEmpty ? Color(white: 0.5) : .white)
                    .lineLimit(1).minimumScaleFactor(0.7)
                if let username = account.me?.handle, account.isSignedIn {
                    Text("@\(username)").font(.mono(13, .bold)).foregroundStyle(accent).lineLimit(1)
                }
                Button { editing = true } label: {
                    Text("Edit profile").font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Capsule().fill(Color(white: 0.17)))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
    }

    /// EDIT PROFILE: everything you change about yourself, in one place.
    private var editProfile: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text("Edit profile").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    Spacer()
                    Button("Done") { save(); editing = false }.font(.system(size: 16, weight: .semibold)).foregroundStyle(accent)
                }
                editFields
                if ShareLinks.isConfigured, let me = account.me, account.isSignedIn {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Signed in with").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            HStack(spacing: 5) {
                                if me.has("apple") { Image(systemName: "apple.logo").font(.system(size: 12, weight: .semibold)) }
                                Text(signInsLine(me)).font(.mono(11, .bold))
                            }
                            .foregroundStyle(.white)
                            Spacer()
                            chip("SIGN OUT", selected: false) { editing = false; Task { await account.signOut() } }
                        }
                    }
                    accountFooter
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .presentationDetents([.large])
        .presentationBackground(Color(white: 0.09))
        .preferredColorScheme(.dark)
    }

    /// The fields EDIT PROFILE changes: photo, name, @username (and search), and what cards show.
    @ViewBuilder private var editFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Photo").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            HStack(alignment: .center, spacing: 16) {
                ProfileAvatar(photo: profile.photo, size: 72)
                    .overlay { if working { ProgressView() } }
                VStack(alignment: .leading, spacing: 6) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        chipText(profile.photo == nil ? "CHOOSE PHOTO" : "CHANGE PHOTO", selected: true)
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
        }

        VStack(alignment: .leading, spacing: 6) {
            Text("Name").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            TextField("", text: $nameDraft,
                      prompt: Text("Your name").foregroundStyle(Color(white: 0.4)))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(save)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(Capsule().fill(Color(white: 0.16)))
                .onChange(of: nameDraft) { _, new in
                    if new.count > Profile.maxNameLength { nameDraft = String(new.prefix(Profile.maxNameLength)) }
                }
        }

        if ShareLinks.isConfigured, account.isSignedIn {
            HandleEditor(accent: accent)
        }

        VStack(alignment: .leading, spacing: 6) {
            Text("Name and photo on cards").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                chip("SHOW", selected: profile.showOnCards) { setShow(true) }
                chip("HIDE", selected: !profile.showOnCards) { setShow(false) }
            }
            Text("Shown on your profile and on the cards you share.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        VStack(alignment: .leading, spacing: 6) {
            Text("Film cards show").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                chip("MY LATEST FRAME", selected: profile.filmCardsUsePhoto) { setPhotoCards(true) }
                chip("TONE SCALE", selected: !profile.filmCardsUsePhoto) { setPhotoCards(false) }
            }
            Text("A frame you shot on the film, or its tone scale.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        if let note {
            Text(note).font(.mono(10, .semibold)).foregroundStyle(accent)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Account and public rolls

    @ViewBuilder private var accountSection: some View {
        if let note {
            Text(note).font(.system(size: 13, weight: .semibold)).foregroundStyle(accent)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let me = account.me, account.isSignedIn {
            // Your numbers: rolls you could share, whom you follow and who follows you.
            HStack(spacing: 8) {
                stat(shareableRolls, shareableRolls == 1 ? "Roll" : "Rolls")
                Button { listing = ProfileListRef(which: "following", user: me.id) } label: {
                    stat(follows?.following, "Following")
                }
                .buttonStyle(.plain)
                Button { listing = ProfileListRef(which: "followers", user: me.id) } label: {
                    stat(follows?.followers, "Followers")
                }
                .buttonStyle(.plain)
            }
            .task(id: me.id) {
                if let mine = try? await RollShare.fetchProfile(id: me.id) {
                    follows = (mine.followers ?? 0, mine.following ?? 0)
                }
            }

            HStack(spacing: 10) {
                bigButton("View profile", filled: true) { viewingMine = IncomingUser(id: me.id) }
                bigButton(makingCard ? "Making card…" : "Share profile", filled: false) { shareProfile(me) }
                    .disabled(makingCard)
            }
            if !profile.showOnCards {
                Text("Your name and photo are hidden. Turn them on in Edit profile.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // People: a short list, each row one place to go.
            VStack(alignment: .leading, spacing: 0) {
                sectionTitle("People")
                VStack(spacing: 0) {
                    peopleRow("person.2", "Following", tab: .feed)
                    peopleRow("square.grid.2x2", "Browse rolls", tab: .browse)
                    peopleRow("tray", "Shared with you", tab: .shared)
                    peopleRow("person.badge.clock", "Requests", tab: .requests)
                    peopleRow("magnifyingglass", "Find people", tab: .find, last: true)
                }
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.13)))
            }

            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Your rolls")
                if myRolls.isEmpty {
                    Text("Your rolls show up here once you've shot a frame.")
                        .font(.system(size: 14)).foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 14) {
                        ForEach(myRolls, id: \.number) { roll in rollTile(roll) }
                    }
                    Text("Tap the badge on a roll to choose who sees it.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
            .padding(.bottom, 8)
    }

    /// One row in the People list: an icon, a label and a chevron.
    private func peopleRow(_ icon: String, _ label: String, tab: SocialView.Tab, last: Bool = false) -> some View {
        Button { socialTab = SocialTabRef(tab: tab) } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 16, weight: .medium)).foregroundStyle(accent)
                    .frame(width: 24)
                Text(label).font(.system(size: 16)).foregroundStyle(.white)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(white: 0.4))
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if !last { Rectangle().fill(Color(white: 0.2)).frame(height: 0.5).padding(.leading, 50) }
            }
        }
        .buttonStyle(.plain)
    }

    /// A full-width rounded button: filled orange, or a quiet grey.
    private func bigButton(_ text: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(Capsule().fill(filled ? accent : Color(white: 0.17)))
                .foregroundStyle(filled ? .black : .white)
        }
        .buttonStyle(.plain)
    }

    /// At the end of the profile: other ways to sign in, and deleting the account.
    @ViewBuilder private var accountFooter: some View {
        if let me = account.me, account.isSignedIn {
            let others = [("apple", true), ("google", SocialSignIn.googleAvailable), ("facebook", SocialSignIn.facebookAvailable)]
                .filter { $0.1 && !me.has($0.0) }.map { $0.0 }
            if !others.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add a sign-in").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
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
                Text("Account").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
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
                Text("Deletes your profile, likes and shared rolls from the server. Your rolls stay on this phone.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if confirmDeleteAccount {
                    Button("CANCEL") { confirmDeleteAccount = false }
                        .font(.mono(10, .bold)).foregroundStyle(.white)
                }
            }
        }
    }

    /// Rolls with developed frames: the ones you could share now.
    private var shareableRolls: Int {
        myRolls.filter { !RollShare.developedFrames(of: $0.number).isEmpty }.count
    }

    private func stat(_ value: Int?, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value.map(String.init) ?? "–").font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.13)))
        .accessibilityElement(children: .combine)
    }

    private func refreshFollows() async {
        guard let id = account.me?.id, let mine = try? await RollShare.fetchProfile(id: id) else { return }
        follows = (mine.followers ?? 0, mine.following ?? 0)
    }

    /// Signed in without a confirmed age or a handle yet: those (and a photo) come before the rest of the profile.
    private var needsSetup: Bool {
        ShareLinks.isConfigured && account.isSignedIn && account.needsSetup
    }

    /// Your name and photo belong to an account, so signed out there's only signing in.
    private var needsSignIn: Bool {
        ShareLinks.isConfigured && !(account.me != nil && account.isSignedIn)
    }

    /// Signed out: what an account is for, and the sign-in buttons. Name and photo come after.
    private var signInFirst: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProfileAvatar(photo: nil, size: 72)
            Text("SIGN IN TO MAKE YOUR PROFILE").font(.mono(15, .bold)).foregroundStyle(accent)
            Text("Your name and photo go with your account. Sign in to set them, share rolls with friends or followers, follow photographers and like their frames.")
                .font(.mono(10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let note {
                Text(note).font(.mono(10, .semibold)).foregroundStyle(accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SignInButtons(onError: { note = $0.uppercased() }, onSignedIn: {
                note = nil
                profile = Profile.load()
                nameDraft = profile.name
                onChange(profile)
                loadRolls()
            })
            Text("The camera, your rolls and sharing a roll as a link all work without an account.")
                .font(.mono(9)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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

    /// A roll on your profile: its cover (tap to see its photos), its name, and a lock:
    /// closed is private, open is public. Tap the lock to switch.
    private func rollTile(_ roll: Roll) -> some View {
        let record = records[roll.number]
        let waiting = record == nil && RollShare.waitsForProfile(roll.number)
        let audience: Audience = waiting ? .everyone : record?.shownAudience ?? .onlyMe
        let isPublic = audience.isShared
        let working = busy[roll.number]
        return VStack(alignment: .leading, spacing: 5) {
            Button { openRoll = RollRef(number: roll.number) } label: {
                thumb(roll)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(roll.title)")
            .overlay(alignment: .topTrailing) {
                Menu {
                    ForEach(Audience.choices) { choice in
                        Button {
                            choose(choice, for: roll)
                        } label: {
                            Label(choice == .people && audience == .people ? "SPECIFIC PEOPLE (EDIT)" : choice.label,
                                  systemImage: choice == audience ? "checkmark" : choice.icon)
                        }
                    }
                } label: {
                    Group {
                        if working != nil {
                            ProgressView().controlSize(.mini).tint(.white)
                        } else {
                            Image(systemName: audience.icon)
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
                .accessibilityLabel("\(audience.label.capitalized). Choose who sees \(roll.title)")
            }
            Text(roll.title.uppercased()).font(.mono(10, .bold)).foregroundStyle(.white).lineLimit(1)
            Text(working ?? (waiting ? "PUBLIC WHEN DEVELOPED" : audience == .link ? "SHARED BY LINK" : audience.label))
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

    /// A choice from a roll's audience menu.
    private func choose(_ audience: Audience, for roll: Roll) {
        switch audience {
        case .onlyMe: makePrivate(roll)
        case .people: pickingPeople = RollRef(number: roll.number)
        default: apply(audience, to: roll)
        }
    }

    private func makePublic(_ roll: Roll) { apply(.everyone, to: roll) }

    /// Share a roll with an audience: uploads it if needed. Public, followers and specific
    /// people need the rules agreed to first.
    private func apply(_ audience: Audience, people: [String] = [], to roll: Roll) {
        let current = records[roll.number]
        if current?.shownAudience == audience && (audience != .people || Set(current?.people ?? []) == Set(people)) { return }
        guard !audience.isShared || account.me?.termsAccepted == true else {
            pendingAudience = (audience, people)
            withAnimation(.snappy(duration: 0.15)) { askingTerms = roll }
            return
        }
        guard !RollShare.developedFrames(of: roll.number).isEmpty else {
            if audience == .everyone {
                // Nothing developed yet: it goes on your profile when its first frames do.
                RollShare.setWaitsForProfile(roll.number, true)
                loadRolls()
            } else {
                note = "DEVELOP A FRAME FIRST, THEN SHARE THE ROLL"
            }
            return
        }
        busy[roll.number] = audience == .people ? "SHARING…" : "PUTTING ON PROFILE…"
        note = nil
        Task {
            do {
                let record = try await RollShare.setAudience(audience, people: people, roll: roll,
                                                             film: camera.film(ofRoll: roll.number), profile: profile) { done, total in
                    busy[roll.number] = "UPLOADING \(done)/\(total)"
                }
                records[roll.number] = record
                Task.detached { await RollShare.uploadProfilePreview() }
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
                Task.detached { await RollShare.uploadProfilePreview() }
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
                Text(pendingAudience.0 == .everyone ? "BEFORE YOU GO PUBLIC" : "BEFORE YOU SHARE").font(.mono(15, .bold)).foregroundStyle(accent)
                Text("""
                    Shared rolls can be seen, liked and reported by the people you share them with. Public rolls, by anyone.

                    There's no place here for nudity or sexual content, violence, hate, harassment, spam, or photos of people who didn't agree to be shared. Reported rolls are hidden and reviewed, and accounts that break these rules are removed.

                    Film Exposures is for people 13 and older. Only post photos you took. The full terms are at filmexposures.com/terms.
                    """)
                    .font(.mono(10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    askingTerms = nil
                    Task {
                        do {
                            try await account.acceptTerms()
                            apply(pendingAudience.0, people: pendingAudience.1, to: roll)
                        } catch {
                            note = error.localizedDescription.uppercased()
                        }
                    }
                } label: {
                    Text(pendingAudience.0 == .everyone ? "I AGREE · MAKE IT PUBLIC" : "I AGREE · SHARE IT")
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
            var content: ProfileCard.Content?
            if let remote = try? await RollShare.fetchProfile(id: me.id) {
                content = await ProfileCard.content(for: remote)
            }
            // So the link you're about to send shows a fresh preview.
            await RollShare.uploadProfilePreview()
            makingCard = false
            sharing = ShareItems(items: [me.url], activities: SendInAppActivity.forProfile(me.id),
                                 card: content.map { c in CardShare(link: me.url) { ProfileCard.render(c, style: $0) } })
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
private struct ProfileListRef: Identifiable {
    let which: String
    let user: String
    var id: String { which }
}

private struct SocialTabRef: Identifiable {
    let tab: SocialView.Tab
    var id: String { tab.rawValue }
}

private struct RollRef: Identifiable {
    let number: Int
    var id: Int { number }
}
