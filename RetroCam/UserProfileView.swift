import SwiftUI

/// Someone's profile: their headshot, name and public rolls. Tap a roll to look through it
/// (and like its frames). Opened from a roll's sharer, a profile link, or your own profile.
struct UserProfileView: View {
    /// An account id, or "@handle" from a handle link (filmexposures.com/@handle).
    let userID: String
    @ObservedObject var camera: CameraModel
    let accent: Color
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var account = Account.shared

    @State private var profile: RollShare.RemoteProfile?
    /// The account id once known (a handle link is looked up when the profile loads).
    private var uid: String { profile?.id ?? userID }
    @State private var failure: String?
    @State private var opening: OpenRoll?
    @State private var sharing: ShareItems?
    @State private var confirmingBlock = false
    @State private var confirmingUnfollow = false
    @State private var askingToSignIn = false
    @State private var reporting = false
    @State private var makingCard = false
    @State private var followStatus = "none"
    @State private var listing: PeopleListRef?
    @State private var note: String?
    @State private var scrollToRolls = 0

    private var isMe: Bool { account.me?.id == uid }

    var body: some View {
        ZStack {
            ProfileStyle.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                header
                if RollShare.isBlocked(uid) {
                    VStack(spacing: 16) {
                        Spacer()
                        EmptyState(icon: "hand.raised", title: "You blocked this person",
                                   detail: "Unblock them to see their profile again. Following doesn't come back on its own.")
                        PillButton(text: "Unblock", accent: accent, fullWidth: false) { unblock() }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else if let profile {
                    if profile.rolls.isEmpty {
                        if isMe {
                            centered("photo.stack", "No shared rolls yet", "Choose who sees a roll from your profile.")
                        } else if followStatus == "following" {
                            centered("photo.stack", "No rolls to show yet")
                        } else {
                            centered("photo.stack", "No public rolls yet", "Follow to see the rolls they share with followers.")
                        }
                    } else {
                        grid(profile)
                    }
                } else if let failure {
                    centered("exclamationmark.triangle", "Couldn't load this profile", failure)
                } else {
                    Spacer()
                    ProgressView().frame(maxWidth: .infinity)
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if confirmingBlock { blockCard }
            if confirmingUnfollow { unfollowCard }
            if askingToSignIn { signInCard }
            if reporting { reportCard }
        }
        .preferredColorScheme(.dark)
        .task { await load() }
        .fullScreenCover(item: $opening) { roll in
            SharedRollView(rollID: roll.id, camera: camera, accent: accent)
        }
        .sheet(item: $sharing) { item in
            ShareSheetView(item: item)
        }
        .sheet(item: $listing) { ref in
            PeopleListSheet(userID: uid, which: ref.which, camera: camera, accent: accent)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Text(isMe ? "Your profile" : "Profile").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                if let profile, !isMe {
                    moreMenu(profile)
                }
                CloseCircle { dismiss() }
            }
            HStack(spacing: 16) {
                avatar
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile?.name.flatMap { $0.isEmpty ? nil : $0 } ?? (profile == nil ? " " : "Film Exposures photographer"))
                        .font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    if let handle = profile?.handle {
                        Text("@\(handle)").font(.system(size: 15, weight: .semibold)).foregroundStyle(accent).lineLimit(1)
                    }
                    if let profile, profile.relation?.followsYou == true, !isMe {
                        Text("Follows you").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            if let profile {
                stats(profile)
                HStack(spacing: 10) {
                    if !isMe && account.isSignedIn && profile.relation != nil {
                        FollowButton(id: uid, status: $followStatus, accent: accent, onError: { note = $0 }, big: true,
                                     confirmUnfollow: { withAnimation(.snappy(duration: 0.15)) { confirmingUnfollow = true } })
                    } else if !isMe && !account.isSignedIn {
                        PillButton(text: "Sign in to follow", filled: true, accent: accent) {
                            withAnimation(.snappy(duration: 0.15)) { askingToSignIn = true }
                        }
                    }
                    if profile.relation?.askedYou == true && !isMe {
                        PillButton(text: "Approve", filled: true, accent: accent) { approve() }
                    }
                    PillButton(text: makingCard ? "Making card…" : "Share profile", filled: isMe, accent: accent) {
                        shareProfile(profile)
                    }
                    .disabled(makingCard)
                }
                if let note {
                    NoteText(text: note, accent: accent)
                }
            }
        }
    }

    /// Report and Block, tucked behind "…" so the profile isn't a row of buttons.
    private func moreMenu(_ profile: RollShare.RemoteProfile) -> some View {
        Menu {
            if account.isSignedIn {
                Button { withAnimation(.snappy(duration: 0.15)) { reporting = true } } label: {
                    Label("Report", systemImage: "flag")
                }
            }
            Button(role: .destructive) { withAnimation(.snappy(duration: 0.15)) { confirmingBlock = true } } label: {
                Label("Block", systemImage: "hand.raised")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .bold))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color(white: 0.16)))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More: report or block")
    }

    private func approve() {
        Task {
            do {
                try await Social.answer(uid, accept: true)
                await load()
            } catch {
                note = error.localizedDescription
            }
        }
    }

    @ViewBuilder private var avatar: some View {
        if let url = profile?.avatar {
            AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color(white: 0.18) }
                .frame(width: 88, height: 88)
                .clipShape(Circle())
        } else {
            ProfileAvatar(photo: nil, size: 88)
        }
    }

    /// Rolls, frames, followers, following: big numbers you can tap. Rolls and frames go to
    /// the rolls (your own: back to your profile, where you choose who sees them); followers
    /// and following open the lists.
    private func stats(_ profile: RollShare.RemoteProfile) -> some View {
        HStack(spacing: 8) {
            stat(profile.rolls.count, profile.rolls.count == 1 ? "Roll" : "Rolls") { showRolls() }
            stat(frameCount(profile), frameCount(profile) == 1 ? "Frame" : "Frames") { showRolls() }
            stat(profile.followers, "Followers") { if account.isSignedIn { listing = PeopleListRef(which: "followers") } }
            stat(profile.following, "Following") { if account.isSignedIn { listing = PeopleListRef(which: "following") } }
        }
    }

    private func stat(_ value: Int?, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(value.map(String.init) ?? "–")
                    .font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text(label).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(ProfileStyle.card))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(value ?? 0) \(label.lowercased())")
    }

    private func showRolls() {
        if isMe { dismiss() } else { withAnimation { scrollToRolls += 1 } }
    }

    private func frameCount(_ profile: RollShare.RemoteProfile) -> Int {
        profile.rolls.reduce(0) { $0 + $1.frames }
    }

    private func centered(_ icon: String, _ title: String, _ detail: String? = nil) -> some View {
        VStack {
            Spacer()
            EmptyState(icon: icon, title: title, detail: detail)
            Spacer()
        }
    }

    // MARK: Rolls

    private func grid(_ profile: RollShare.RemoteProfile) -> some View {
        ScrollViewReader { reader in
        ScrollView {
            Color.clear.frame(height: 0).id("rolls-top")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 16) {
                ForEach(profile.rolls) { roll in
                    Button { opening = OpenRoll(id: roll.id) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            // The whole cover print, any format, on a mat: every tile the same size.
                            PrintCell(aspect: 4 / 5, cornerRadius: 10) {
                                AsyncImage(url: roll.cover) { image in
                                    image.resizable().scaledToFit()
                                } placeholder: {
                                    Color(white: 0.1)
                                }
                            }
                                .overlay(alignment: .topTrailing) {
                                    if let audience = roll.audience.flatMap(Audience.init(rawValue:)), audience != .everyone {
                                        Image(systemName: audience.icon)
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(6)
                                            .background(Circle().fill(Color.black.opacity(0.6)))
                                            .padding(6)
                                            .accessibilityLabel(audience.title)
                                    }
                                }
                            Text(roll.title)
                                .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                            Text([String(roll.frames) + (roll.frames == 1 ? " frame" : " frames"), roll.film].compactMap { $0 }.joined(separator: " · "))
                                .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(roll.title), \(roll.frames) frames")
                }
            }
            .padding(.bottom, 12)
        }
        .refreshable { await load() }
        .onChange(of: scrollToRolls) { _, _ in reader.scrollTo("rolls-top", anchor: .top) }
        }
    }

    // MARK: Block, unfollow, sign in, report

    private var who: String {
        profile?.handle.map { "@\($0)" } ?? profile?.name.flatMap { $0.isEmpty ? nil : $0 } ?? "this person"
    }

    private var blockCard: some View {
        ConfirmCard(title: "Block \(who)?",
                    message: "You won't see their profile or rolls they share. Following ends both ways, and they can't find you, follow you or share with you.",
                    onCancel: { withAnimation(.snappy(duration: 0.15)) { confirmingBlock = false } }) {
            DestructiveButton(text: "Block", icon: "hand.raised") {
                RollShare.block(uid)
                if account.isSignedIn { Task { try? await Social.block(uid, true) } }
                confirmingBlock = false
                dismiss()
            }
            PillButton(text: "Cancel", accent: accent) { withAnimation(.snappy(duration: 0.15)) { confirmingBlock = false } }
        }
    }

    private var unfollowCard: some View {
        ConfirmCard(title: "Unfollow \(who)?",
                    message: "Rolls they share with followers stop showing for you. To follow again, you'll need to ask again.",
                    onCancel: { withAnimation(.snappy(duration: 0.15)) { confirmingUnfollow = false } }) {
            DestructiveButton(text: "Unfollow", icon: "person.badge.minus") {
                confirmingUnfollow = false
                Task {
                    do {
                        followStatus = try await Social.follow(uid, false)
                    } catch {
                        note = error.localizedDescription
                    }
                }
            }
            PillButton(text: "Cancel", accent: accent) { withAnimation(.snappy(duration: 0.15)) { confirmingUnfollow = false } }
        }
    }

    private var signInCard: some View {
        ConfirmCard(title: "Sign in to follow",
                    message: "Follow \(who) to see the rolls they share with followers. They approve every follow.",
                    onCancel: { withAnimation(.snappy(duration: 0.15)) { askingToSignIn = false } }) {
            SignInButtons(onError: { message in
                askingToSignIn = false
                note = message
            }, onSignedIn: {
                askingToSignIn = false
                if account.needsSetup {
                    note = "Finish setting up your profile (your age and a @username) to follow people."
                }
                Task { await load() }
            })
            PillButton(text: "Not now", accent: accent) { withAnimation(.snappy(duration: 0.15)) { askingToSignIn = false } }
        }
    }

    private func unblock() {
        RollShare.unblock(uid)
        note = nil
        Task {
            if account.isSignedIn {
                do { try await Social.block(uid, false) } catch { note = error.localizedDescription }
            }
            await load()
        }
    }

    // MARK: Report

    private var reportCard: some View {
        ConfirmCard(title: "Report \(who)",
                    message: "Tell us what's wrong. We review every report, and accounts that break the rules are removed.",
                    onCancel: { withAnimation(.snappy(duration: 0.15)) { reporting = false } }) {
            ForEach(["They may be under 13", "Pretending to be someone", "Hate or harassment", "Spam", "Something else"], id: \.self) { reason in
                PillButton(text: reason, accent: accent) {
                    reporting = false
                    Task {
                        do {
                            try await Social.report(uid, reason: reason)
                            note = "Thanks. We'll take a look."
                        } catch {
                            note = error.localizedDescription
                        }
                    }
                }
            }
            PillButton(text: "Cancel", accent: accent) { withAnimation(.snappy(duration: 0.15)) { reporting = false } }
        }
    }

    /// Share the profile as a card (latest roll covers, headshot, name, counts) with its link.
    private func shareProfile(_ profile: RollShare.RemoteProfile) {
        makingCard = true
        Task {
            let content = await ProfileCard.content(for: profile)
            makingCard = false
            sharing = ShareItems(items: [ShareCaption.text(.profile, link: profile.url)], activities: SendInAppActivity.forProfile(profile.id),
                                 card: CardShare(link: profile.url, kind: .profile) { ProfileCard.render(content, style: $0) })
        }
    }

    private func load() async {
        do {
            profile = try await RollShare.fetchProfile(id: uid)
            followStatus = profile?.relation?.status ?? "none"
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }
}

private struct PeopleListRef: Identifiable {
    let which: String
    var id: String { which }
}

private struct OpenRoll: Identifiable {
    let id: String
}

/// A profile to open (from a link or a roll's sharer).
struct IncomingUser: Identifiable {
    let id: String
}
