import SwiftUI

private extension Font {
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Someone's profile: their headshot, name and public rolls. Tap a roll to look through it
/// (and like its frames). Opened from a roll's sharer, a profile link, or your own profile.
struct UserProfileView: View {
    let userID: String
    @ObservedObject var camera: CameraModel
    let accent: Color
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var account = Account.shared

    @State private var profile: RollShare.RemoteProfile?
    @State private var failure: String?
    @State private var opening: OpenRoll?
    @State private var sharing: ShareItems?
    @State private var confirmingBlock = false

    private var isMe: Bool { account.me?.id == userID }

    var body: some View {
        ZStack {
            Color(white: 0.06).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                header
                if RollShare.isBlocked(userID) {
                    centered("YOU BLOCKED THIS PERSON")
                } else if let profile {
                    if profile.rolls.isEmpty {
                        centered(isMe ? "NO PUBLIC ROLLS YET\nMAKE ONE PUBLIC FROM YOUR PROFILE" : "NO PUBLIC ROLLS YET")
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
        }
        .preferredColorScheme(.dark)
        .task { await load() }
        .fullScreenCover(item: $opening) { roll in
            SharedRollView(rollID: roll.id, camera: camera, accent: accent)
        }
        .sheet(item: $sharing) { item in
            ActivityView(items: item.items).ignoresSafeArea()
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
                    if let profile {
                        Text("\(profile.rolls.count) \(profile.rolls.count == 1 ? "ROLL" : "ROLLS") · \(frameCount(profile)) FRAMES")
                            .font(.mono(10)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            if let profile {
                HStack(spacing: 8) {
                    chip("SHARE PROFILE", selected: true) { sharing = ShareItems(items: [profile.url]) }
                    Spacer(minLength: 0)
                    if !isMe {
                        chip("BLOCK", selected: false) { withAnimation(.snappy(duration: 0.15)) { confirmingBlock = true } }
                    }
                }
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
        ScrollView {
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
    }

    // MARK: Block

    private var blockCard: some View {
        let who = profile?.name.flatMap { $0.isEmpty ? nil : $0 } ?? "this person"
        return ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
                .onTapGesture { withAnimation(.snappy(duration: 0.15)) { confirmingBlock = false } }
            VStack(alignment: .leading, spacing: 10) {
                Text("BLOCK \(who.uppercased())?").font(.mono(15, .bold)).foregroundStyle(accent)
                Text("You won't see their profile or rolls they share again on this phone.")
                    .font(.mono(10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                cardButton("BLOCK", destructive: true) {
                    RollShare.block(userID)
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
            profile = try await RollShare.fetchProfile(id: userID)
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }
}

private struct OpenRoll: Identifiable {
    let id: String
}

/// A profile to open (from a link or a roll's sharer).
struct IncomingUser: Identifiable {
    let id: String
}
