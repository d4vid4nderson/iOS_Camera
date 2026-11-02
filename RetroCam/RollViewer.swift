import SwiftUI

private extension Font {
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Your rolls, read-only: a contact sheet per roll and a full-screen view to swipe
/// through the frames. Nothing here edits or deletes — a roll is what you shot.
struct RollViewer: View {
    @ObservedObject var camera: CameraModel
    let accent: Color
    @Environment(\.dismiss) private var dismiss

    @State private var rolls: [Roll] = []
    @State private var selected: Int?
    @State private var frames: [Int] = []
    @State private var viewing: FrameRef?

    private var roll: Roll? { rolls.first { $0.number == selected } }

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
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: reload)
        .onChange(of: camera.developing) { _, _ in reload() }
        .onChange(of: selected) { _, _ in loadFrames() }
        .fullScreenCover(item: $viewing) { ref in
            FramePager(roll: ref.roll, frames: frames, start: ref.frame, accent: accent)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(roll?.albumTitle.uppercased() ?? "YOUR ROLLS")
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
        if roll.number == camera.roll.number { parts.append("IN CAMERA") }
        return parts.joined(separator: " · ")
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

    /// The roll as a contact sheet: three across, frame numbers under each print.
    private var contactSheet: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 10) {
                ForEach(frames, id: \.self) { frame in
                    Button {
                        if let number = selected { viewing = FrameRef(roll: number, frame: frame) }
                    } label: {
                        VStack(spacing: 4) {
                            LocalImage(url: RollStore.thumbURL(roll: selected ?? 0, frame: frame), fill: true)
                                .aspectRatio(3 / 4, contentMode: .fit)
                                .clipped()
                            Text(String(format: "%02d", frame))
                                .font(.mono(9, .semibold)).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Frame \(frame)")
                }
            }
            .padding(.bottom, 24)
        }
    }

    private func reload() {
        rolls = RollStore.rolls()
        if selected == nil || !rolls.contains(where: { $0.number == selected }) {
            selected = rolls.first(where: { $0.number == camera.roll.number })?.number ?? rolls.first?.number
        }
        loadFrames()
    }

    private func loadFrames() {
        frames = selected.map { RollStore.frames(of: $0) } ?? []
    }
}

private struct FrameRef: Identifiable {
    let roll: Int
    let frame: Int
    var id: String { "\(roll)-\(frame)" }
}

/// Full-screen frames, swipe left and right. View only.
private struct FramePager: View {
    let roll: Int
    let frames: [Int]
    let accent: Color
    @State private var current: Int
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

            HStack {
                Text(String(format: "ROLL %02d · FRAME %02d", roll, current))
                    .font(.mono(11, .bold)).foregroundStyle(accent)
                    .contentTransition(.numericText())
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color(white: 0.16).opacity(0.9)))
                }
                .foregroundStyle(.white)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .sensoryFeedback(.selection, trigger: current)
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
