import SwiftUI

private extension Font {
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// A roll someone shared, opened in the app: look through the frames and like them, load
/// the film it was shot on, open the sharer's profile, and report or block them.
struct SharedRollView: View {
    let rollID: String
    @ObservedObject var camera: CameraModel
    let accent: Color
    @Environment(\.dismiss) private var dismiss

    @State private var roll: RollShare.RemoteRoll?
    @State private var failure: String?
    @State private var viewing: FrameIndex?
    @State private var reporting = false
    @State private var confirmingBlock = false
    @State private var note: String?
    @State private var filmLoaded = false
    @State private var likes = RollShare.Likes(counts: [:], mine: [])
    @State private var askingToSignIn = false
    @State private var sharerProfile: IncomingUser?
    @State private var likersOf: LikersOf?

    var body: some View {
        ZStack {
            Color(white: 0.06).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                header
                if let roll {
                    if RollShare.isBlocked(roll.sharer.id) {
                        centered("YOU BLOCKED THE PERSON WHO SHARED THIS ROLL")
                    } else {
                        rollLikes
                        grid(roll)
                        footer(roll)
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

            if reporting, let roll { reportCard(roll) }
            if confirmingBlock, let roll { blockCard(roll) }
            if askingToSignIn { signInCard }
        }
        .preferredColorScheme(.dark)
        .task { await load() }
        .fullScreenCover(item: $viewing) { start in
            RemotePager(frames: roll?.frames ?? [], start: start.index, accent: accent, camera: camera, likes: $likes) { frame in
                await toggleLike(frame)
            }
        }
        .fullScreenCover(item: $sharerProfile) { user in
            UserProfileView(userID: user.id, camera: camera, accent: accent)
        }
        .sheet(item: $likersOf) { of in
            LikersSheet(frame: of.frame, people: likes.people(of.frame), count: likes.count(of.frame), camera: camera, accent: accent)
        }
    }

    /// Like the whole roll, and who did.
    private var rollLikes: some View {
        let roll = RollShare.Likes.roll
        return HStack(spacing: 10) {
            if likes.count(roll) > 0 {
                LikedBy(people: likes.people(roll), count: likes.count(roll)) { likersOf = LikersOf(frame: roll) }
            } else {
                Text("LIKE THIS ROLL").font(.mono(10, .semibold)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            LikeButton(count: likes.count(roll), liked: likes.isMine(roll), accent: accent, size: 15, what: "roll") {
                Task { await toggleLike(roll) }
            }
        }
        .padding(.leading, 12).padding(.trailing, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.1)))
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: openSharer) {
                HStack(alignment: .top, spacing: 10) {
                    if let avatar = roll?.sharer.avatar {
                        AsyncImage(url: avatar) { image in image.resizable().scaledToFill() } placeholder: { Color(white: 0.18) }
                            .frame(width: 36, height: 36)
                            .clipShape(Circle())
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text((roll?.title ?? "SHARED ROLL").uppercased())
                            .font(.mono(15, .bold)).foregroundStyle(accent)
                        Text(subtitle).font(.mono(10)).foregroundStyle(.secondary).lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if roll?.sharer.profile != nil {
                            Text("VIEW PROFILE ›").font(.mono(9, .bold)).foregroundStyle(.white)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .allowsHitTesting(roll?.sharer.profile != nil)
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
    }

    private var subtitle: String {
        guard let roll else { return "" }
        var parts: [String] = []
        if let name = roll.sharer.name, !name.isEmpty { parts.append(name.uppercased()) }
        parts.append("\(roll.frames.count) FRAMES")
        if let film = roll.film.name { parts.append(film) }
        if let shot = roll.shotAt { parts.append(shot.uppercased()) }
        return parts.joined(separator: " · ")
    }

    private func centered(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text).font(.mono(11, .bold)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: .infinity)
            Spacer()
        }
    }

    // MARK: Frames

    private func grid(_ roll: RollShare.RemoteRoll) -> some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 10) {
                ForEach(Array(roll.frames.enumerated()), id: \.offset) { index, url in
                    VStack(spacing: 4) {
                        Button { viewing = FrameIndex(index: index) } label: {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Rectangle().fill(Color(white: 0.1))
                            }
                            .aspectRatio(3 / 4, contentMode: .fit)
                            .clipped()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Frame \(index + 1)")
                        HStack(spacing: 6) {
                            Text(String(format: "%02d", index + 1))
                                .font(.mono(9, .semibold)).foregroundStyle(.secondary)
                            if likes.count(index + 1) > 0 {
                                Button { likersOf = LikersOf(frame: index + 1) } label: {
                                    AvatarStack(people: likes.people(index + 1), size: 15)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Who liked frame \(index + 1)")
                            }
                            Spacer(minLength: 0)
                            LikeButton(count: likes.count(index + 1), liked: likes.isMine(index + 1), accent: accent, size: 11) {
                                Task { await toggleLike(index + 1) }
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 12)
        }
    }

    // MARK: Footer: load the film, report, block

    private func footer(_ roll: RollShare.RemoteRoll) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let note {
                Text(note).font(.mono(10, .semibold)).foregroundStyle(accent)
            }
            HStack(spacing: 8) {
                if let film = sharedFilm(roll) {
                    chip(filmLoaded ? "\(film.name) ADDED" : "LOAD \(film.name)", selected: true) {
                        guard !filmLoaded else { return }
                        camera.addSharedFilm(film)
                        filmLoaded = true
                        note = "\(film.name) IS IN YOUR FILMS AND LOADED IN THE CAMERA"
                    }
                }
                Spacer(minLength: 0)
                chip("REPORT", selected: false) { withAnimation(.snappy(duration: 0.15)) { reporting = true } }
                if roll.sharer.id != nil {
                    chip("BLOCK", selected: false) { withAnimation(.snappy(duration: 0.15)) { confirmingBlock = true } }
                }
            }
        }
    }

    private func sharedFilm(_ roll: RollShare.RemoteRoll) -> FilmStock? {
        guard let code = roll.film.code, let url = URL(string: "exposures://f/\(code)") else { return nil }
        return FilmCode.film(from: url)
    }

    private func reportCard(_ roll: RollShare.RemoteRoll) -> some View {
        overlayCard(title: "REPORT THIS ROLL", detail: "Tell us what's wrong. Rolls with several reports are hidden until they're reviewed.") {
            ForEach(["Nudity or sexual content", "Violence or abuse", "Hate or harassment", "Spam", "Something else"], id: \.self) { reason in
                cardButton(reason.uppercased()) {
                    reporting = false
                    Task {
                        do {
                            try await RollShare.report(id: roll.id, reason: reason)
                            note = "THANKS. THE ROLL HAS BEEN REPORTED"
                        } catch {
                            note = error.localizedDescription.uppercased()
                        }
                    }
                }
            }
            cardButton("CANCEL", quiet: true) { withAnimation(.snappy(duration: 0.15)) { reporting = false } }
        }
    }

    private func blockCard(_ roll: RollShare.RemoteRoll) -> some View {
        let who = roll.sharer.name.flatMap { $0.isEmpty ? nil : $0 } ?? "this person"
        return overlayCard(title: "BLOCK \(who.uppercased())?", detail: "You won't see rolls they share again on this phone.") {
            cardButton("BLOCK", destructive: true) {
                RollShare.block(roll.sharer.id)
                confirmingBlock = false
                dismiss()
            }
            cardButton("CANCEL", quiet: true) { withAnimation(.snappy(duration: 0.15)) { confirmingBlock = false } }
        }
    }

    private func overlayCard<Content: View>(title: String, detail: String, @ViewBuilder buttons: () -> Content) -> some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
                .onTapGesture { withAnimation(.snappy(duration: 0.15)) { reporting = false; confirmingBlock = false } }
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.mono(15, .bold)).foregroundStyle(accent)
                Text(detail).font(.mono(10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                buttons()
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.11)))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(white: 0.2), lineWidth: 1))
            .padding(.horizontal, 22)
        }
        .transition(.opacity)
    }

    private func cardButton(_ text: String, destructive: Bool = false, quiet: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.mono(11, .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Capsule().fill(destructive ? Color.red.opacity(0.16) : quiet ? Color.clear : Color(white: 0.17)))
                .overlay(Capsule().stroke(destructive ? Color.red.opacity(0.6) : Color.clear, lineWidth: 1))
                .foregroundStyle(destructive ? Color(red: 1, green: 0.45, blue: 0.4) : quiet ? Color(white: 0.55) : Color.white)
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
            roll = try await RollShare.fetch(id: rollID)
        } catch {
            failure = error.localizedDescription
            return
        }
        if let fetched = try? await RollShare.likes(id: rollID) { likes = fetched }
    }

    // MARK: Likes and the sharer's profile

    private func openSharer() {
        guard let roll, roll.sharer.profile != nil, let id = roll.sharer.id else { return }
        sharerProfile = IncomingUser(id: id)
    }

    /// Like or unlike a frame (numbered from 1), showing it straight away and putting it
    /// back if the server says no. Signed out, it asks you to sign in.
    @MainActor
    private func toggleLike(_ frame: Int) async {
        guard Account.shared.isSignedIn else {
            viewing = nil
            withAnimation(.snappy(duration: 0.15)) { askingToSignIn = true }
            return
        }
        let before = likes
        let on = !likes.isMine(frame)
        likes.set(frame, liked: on, me: .me)
        do {
            let count = try await RollShare.like(id: rollID, frame: frame, on)
            likes.set(frame, liked: on, count: count)
        } catch {
            likes = before
            note = error.localizedDescription.uppercased()
        }
    }

    private var signInCard: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
                .onTapGesture { withAnimation(.snappy(duration: 0.15)) { askingToSignIn = false } }
            VStack(alignment: .leading, spacing: 12) {
                Text("SIGN IN TO LIKE").font(.mono(15, .bold)).foregroundStyle(accent)
                Text("One like per person, so likes mean something. People see your name and photo on what you like. Signing in also lets you put your own rolls on a public profile.")
                    .font(.mono(10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                SignInButtons(onError: { message in
                    askingToSignIn = false
                    note = message.uppercased()
                }, onSignedIn: {
                    askingToSignIn = false
                    Task { if let fetched = try? await RollShare.likes(id: rollID) { likes = fetched } }
                })
                cardButton("NOT NOW", quiet: true) { withAnimation(.snappy(duration: 0.15)) { askingToSignIn = false } }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.11)))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(white: 0.2), lineWidth: 1))
            .padding(.horizontal, 22)
        }
        .transition(.opacity)
    }
}

/// A heart and a count. Filled in the accent when it's your like.
struct LikeButton: View {
    let count: Int
    let liked: Bool
    let accent: Color
    var size: CGFloat = 11
    /// What's being liked, for VoiceOver: "frame" or "roll".
    var what = "frame"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: liked ? "heart.fill" : "heart")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(liked ? accent : Color(white: 0.6))
                    .contentTransition(.symbolEffect(.replace))
                if count > 0 {
                    Text("\(count)").font(.system(size: size - 1, weight: .semibold, design: .monospaced))
                        .foregroundStyle(liked ? accent : Color(white: 0.6))
                        .contentTransition(.numericText())
                }
            }
            .padding(.vertical, 4).padding(.leading, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: liked)
        .accessibilityLabel(liked ? "Unlike \(what)" : "Like \(what)")
        .accessibilityValue(count == 1 ? "1 like" : "\(count) likes")
    }
}

private struct FrameIndex: Identifiable {
    let index: Int
    var id: Int { index }
}

/// Swipe through a shared roll's frames full screen. Double-tap a frame to like it.
private struct RemotePager: View {
    let frames: [URL]
    @State var start: Int
    let accent: Color
    let camera: CameraModel
    @Binding var likes: RollShare.Likes
    let toggle: (Int) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var burst = 0
    @State private var likersOf: LikersOf?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $start) {
                ForEach(Array(frames.enumerated()), id: \.offset) { index, url in
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        burst += 1
                        if !likes.isMine(index + 1) { Task { await toggle(index + 1) } }
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .overlay {
                Image(systemName: "heart.fill")
                    .font(.system(size: 84))
                    .foregroundStyle(accent)
                    .shadow(radius: 12)
                    .phaseAnimator([false, true], trigger: burst) { heart, phase in
                        heart.scaleEffect(phase ? 1 : 0.6).opacity(phase ? 0.95 : 0)
                    } animation: { _ in .snappy(duration: 0.22) }
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    // Who liked this frame, under the photo.
                    LikedBy(people: likes.people(start + 1), count: likes.count(start + 1), size: 22) {
                        likersOf = LikersOf(frame: start + 1)
                    }
                    HStack {
                        Text(String(format: "%02d / %02d", start + 1, frames.count))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color(white: 0.6))
                        Spacer()
                        LikeButton(count: likes.count(start + 1), liked: likes.isMine(start + 1), accent: accent, size: 18) {
                            Task { await toggle(start + 1) }
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 18)
            }
            .sheet(item: $likersOf) { of in
                LikersSheet(frame: of.frame, people: likes.people(of.frame), count: likes.count(of.frame), camera: camera, accent: accent)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color(white: 0.16)))
            }
            .foregroundStyle(.white)
            .padding(16)
            .accessibilityLabel("Close")
        }
    }
}

private struct LikersOf: Identifiable {
    let frame: Int
    var id: Int { frame }
}

/// A liker's headshot, or their initial when they have none.
struct Headshot: View {
    let person: RollShare.Liker
    let size: CGFloat

    var body: some View {
        Group {
            if let url = person.avatar {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color(white: 0.2) }
            } else {
                ZStack {
                    Color(white: 0.24)
                    Text(initial)
                        .font(.system(size: size * 0.46, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var initial: String {
        guard let first = person.name?.trimmingCharacters(in: .whitespaces).first else { return "·" }
        return String(first).uppercased()
    }
}

/// The first few likers' headshots, overlapping.
struct AvatarStack: View {
    let people: [RollShare.Liker]
    var size: CGFloat = 16
    var limit = 3

    var body: some View {
        HStack(spacing: -size * 0.35) {
            ForEach(people.prefix(limit)) { person in
                Headshot(person: person, size: size)
                    .overlay(Circle().stroke(Color(white: 0.06), lineWidth: max(1, size * 0.08)))
            }
        }
    }
}

/// "LIKED BY YOU, ANA AND 3 OTHERS", with their headshots. Tap to see everyone.
struct LikedBy: View {
    let people: [RollShare.Liker]
    let count: Int
    var size: CGFloat = 18
    let action: () -> Void
    @ObservedObject private var account = Account.shared

    var body: some View {
        if count > 0 {
            Button(action: action) {
                HStack(spacing: 8) {
                    AvatarStack(people: people, size: size)
                    Text(Self.summary(people, count: count, me: account.me?.id))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(white: 0.78))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows everyone who liked it")
        }
    }

    static func summary(_ people: [RollShare.Liker], count: Int, me: String?) -> String {
        let names = people.prefix(2).map { person -> String in
            if person.id == me { return "YOU" }
            let name = person.name?.trimmingCharacters(in: .whitespaces) ?? ""
            return name.isEmpty ? "SOMEONE" : name.uppercased()
        }
        guard !names.isEmpty else { return count == 1 ? "1 LIKE" : "\(count) LIKES" }
        let others = max(0, count - names.count)
        switch (names.count, others) {
        case (1, 0): return "LIKED BY \(names[0])"
        case (2, 0): return "LIKED BY \(names[0]) AND \(names[1])"
        case (1, _): return "LIKED BY \(names[0]) AND \(others) \(others == 1 ? "OTHER" : "OTHERS")"
        default: return "LIKED BY \(names[0]), \(names[1]) AND \(others) \(others == 1 ? "OTHER" : "OTHERS")"
        }
    }
}

/// Everyone who liked a frame (or the roll, frame 0). Tap someone to open their profile.
struct LikersSheet: View {
    let frame: Int
    let people: [RollShare.Liker]
    let count: Int
    @ObservedObject var camera: CameraModel
    let accent: Color
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var account = Account.shared
    @State private var opening: IncomingUser?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("LIKED BY").font(.system(size: 15, weight: .bold, design: .monospaced)).foregroundStyle(accent)
                    Text(frame == RollShare.Likes.roll ? "THIS ROLL" : String(format: "FRAME %02d", frame))
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color(white: 0.16)))
                }
                .foregroundStyle(.white)
                .accessibilityLabel("Close")
            }
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(people) { person in
                        Button { opening = IncomingUser(id: person.id) } label: {
                            HStack(spacing: 12) {
                                Headshot(person: person, size: 38)
                                Text(label(person))
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.white)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color(white: 0.4))
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens their profile")
                    }
                    if count > people.count {
                        Text("AND \(count - people.count) MORE")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                    }
                }
            }
        }
        .padding(20)
        .background(Color(white: 0.08).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .fullScreenCover(item: $opening) { user in
            UserProfileView(userID: user.id, camera: camera, accent: accent)
        }
    }

    private func label(_ person: RollShare.Liker) -> String {
        let name = person.name?.trimmingCharacters(in: .whitespaces) ?? ""
        let shown = name.isEmpty ? "SOMEONE" : name.uppercased()
        return person.id == account.me?.id ? "\(shown) (YOU)" : shown
    }
}
