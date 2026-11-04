import SwiftUI

private extension Font {
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

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
    @State private var reporting = false
    @State private var makingCard = false
    @State private var followStatus = "none"
    @State private var listing: PeopleListRef?
    @State private var note: String?
    @State private var scrollToRolls = 0

    private var isMe: Bool { account.me?.id == uid }

    var body: some View {
        ZStack {
            Color(white: 0.06).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                header
                if RollShare.isBlocked(uid) {
                    centered("YOU BLOCKED THIS PERSON")
                } else if let profile {
                    if profile.rolls.isEmpty {
                        centered(isMe ? "NO SHARED ROLLS YET\nCHOOSE WHO SEES A ROLL FROM YOUR PROFILE"
                                 : followStatus == "following" ? "NO ROLLS TO SHOW YET" : "NO PUBLIC ROLLS YET\nFOLLOW TO SEE ROLLS FOR FOLLOWERS")
                    } else {
                        grid(profile)
                    }
                } else if let failure {
                    centered(failure.uppercased())
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Text(isMe ? "YOUR PROFILE" : "PROFILE").font(.mono(10, .semibold)).foregroundStyle(.secondary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color(white: 0.16)))
                }
                .foregroundStyle(.white)
                .accessibilityLabel("Close")
            }
            HStack(spacing: 14) {
                avatar
                VStack(alignment: .leading, spacing: 4) {
                    Text((profile?.name ?? (profile == nil ? " " : "FILM EXPOSURES PHOTOGRAPHER")).uppercased())
                        .font(.mono(16, .bold)).foregroundStyle(accent).lineLimit(1)
                    if let handle = profile?.handle {
                        Text("@\(handle)").font(.mono(11, .semibold)).foregroundStyle(.white).lineLimit(1)
                    }
                    if let profile {
                        if profile.relation?.followsYou == true && !isMe {
                            Text("FOLLOWS YOU").font(.mono(9, .bold)).foregroundStyle(accent)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            if let profile {
                stats(profile)
                HStack(spacing: 8) {
                    if !isMe && account.isSignedIn && profile.relation != nil {
                        FollowButton(id: uid, status: $followStatus, accent: accent, onError: { note = $0 })
                    }
                    if profile.relation?.askedYou == true && !isMe {
                        chip("APPROVE", selected: true) { approve() }
                    }
                    chip(makingCard ? "MAKING CARD…" : "SHARE PROFILE", selected: isMe || !account.isSignedIn) { shareProfile(profile) }
                        .disabled(makingCard)
                    Spacer(minLength: 0)
                    if !isMe {
                        if account.isSignedIn {
                            chip("REPORT", selected: false) { withAnimation(.snappy(duration: 0.15)) { reporting = true } }
                        }
                        chip("BLOCK", selected: false) { withAnimation(.snappy(duration: 0.15)) { confirmingBlock = true } }
                    }
                }
                if let note {
                    Text(note).font(.mono(10, .semibold)).foregroundStyle(accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func approve() {
        Task {
            do {
                try await Social.answer(uid, accept: true)
                await load()
            } catch {
                note = error.localizedDescription.uppercased()
            }
        }
    }

    @ViewBuilder private var avatar: some View {
        if let url = profile?.avatar {
            AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color(white: 0.18) }
                .frame(width: 72, height: 72)
                .clipShape(Circle())
        } else {
            ProfileAvatar(photo: nil, size: 72)
        }
    }

    /// Rolls, frames, followers, following: big numbers you can tap. Rolls and frames go to
    /// the rolls (your own: back to your profile, where you choose who sees them); followers
    /// and following open the lists.
    private func stats(_ profile: RollShare.RemoteProfile) -> some View {
        HStack(spacing: 8) {
            stat(profile.rolls.count, profile.rolls.count == 1 ? "ROLL" : "ROLLS") { showRolls() }
            stat(frameCount(profile), frameCount(profile) == 1 ? "FRAME" : "FRAMES") { showRolls() }
            stat(profile.followers, "FOLLOWERS") { if account.isSignedIn { listing = PeopleListRef(which: "followers") } }
            stat(profile.following, "FOLLOWING") { if account.isSignedIn { listing = PeopleListRef(which: "following") } }
        }
    }

    private func stat(_ value: Int?, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(value.map(String.init) ?? "–")
                    .font(.mono(20, .bold)).foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text(label).font(.mono(9, .semibold)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.11)))
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

    private func centered(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text).font(.mono(11, .bold)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: .infinity)
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
                            Color(white: 0.1)
                                .aspectRatio(3 / 4, contentMode: .fit)
                                .overlay {
                                    AsyncImage(url: roll.cover) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        Color(white: 0.1)
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(alignment: .topTrailing) {
                                    if let audience = roll.audience.flatMap(Audience.init(rawValue:)), audience != .everyone {
                                        Image(systemName: audience.icon)
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(6)
                                            .background(Circle().fill(Color.black.opacity(0.6)))
                                            .padding(6)
                                            .accessibilityLabel(audience.label)
                                    }
                                }
                            Text(roll.title.uppercased())
                                .font(.mono(11, .bold)).foregroundStyle(.white).lineLimit(1)
                            Text([String(roll.frames) + " FRAMES", roll.film].compactMap { $0 }.joined(separator: " · "))
                                .font(.mono(9)).foregroundStyle(.secondary).lineLimit(1)
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

    // MARK: Block

    private var blockCard: some View {
        let who = profile?.name.flatMap { $0.isEmpty ? nil : $0 } ?? "this person"
        return ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
                .onTapGesture { withAnimation(.snappy(duration: 0.15)) { confirmingBlock = false } }
            VStack(alignment: .leading, spacing: 10) {
                Text("BLOCK \(who.uppercased())?").font(.mono(15, .bold)).foregroundStyle(accent)
                Text("You won't see their profile or rolls they share. Following ends both ways, and they can't find you, follow you or share with you.")
                    .font(.mono(10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                cardButton("BLOCK", destructive: true) {
                    RollShare.block(uid)
                    if account.isSignedIn { Task { try? await Social.block(uid, true) } }
                    confirmingBlock = false
                    dismiss()
                }
                cardButton("CANCEL") { withAnimation(.snappy(duration: 0.15)) { confirmingBlock = false } }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.11)))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(white: 0.2), lineWidth: 1))
            .padding(.horizontal, 22)
        }
        .transition(.opacity)
    }

    // MARK: Report

    private var reportCard: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
                .onTapGesture { withAnimation(.snappy(duration: 0.15)) { reporting = false } }
            VStack(alignment: .leading, spacing: 10) {
                Text("REPORT THIS PERSON").font(.mono(15, .bold)).foregroundStyle(accent)
                Text("Tell us what's wrong. We review every report, and accounts that break the rules are removed.")
                    .font(.mono(10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                ForEach(["They may be under 13", "Pretending to be someone", "Hate or harassment", "Spam", "Something else"], id: \.self) { reason in
                    cardButton(reason.uppercased()) {
                        reporting = false
                        Task {
                            do {
                                try await Social.report(uid, reason: reason)
                                note = "THANKS. WE'LL TAKE A LOOK"
                            } catch {
                                note = error.localizedDescription.uppercased()
                            }
                        }
                    }
                }
                cardButton("CANCEL") { withAnimation(.snappy(duration: 0.15)) { reporting = false } }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.11)))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(white: 0.2), lineWidth: 1))
            .padding(.horizontal, 22)
        }
        .transition(.opacity)
    }

    private func cardButton(_ text: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.mono(11, .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Capsule().fill(destructive ? Color.red.opacity(0.16) : Color.clear))
                .overlay(Capsule().stroke(destructive ? Color.red.opacity(0.6) : Color.clear, lineWidth: 1))
                .foregroundStyle(destructive ? Color(red: 1, green: 0.45, blue: 0.4) : Color(white: 0.55))
        }
        .buttonStyle(.plain)
    }

    /// Share the profile as a card (latest roll covers, headshot, name, counts) with its link.
    private func shareProfile(_ profile: RollShare.RemoteProfile) {
        makingCard = true
        Task {
            let content = await ProfileCard.content(for: profile)
            makingCard = false
            sharing = ShareItems(items: [profile.url], activities: SendInAppActivity.forProfile(profile.id),
                                 card: CardShare(link: profile.url) { ProfileCard.render(content, style: $0) })
        }
    }

    private func chip(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.mono(10, .bold))
                .lineLimit(1)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Capsule().fill(selected ? accent.opacity(0.18) : Color(white: 0.15)))
                .overlay(Capsule().stroke(selected ? accent : .clear, lineWidth: 1))
                .foregroundStyle(selected ? accent : .white)
        }
        .buttonStyle(.plain)
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
