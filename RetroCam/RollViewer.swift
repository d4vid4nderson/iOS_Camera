import SwiftUI
import UIKit

private extension Font {
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Your rolls: a contact sheet per roll and a full-screen view to swipe through the
/// frames. Frames can't be edited or deleted one by one — a roll is what you shot — but a
/// whole roll can be deleted. You can share a frame or the whole roll as a contact sheet,
/// load a new roll (ending the one in the camera early), and choose how new rolls develop.
struct RollViewer: View {
    @ObservedObject var camera: CameraModel
    let accent: Color
    @Environment(\.dismiss) private var dismiss

    @State private var rolls: [Roll] = []
    @State private var selected: Int?
    @State private var frames: [Int] = []
    @State private var pending: Set<Int> = []
    @State private var viewing: FrameRef?
    @State private var sharing: ShareItems?
    @State private var makingSheet = false
    @State private var confirmFinish = false
    @State private var deleting: Roll?

    private var roll: Roll? { rolls.first { $0.number == selected } }
    private var isInCamera: Bool { selected == camera.roll.number }
    private var developedFrames: [Int] { frames.filter { !pending.contains($0) } }

    var body: some View {
        ZStack {
            Color(white: 0.06).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                header
                if rolls.count > 1 { rollStrip }
                if frames.isEmpty {
                    Spacer()
                    Text("NO FRAMES YET").font(.mono(12, .bold)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    contactSheet
                }
                footer
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .overlay {
            if let target = deleting { deleteCard(target) }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: reload)
        .onChange(of: camera.rollsVersion) { _, _ in reload() }
        .onChange(of: selected) { _, _ in loadFrames() }
        .fullScreenCover(item: $viewing) { ref in
            FramePager(roll: ref.roll, frames: developedFrames, start: ref.frame, accent: accent)
        }
        .sheet(item: $sharing) { item in
            ActivityView(items: item.items).ignoresSafeArea()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(roll?.albumTitle.uppercased() ?? String(format: "ROLL %02d", camera.roll.number))
                    .font(.mono(15, .bold)).foregroundStyle(accent)
                Text(subtitle).font(.mono(10)).foregroundStyle(.secondary)
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
        var parts = ["\(frames.count)/\(Roll.length) FRAMES"]
        if let started = roll.started {
            parts.append(started.formatted(.dateTime.month(.abbreviated).day().year()).uppercased())
        }
        if !pending.isEmpty { parts.append(developNote(roll)) }
        if isInCamera { parts.append("IN CAMERA") }
        return parts.joined(separator: " · ")
    }

    private func developNote(_ roll: Roll) -> String {
        switch roll.develop {
        case .instant: return "DEVELOPING"
        case .rollEnd: return roll.finishedAt == nil ? "DEVELOPS WHEN FINISHED" : "DEVELOPING"
        case .nextMorning:
            guard let ready = roll.readyDate() else { return "DEVELOPS THE MORNING AFTER IT'S FINISHED" }
            return "DEVELOPS " + ready.formatted(.dateTime.weekday(.abbreviated).hour().minute()).uppercased()
        }
    }

    private var rollStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(rolls, id: \.number) { r in
                    let on = r.number == selected
                    Button { selected = r.number } label: {
                        Text(String(format: "ROLL %02d", r.number))
                            .font(.mono(10, .bold))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Capsule().fill(on ? accent.opacity(0.18) : Color(white: 0.15)))
                            .overlay(Capsule().stroke(on ? accent : .clear, lineWidth: 1))
                            .foregroundStyle(on ? accent : .white)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
    }

    // MARK: Contact sheet

    /// The roll as a contact sheet: three across, frame numbers under each print.
    /// Frames still developing show as blank, numbered spaces.
    private var contactSheet: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 10) {
                ForEach(frames, id: \.self) { frame in
                    let waiting = pending.contains(frame)
                    Button {
                        if !waiting, let number = selected { viewing = FrameRef(roll: number, frame: frame) }
                    } label: {
                        VStack(spacing: 4) {
                            Group {
                                if waiting {
                                    ZStack {
                                        Rectangle().fill(Color(white: 0.1))
                                        Rectangle().strokeBorder(Color(white: 0.22), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                        Text("DEVELOPING").font(.mono(8, .bold)).foregroundStyle(Color(white: 0.4))
                                    }
                                } else {
                                    LocalImage(url: RollStore.thumbURL(roll: selected ?? 0, frame: frame), fill: true)
                                }
                            }
                            .aspectRatio(3 / 4, contentMode: .fit)
                            .clipped()
                            Text(String(format: "%02d", frame))
                                .font(.mono(9, .semibold)).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(waiting)
                    .accessibilityLabel(waiting ? "Frame \(frame), developing" : "Frame \(frame)")
                }
            }
            .padding(.bottom, 12)
        }
    }

    // MARK: Footer: share, delete, new roll, develop mode

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if !developedFrames.isEmpty, let roll {
                    chip(makingSheet ? "PRINTING…" : "SHARE SHEET", selected: true) { shareContactSheet(roll) }
                        .disabled(makingSheet)
                }
                Spacer(minLength: 0)
                if let roll {
                    deleteChip("DELETE ROLL") { withAnimation(.snappy(duration: 0.15)) { deleting = roll } }
                }
            }

            // The roll in the camera, and loading a new one.
            VStack(alignment: .leading, spacing: 6) {
                Text("IN CAMERA").font(.mono(9, .semibold)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(cameraRollLine).font(.mono(11, .bold)).foregroundStyle(.white).lineLimit(1)
                    Spacer(minLength: 0)
                    if camera.roll.frames > 0 {
                        chip(confirmFinish ? "TAP FOR NEW ROLL" : "NEW ROLL", selected: confirmFinish) {
                            if confirmFinish {
                                camera.rewindRoll()
                                confirmFinish = false
                            } else {
                                withAnimation(.snappy(duration: 0.15)) { confirmFinish = true }
                            }
                        }
                        .sensoryFeedback(.warning, trigger: confirmFinish) { _, new in new }
                    }
                }
                if confirmFinish {
                    Text(String(format: "Roll %02d ends at frame %d; the rest stays blank.", camera.roll.number, camera.roll.frames))
                        .font(.mono(9)).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(camera.roll.frames > 0 ? "DEVELOP · FROM THE NEXT ROLL" : "DEVELOP")
                    .font(.mono(9, .semibold)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(DevelopMode.allCases) { mode in
                        chip(mode.label, selected: camera.developMode == mode) { camera.developMode = mode }
                    }
                }
                .sensoryFeedback(.selection, trigger: camera.developMode)
            }
        }
    }

    private var cameraRollLine: String {
        let r = camera.roll
        let name = String(format: "ROLL %02d", r.number)
        guard r.frames > 0 else { return "\(name) · NEW, NOTHING SHOT YET" }
        return "\(name) · \(r.frames)/\(Roll.length)" + (r.film.map { " · \($0)" } ?? "")
    }

    private func deleteChip(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.mono(10, .bold))
                .lineLimit(1)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Capsule().fill(Color.red.opacity(0.12)))
                .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.4))
        }
        .buttonStyle(.plain)
    }

    // MARK: Delete a roll

    private func deleteCard(_ target: Roll) -> some View {
        let name = String(format: "ROLL %02d", target.number)
        return ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
                .onTapGesture { withAnimation(.snappy(duration: 0.15)) { deleting = nil } }
            VStack(alignment: .leading, spacing: 12) {
                Text("DELETE \(name)?").font(.mono(15, .bold)).foregroundStyle(accent)
                Text(deleteDetail(target))
                    .font(.mono(10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                cardButton("DELETE FROM EXPOSURES", destructive: false) {
                    camera.deleteRoll(target.number, deletingPhotos: false)
                    deleting = nil
                }
                cardButton("DELETE ROLL + ITS PHOTOS", destructive: true) {
                    camera.deleteRoll(target.number, deletingPhotos: true)
                    deleting = nil
                }
                cardButton("CANCEL", destructive: false, quiet: true) {
                    withAnimation(.snappy(duration: 0.15)) { deleting = nil }
                }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.11)))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(white: 0.2), lineWidth: 1))
            .padding(.horizontal, 22)
        }
        .transition(.opacity)
    }

    private func deleteDetail(_ target: Roll) -> String {
        let stored = RollStore.frames(of: target.number)
        let waiting = RollStore.pendingFrames(of: target.number).count
        var lines = ["\(stored.count) \(stored.count == 1 ? "frame" : "frames"). Can't be undone."]
        lines.append("DELETE FROM EXPOSURES keeps the photos in Photos, in the album \"\(target.albumTitle)\".")
        lines.append("DELETE ROLL + ITS PHOTOS also removes that album and its photos from Photos. iOS asks you to confirm.")
        if waiting > 0 {
            lines.append("\(waiting) \(waiting == 1 ? "frame hasn't" : "frames haven't") developed yet and will be lost.")
        }
        if target.number == camera.roll.number {
            lines.append("It's the roll in the camera, so a new roll is loaded.")
        }
        return lines.joined(separator: "\n\n")
    }

    private func cardButton(_ text: String, destructive: Bool, quiet: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.mono(11, .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Capsule().fill(destructive ? Color.red.opacity(0.16) : quiet ? .clear : Color(white: 0.17)))
                .overlay(Capsule().stroke(destructive ? Color.red.opacity(0.6) : .clear, lineWidth: 1))
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

    private func shareContactSheet(_ roll: Roll) {
        makingSheet = true
        let frames = developedFrames
        Task {
            let image = await Task.detached(priority: .userInitiated) {
                ContactSheet.render(roll: roll, frames: frames)
            }.value
            makingSheet = false
            if let image { sharing = ShareItems(items: [image]) }
        }
    }

    // MARK: Loading

    private func reload() {
        rolls = RollStore.rolls()
        if selected == nil || !rolls.contains(where: { $0.number == selected }) {
            selected = rolls.first(where: { $0.number == camera.roll.number })?.number ?? rolls.first?.number
        }
        loadFrames()
    }

    private func loadFrames() {
        guard let number = selected else { frames = []; pending = []; return }
        frames = RollStore.frames(of: number)
        pending = Set(RollStore.pendingFrames(of: number))
    }
}

private struct FrameRef: Identifiable {
    let roll: Int
    let frame: Int
    var id: String { "\(roll)-\(frame)" }
}

/// What to hand to the share sheet.
struct ShareItems: Identifiable {
    let id = UUID()
    let items: [Any]
}

/// The system share sheet.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Full-screen frames, swipe left and right. View and share only.
private struct FramePager: View {
    let roll: Int
    let frames: [Int]
    let accent: Color
    @State private var current: Int
    @State private var sharing: ShareItems?
    @Environment(\.dismiss) private var dismiss

    init(roll: Int, frames: [Int], start: Int, accent: Color) {
        self.roll = roll
        self.frames = frames
        self.accent = accent
        _current = State(initialValue: start)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            TabView(selection: $current) {
                ForEach(frames, id: \.self) { frame in
                    LocalImage(url: RollStore.frameURL(roll: roll, frame: frame), fill: false)
                        .padding(.horizontal, 8)
                        .tag(frame)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            HStack(spacing: 10) {
                Text(String(format: "ROLL %02d · FRAME %02d", roll, current))
                    .font(.mono(11, .bold)).foregroundStyle(accent)
                    .contentTransition(.numericText())
                Spacer()
                roundButton("square.and.arrow.up", label: "Share frame") {
                    if let image = UIImage(contentsOfFile: RollStore.frameURL(roll: roll, frame: current).path) {
                        sharing = ShareItems(items: [image])
                    }
                }
                roundButton("xmark", label: "Close") { dismiss() }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .sensoryFeedback(.selection, trigger: current)
        .sheet(item: $sharing) { item in
            ActivityView(items: item.items).ignoresSafeArea()
        }
    }

    private func roundButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color(white: 0.16).opacity(0.9)))
        }
        .foregroundStyle(.white)
        .accessibilityLabel(label)
    }
}

/// An image file from the app's roll store, decoded off the main thread.
private struct LocalImage: View {
    let url: URL
    let fill: Bool
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                if fill {
                    Color.clear.overlay(Image(uiImage: image).resizable().scaledToFill())
                } else {
                    Image(uiImage: image).resizable().scaledToFit()
                }
            } else {
                Rectangle().fill(Color(white: 0.12))
            }
        }
        .task(id: url) {
            let path = url.path
            image = await Task.detached(priority: .userInitiated) {
                UIImage(contentsOfFile: path)?.preparingForDisplay()
            }.value
        }
    }
}
