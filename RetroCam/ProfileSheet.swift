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
        .presentationBackground(ProfileStyle.background)
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
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("Edit profile").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    Spacer()
                    Button("Done") { save(); editing = false }.font(.system(size: 16, weight: .semibold)).foregroundStyle(accent)
                }
                editFields
                if ShareLinks.isConfigured, let me = account.me, account.isSignedIn {
                    accountCard(me)
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .presentationDetents([.large])
        .presentationBackground(ProfileStyle.background)
        .preferredColorScheme(.dark)
    }

    /// The fields EDIT PROFILE changes: photo, name, @username, who can find you, and what cards show.
    @ViewBuilder private var editFields: some View {
        VStack(spacing: 14) {
            ProfileAvatar(photo: profile.photo, size: 104)
                .overlay { if working { ProgressView() } }
            HStack(spacing: 8) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    PillLabel(text: profile.photo == nil ? "Choose photo" : "Change photo", filled: true,
                              accent: accent, compact: true, fullWidth: false)
                }
                .buttonStyle(.plain)
                if profile.photo != nil {
                    PillButton(text: "Remove", accent: accent, compact: true, fullWidth: false) {
                        Profile.removeHeadshot()
                        profile.photo = nil
                        onChange(profile)
                        syncAccount(avatarChanged: true)
                    }
                }
            }
            ForEach(providerPhotos, id: \.self) { provider in
                PillButton(text: "Use my \(provider.capitalized) photo", accent: accent, compact: true, fullWidth: false) {
                    useProviderPhoto(provider)
                }
            }
        }
        .frame(maxWidth: .infinity)

        VStack(alignment: .leading, spacing: 8) {
            FieldLabel("Name")
            ProfileField(prompt: "Your name", text: $nameDraft, capitalization: .words, onSubmit: save)
                .onChange(of: nameDraft) { _, new in
                    if new.count > Profile.maxNameLength { nameDraft = String(new.prefix(Profile.maxNameLength)) }
                }
        }

        if ShareLinks.isConfigured, account.isSignedIn {
            UsernameEditor(accent: accent)
        }

        VStack(alignment: .leading, spacing: 8) {
            FieldLabel("Privacy")
            SettingsCard {
                if ShareLinks.isConfigured, account.isSignedIn {
                    ToggleRow(title: "Find me in search",
                              detail: "People find you by your @username or name. Every follow is a request you approve.",
                              isOn: discoverable, accent: accent)
                    CardDivider()
                }
                ToggleRow(title: "Name and photo on cards",
                          detail: "Shown on your profile and on the cards you share.",
                          isOn: Binding(get: { profile.showOnCards }, set: { setShow($0) }), accent: accent)
            }
        }

        VStack(alignment: .leading, spacing: 8) {
            FieldLabel("Film cards show")
            SettingsCard {
                NavRow(title: "My latest frame", checked: profile.filmCardsUsePhoto, accent: accent) { setPhotoCards(true) }
                CardDivider()
                NavRow(title: "Tone scale", checked: !profile.filmCardsUsePhoto, accent: accent) { setPhotoCards(false) }
            }
            FootnoteText("A frame you shot on that film, or the film's tone scale.")
        }

        if let note { NoteText(text: note, accent: accent) }
    }

    /// Whether search finds you: the switch shows the account's setting.
    private var discoverable: Binding<Bool> {
        Binding(get: { account.me?.discoverable != false }, set: { on in
            Task {
                do { try await account.updateSocial(discoverable: on) } catch { note = error.localizedDescription }
            }
        })
    }

    /// The end of EDIT PROFILE: how you sign in, signing out, other sign-ins, and deleting
    /// the account (App Review wants it easy to find, not prominent).
    private func accountCard(_ me: Account.Me) -> some View {
        let others = [("apple", true), ("google", SocialSignIn.googleAvailable), ("facebook", SocialSignIn.facebookAvailable)]
            .filter { $0.1 && !me.has($0.0) }.map { $0.0 }
        return VStack(alignment: .leading, spacing: 8) {
            FieldLabel("Account")
            SettingsCard {
                HStack(spacing: 6) {
                    Text("Signed in with").font(.system(size: 16)).foregroundStyle(.white)
                    Spacer(minLength: 8)
                    if me.has("apple") { Image(systemName: "apple.logo").font(.system(size: 14, weight: .semibold)).foregroundStyle(.secondary) }
                    Text(signInsLine(me)).font(.system(size: 15)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 13)
                CardDivider()
                actionRow("Sign out") { editing = false; Task { await account.signOut() } }
                CardDivider()
                actionRow(confirmDeleteAccount ? "Tap again to delete your account" : "Delete account",
                          tint: ProfileStyle.destructive) {
                    if confirmDeleteAccount { deleteAccount() } else { confirmDeleteAccount = true }
                }
                .disabled(account.working)
                if confirmDeleteAccount {
                    CardDivider()
                    actionRow("Cancel") { confirmDeleteAccount = false }
                }
            }
            FootnoteText("Deleting your account removes your profile, likes and shared rolls from the server. Your rolls stay on this phone.")

            if !others.isEmpty {
                FieldLabel("Add a sign-in").padding(.top, 14)
                ForEach(others, id: \.self) { provider in
                    if provider == "apple" {
                        AppleSignInButton(onError: { note = $0 })
                    } else {
                        ProviderButton(provider: provider, onError: { note = $0 })
                    }
                }
            }
        }
    }

    /// A row in a card that does something when tapped (no chevron).
    private func actionRow(_ title: String, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 16)).foregroundStyle(tint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 13)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        VStack(alignment: .leading, spacing: 14) {
            ProfileAvatar(photo: nil, size: 88)
            Text("Sign in to make your profile").font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
            Text("Your name and photo go with your account. Sign in to share rolls with friends or followers, follow photographers and like their frames.")
                .font(.system(size: 15)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let note { NoteText(text: note, accent: accent) }
            SignInButtons(onError: { note = $0 }, onSignedIn: {
                note = nil
                profile = Profile.load()
                nameDraft = profile.name
                onChange(profile)
                loadRolls()
            })
            FootnoteText("The camera, your rolls and sharing a roll as a link all work without an account.")
        }
    }

    private func signInsLine(_ me: Account.Me) -> String {
        let names = (me.logins ?? ["apple"]).map { $0 == "google" ? "Google" : $0 == "facebook" ? "Facebook" : "Apple" }
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
                note = error.localizedDescription
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
                            Label(choice == .people && audience == .people ? "Specific people (edit)" : choice.title,
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
                .accessibilityLabel("\(audience.title). Choose who sees \(roll.title)")
            }
            Text(roll.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            Text(working ?? (waiting ? "Public when developed" : audience == .link ? "Shared by link" : audience.title))
                .font(.system(size: 12)).foregroundStyle(isPublic ? accent : .secondary).lineLimit(1)
        }
    }

    private func thumb(_ roll: Roll) -> some View {
        let developed = RollStore.frames(of: roll.number).filter { !RollStore.isPending(roll: roll.number, frame: $0) }
        let first = roll.cover.flatMap { developed.contains($0) ? $0 : nil } ?? developed.first
        let image = first.flatMap { UIImage(contentsOfFile: RollStore.thumbURL(roll: roll.number, frame: $0).path) }
        return PrintCell(aspect: 4 / 5, cornerRadius: 6) {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
        }
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
                note = "Develop a frame first, then share the roll."
            }
            return
        }
        busy[roll.number] = audience == .people ? "Sharing…" : "Putting on profile…"
        note = nil
        Task {
            do {
                let record = try await RollShare.setAudience(audience, people: people, roll: roll,
                                                             film: camera.film(ofRoll: roll.number), profile: profile) { done, total in
                    busy[roll.number] = "Uploading \(done)/\(total)"
                }
                records[roll.number] = record
                Task.detached { await RollShare.uploadProfilePreview() }
            } catch RollShare.ProfileError.terms {
                await account.refresh()
                askingTerms = roll
            } catch {
                note = error.localizedDescription
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
        busy[roll.number] = "Making private…"
        note = nil
        Task {
            do {
                try await RollShare.unshare(roll: roll.number)
                records[roll.number] = nil
                Task.detached { await RollShare.uploadProfilePreview() }
            } catch {
                note = error.localizedDescription
            }
            busy[roll.number] = nil
        }
    }

    private func deleteAccount() {
        Task {
            do {
                try await account.deleteAccount()
                confirmDeleteAccount = false
                note = "Account deleted."
                loadRolls()
            } catch {
                note = error.localizedDescription
            }
        }
    }

    /// The rules for public rolls (App Review asks for these before people post).
    private func termsCard(_ roll: Roll) -> some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
                .onTapGesture { withAnimation(.snappy(duration: 0.15)) { askingTerms = nil } }
            VStack(alignment: .leading, spacing: 14) {
                Text(pendingAudience.0 == .everyone ? "Before you go public" : "Before you share")
                    .font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                Text("""
                    Shared rolls can be seen, liked and reported by the people you share them with. Public rolls, by anyone.

                    There's no place here for nudity or sexual content, violence, hate, harassment, spam, or photos of people who didn't agree to be shared. Reported rolls are hidden and reviewed, and accounts that break these rules are removed.

                    Film Exposures is for people 13 and older. Only post photos you took. The full terms are at filmexposures.com/terms.
                    """)
                    .font(.system(size: 14)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                PillButton(text: pendingAudience.0 == .everyone ? "Agree and make it public" : "Agree and share",
                           filled: true, accent: accent) {
                    askingTerms = nil
                    Task {
                        do {
                            try await account.acceptTerms()
                            apply(pendingAudience.0, people: pendingAudience.1, to: roll)
                        } catch {
                            note = error.localizedDescription
                        }
                    }
                }
                PillButton(text: "Cancel", accent: accent) { withAnimation(.snappy(duration: 0.15)) { askingTerms = nil } }
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 20).fill(ProfileStyle.card))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(ProfileStyle.divider, lineWidth: 1))
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
            sharing = ShareItems(items: [ShareCaption.text(.profile, link: me.url)], activities: SendInAppActivity.forProfile(me.id),
                                 card: content.map { c in CardShare(link: me.url, kind: .profile) { ProfileCard.render(c, style: $0) } })
        }
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

/// Your @username in EDIT PROFILE: letters, numbers, _ and . (3 to 20), saved with SAVE.
/// It's your link too: filmexposures.com/@username.
private struct UsernameEditor: View {
    let accent: Color
    @ObservedObject private var account = Account.shared
    @State private var draft = ""
    @State private var note: String?
    @State private var saving = false

    private var changed: Bool { !draft.isEmpty && draft != (account.me?.handle ?? "") }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel("Username")
            HStack(spacing: 8) {
                ProfileField(prefix: "@", prompt: "yourname", text: $draft, onSubmit: save)
                    .onChange(of: draft) { _, new in
                        let cleaned = String(new.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }.prefix(20))
                        if cleaned != new { draft = cleaned }
                        if note != nil { note = nil }
                    }
                if changed {
                    PillButton(text: saving ? "Saving…" : "Save", filled: true, accent: accent, compact: true, fullWidth: false, action: save)
                        .disabled(saving || draft.count < 3)
                        .opacity(draft.count < 3 ? 0.5 : 1)
                }
            }
            if let note {
                NoteText(text: note, accent: accent)
            } else {
                FootnoteText("Your link: filmexposures.com/@\(draft.isEmpty ? "yourname" : draft)")
            }
        }
        .onAppear { draft = account.me?.handle ?? "" }
        .onChange(of: account.me?.handle) { _, handle in draft = handle ?? draft }
    }

    private func save() {
        guard changed, draft.count >= 3, !saving else { return }
        saving = true
        note = nil
        Task {
            do {
                try await account.updateSocial(handle: draft)
                note = "Saved."
            } catch {
                note = error.localizedDescription
            }
            saving = false
        }
    }
}
