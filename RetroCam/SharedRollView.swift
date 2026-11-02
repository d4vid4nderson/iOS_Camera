import SwiftUI

private extension Font {
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// A roll someone shared with a link, opened in the app: look through the frames, load
/// the film it was shot on, and report or block the person who shared it.
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

    var body: some View {
        ZStack {
            Color(white: 0.06).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                header
                if let roll {
                    if RollShare.isBlocked(roll.sharer.id) {
                        centered("YOU BLOCKED THE PERSON WHO SHARED THIS ROLL")
                    } else {
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
        }
        .preferredColorScheme(.dark)
        .task { await load() }
        .fullScreenCover(item: $viewing) { start in
            RemotePager(frames: roll?.frames ?? [], start: start.index)
        }
    }

    // MARK: Header

    private var header: some View {
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
            }
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
                    Button { viewing = FrameIndex(index: index) } label: {
                        VStack(spacing: 4) {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Rectangle().fill(Color(white: 0.1))
                            }
                            .aspectRatio(3 / 4, contentMode: .fit)
                            .clipped()
                            Text(String(format: "%02d", index + 1))
                                .font(.mono(9, .semibold)).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Frame \(index + 1)")
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
        }
    }
}

private struct FrameIndex: Identifiable {
    let index: Int
    var id: Int { index }
}

/// Swipe through a shared roll's frames full screen.
private struct RemotePager: View {
    let frames: [URL]
    @State var start: Int
    @Environment(\.dismiss) private var dismiss

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
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
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
