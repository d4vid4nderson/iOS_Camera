import SwiftUI
import UIKit

/// "ROLL END" → "Roll end": labels shared with the camera's uppercase controls, shown here
/// in the profile style's sentence case.
private func sentenceCase(_ text: String) -> String {
    let lower = text.lowercased()
    return lower.prefix(1).uppercased() + lower.dropFirst()
}

/// Your rolls: a contact sheet per roll and a full-screen view to swipe through the
/// frames. Frames can't be edited or deleted one by one — a roll is what you shot — but a
/// whole roll can be deleted. You can share a frame or the whole roll as a contact sheet,
/// switch between part-shot rolls (a food roll, a holiday roll…), load a new roll, finish
/// the one in the camera, and choose how new rolls develop.
struct RollViewer: View {
    @ObservedObject var camera: CameraModel
    let accent: Color
    /// Open on the roll in the camera (from the frame counter), even before its first
    /// frame; otherwise on the newest roll with frames (from the last print).
    var opensInCamera = false
    /// Open on this roll instead (from your profile).
    var opensOnRoll: Int? = nil
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
    @State private var confirmingShare: Roll?
    @State private var uploading: (done: Int, total: Int)?
    @State private var shareRecord: RollShare.Record?
    @State private var unsharing = false
    /// "Make private" / "Unshare" asks first: it takes the roll off your profile and kills the link.
    @State private var confirmingPrivate = false
    @State private var renaming: Roll?
    /// A developing frame you tapped: asks before showing it early.
    @State private var developingEarly: Int?
    /// Developing frames you're peeking at.
    @State private var peeking: Set<Int> = []
    @ObservedObject private var account = Account.shared
    /// Put on your profile before anything developed: goes on when its first frames do.
    @State private var waitingForProfile = false
    @State private var addingToProfile: (done: Int, total: Int)?
    @State private var nameDraft = ""

    private var roll: Roll? { rolls.first { $0.number == selected } }
    private var isInCamera: Bool { selected == camera.roll.number }
    private var developedFrames: [Int] { frames.filter { !pending.contains($0) } }
    /// What you can see: developed frames, and developing ones you're peeking at.
    private var visibleFrames: [Int] { frames.filter { !pending.contains($0) || peeking.contains($0) } }
    /// The roll's cover: the frame picked for it, or else its first developed frame.
    private var coverFrame: Int? {
        roll?.cover.flatMap { developedFrames.contains($0) ? $0 : nil } ?? developedFrames.first
    }

    var body: some View {
        ZStack {
            Color(white: 0.06).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                header
                if rolls.count > 1 { rollStrip }
                if frames.isEmpty {
                    Spacer()
                    EmptyState(icon: "film", title: "No frames yet",
                               detail: isInCamera ? "Frames you shoot on this roll show up here." : "This roll has no frames.")
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
            if let frame = developingEarly { developEarlyCard(frame) }
            if let target = renaming { renameCard(target) }
            if let target = confirmingShare { shareCard(target) }
            if confirmingPrivate, let roll { privateCard(roll) }
        }
        // Share, delete and profile errors land here: the camera's toast is behind this screen.
        .cameraMessages(camera)
        .preferredColorScheme(.dark)
        .onAppear(perform: reload)
        .onChange(of: camera.rollsVersion) { _, _ in reload() }
        .onChange(of: selected) { _, _ in loadFrames() }
        .fullScreenCover(item: $viewing) { ref in
            // Frames shot before settings were recorded still get their film's name.
            FramePager(roll: ref.roll, frames: visibleFrames, start: ref.frame, accent: accent,
                       films: RollStore.films(of: ref.roll).compactMapValues { camera.library.current(id: $0)?.name })
        }
        .sheet(item: $sharing) { item in
            ShareSheetView(item: item)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                // Tap the title to name the roll.
                Button {
                    if let roll { startRenaming(roll) }
                } label: {
                    HStack(spacing: 8) {
                        Text((roll ?? camera.roll).title)
                            .font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(roll == nil)
                .accessibilityHint("Rename this roll")
                Text(subtitle).font(.system(size: 14)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color(white: 0.16)))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(.white)
            .accessibilityLabel("Close")
        }
    }

    private var subtitle: String {
        guard let roll else { return "" }
        var parts = ["\(frames.count)/\(Roll.length) frames"]
        if let started = roll.started {
            parts.append(started.formatted(.dateTime.month(.abbreviated).day().year()))
        }
        if !pending.isEmpty { parts.append(developNote(roll)) }
        if isInCamera {
            parts.append("In camera")
        } else if roll.isOpen {
            parts.append("\(Roll.length - roll.frames) frames left")
        }
        return parts.joined(separator: " · ")
    }

    private func developNote(_ roll: Roll) -> String {
        switch roll.develop {
        case .instant: return "Developing"
        case .rollEnd: return roll.finishedAt == nil ? "Develops when finished" : "Developing"
        case .nextMorning:
            guard let ready = roll.readyDate() else { return "Develops the morning after it's finished" }
            return "Develops " + ready.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        }
    }

    private var rollStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(rolls, id: \.number) { r in
                    let on = r.number == selected
                    Button { selected = r.number } label: {
                        HStack(spacing: 6) {
                            if r.number == camera.roll.number {
                                Image(systemName: "camera.fill").font(.system(size: 11, weight: .semibold))
                            } else if r.isOpen {
                                Image(systemName: "circle.lefthalf.filled").font(.system(size: 11, weight: .semibold))
                            }
                            Text(r.title).lineLimit(1)
                        }
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Capsule().fill(on ? accent : ProfileStyle.button))
                            .foregroundStyle(on ? .black : .white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(r.title + (r.number == camera.roll.number ? ", in camera" : r.isOpen ? ", part-shot" : ""))
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
    }

    // MARK: Contact sheet

    /// The shape of this roll's prints (width ÷ height), from its first developed frame:
    /// wide formats get landscape cells, two across.
    private var printAspect: CGFloat? {
        guard let number = selected,
              let frame = frames.first(where: { !pending.contains($0) || peeking.contains($0) }) else { return nil }
        return PrintLayout.aspect(ofImageAt: RollStore.thumbURL(roll: number, frame: frame))
    }

    /// The roll as a contact sheet: three across, frame numbers under each print.
    /// Frames still developing show as blank, numbered spaces.
    private var contactSheet: some View {
        let shape = printAspect
        let cell = PrintLayout.cellAspect(for: shape)
        return ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: PrintLayout.columns(for: shape)), spacing: 10) {
                ForEach(frames, id: \.self) { frame in
                    let waiting = pending.contains(frame) && !peeking.contains(frame)
                    let peeked = pending.contains(frame) && peeking.contains(frame)
                    Button {
                        if waiting {
                            withAnimation(.snappy(duration: 0.15)) { developingEarly = frame }
                        } else if let number = selected {
                            viewing = FrameRef(roll: number, frame: frame)
                        }
                    } label: {
                        VStack(spacing: 4) {
                            PrintCell(aspect: cell) {
                                if waiting {
                                    ZStack {
                                        Rectangle().fill(Color(white: 0.1))
                                        Rectangle().strokeBorder(Color(white: 0.22), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                        VStack(spacing: 3) {
                                            Text("Developing").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(white: 0.45))
                                            Text("Tap to develop").font(.system(size: 10)).foregroundStyle(Color(white: 0.35))
                                        }
                                    }
                                } else {
                                    // The whole print, border and all, whatever its format.
                                    LocalImage(url: RollStore.thumbURL(roll: selected ?? 0, frame: frame), fill: false)
                                }
                            }
                            .overlay(alignment: .topLeading) {
                                if !waiting, frame == coverFrame {
                                    Text("Cover")
                                        .font(.system(size: 11, weight: .bold))
                                        .padding(.horizontal, 7).padding(.vertical, 3)
                                        .background(Capsule().fill(accent))
                                        .foregroundStyle(.black)
                                        .padding(4)
                                }
                            }
                            Text(String(format: "%02d", frame))
                                .font(.system(size: 12, weight: .medium).monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .topTrailing) {
                        if peeked, let number = selected {
                            // Peeking: tap to cover it up again.
                            Button { camera.setPeeking(roll: number, frame: frame, false) } label: {
                                Label("Hide", systemImage: "eye.slash.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Capsule().fill(Color.black.opacity(0.7)))
                                    .foregroundStyle(.white)
                                    .padding(4)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Hide frame \(frame) again")
                        }
                    }
                    .contextMenu {
                        if !waiting, !peeked, let number = selected {
                            if frame == coverFrame, roll?.cover != nil {
                                Button("Use the First Frame as Cover", systemImage: "arrow.uturn.backward") {
                                    camera.setCover(ofRoll: number, to: nil)
                                }
                            } else if frame != coverFrame {
                                Button("Set as Roll Cover", systemImage: "photo") {
                                    camera.setCover(ofRoll: number, to: frame)
                                }
                            }
                        }
                    }
                    .accessibilityLabel(waiting ? "Frame \(frame), developing" : "Frame \(frame)" + (frame == coverFrame ? ", cover" : ""))
                    .accessibilityHint(waiting ? "Develop this frame now" : "")
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
                    if ShareLinks.isConfigured {
                        if let uploading {
                            chip("Uploading \(uploading.done)/\(uploading.total)", selected: true) {}
                                .disabled(true)
                        } else if shareRecord != nil {
                            chip("Share link", selected: true) { shareLinkAgain(roll) }
                        } else {
                            chip("Share roll", selected: true) {
                                withAnimation(.snappy(duration: 0.15)) { confirmingShare = roll }
                            }
                        }
                    }
                    if !ShareLinks.isConfigured {
                        // No share server: the contact sheet is the only way to share.
                        chip("Share contact sheet", selected: true, busy: makingSheet) { shareContactSheet(roll) }
                            .disabled(makingSheet)
                    }
                }
                Spacer(minLength: 0)
                if let roll, roll.isOpen, !isInCamera {
                    chip("Shoot this roll", selected: true) { load(roll.number) }
                }
                if let roll { moreMenu(roll) }
            }
            if let shareRecord {
                HStack(spacing: 8) {
                    let audience = shareRecord.shownAudience
                    Text(audience == .everyone ? "Public · on your profile"
                         : audience == .followers ? "Followers · on your profile"
                         : audience == .people ? "Shared with \(shareRecord.people?.count ?? 0) \((shareRecord.people?.count ?? 0) == 1 ? "person" : "people")"
                         : "Shared · link works until " + shareRecord.expiresAt.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(audience.isShared ? accent : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    chip(unsharing ? "Unsharing…" : audience.isShared ? "Make private" : "Unshare", selected: false) {
                        withAnimation(.snappy(duration: 0.15)) { confirmingPrivate = true }
                    }
                    .disabled(unsharing)
                }
            }

            profileRow

            // The roll in the camera: switch to another part-shot roll, load a new one, or
            // finish this one.
            VStack(alignment: .leading, spacing: 6) {
                FieldLabel("In camera")
                Text(cameraRollLine).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                if camera.roll.frames > 0 {
                    HStack(spacing: 8) {
                        chip("New roll", selected: false) {
                            confirmFinish = false
                            camera.loadNewRoll()
                            selected = camera.roll.number
                        }
                        chip(confirmFinish ? "Tap to finish" : "Finish roll", selected: confirmFinish) {
                            if confirmFinish {
                                camera.rewindRoll()
                                confirmFinish = false
                            } else {
                                withAnimation(.snappy(duration: 0.15)) { confirmFinish = true }
                            }
                        }
                        .sensoryFeedback(.warning, trigger: confirmFinish) { _, new in new }
                        Spacer(minLength: 0)
                    }
                    Text(confirmFinish
                         ? "\(camera.roll.title) ends at frame \(camera.roll.frames); the rest stays blank\(camera.roll.develop == .instant ? "." : ", and it goes to be developed.")"
                         : "New roll keeps \(camera.roll.title) part-shot, to come back to.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                let others = camera.openRolls()
                if !others.isEmpty {
                    FieldLabel("Switch to").padding(.top, 4)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(others, id: \.number) { other in
                                chip("\(other.title) · \(other.frames)/\(Roll.length)", selected: false) {
                                    load(other.number)
                                }
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(camera.roll.frames > 0 ? "Develop · from the next roll" : "Develop")
                ChoicePills(options: DevelopMode.allCases.map { ($0, sentenceCase($0.label)) },
                            selection: Binding(get: { camera.developMode }, set: { camera.developMode = $0 }),
                            accent: accent)
                    .sensoryFeedback(.selection, trigger: camera.developMode)
            }
        }
    }

    /// Your public profile and this roll: add it (even while you're still shooting it; frames
    /// join it as they develop), or see that it's on there or waiting to develop.
    @ViewBuilder private var profileRow: some View {
        // Only for rolls that aren't shared with anyone in particular (private or link-only):
        // a roll shared with followers or chosen people mustn't become public by one tap.
        if ShareLinks.isConfigured, account.isSignedIn, let roll, !frames.isEmpty,
           shareRecord == nil || shareRecord?.shownAudience == .link {
            HStack(spacing: 8) {
                if waitingForProfile {
                    Text("Goes on your profile when it develops")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(accent)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    chip("Cancel", selected: false) {
                        RollShare.setWaitsForProfile(roll.number, false)
                        waitingForProfile = false
                    }
                } else if let addingToProfile {
                    chip("Adding \(addingToProfile.done)/\(addingToProfile.total)", selected: true) {}
                        .disabled(true)
                    Spacer(minLength: 0)
                } else {
                    chip("Add to profile", selected: true) { addToProfile(roll) }
                    Spacer(minLength: 0)
                }
            }
        } else if let shareRecord, shareRecord.onProfile, let roll, !RollStore.pendingFrames(of: roll.number).isEmpty || roll.isOpen {
            FootnoteText("New frames join it on your profile as they develop.")
        }
    }

    private func addToProfile(_ roll: Roll) {
        guard account.me?.termsAccepted == true else {
            camera.message = "Open your profile and agree to the rules for public rolls first."
            return
        }
        guard !developedFrames.isEmpty else {
            // Nothing developed yet: it goes on when the first frames do.
            RollShare.setWaitsForProfile(roll.number, true)
            waitingForProfile = true
            return
        }
        addingToProfile = (0, developedFrames.count + 1)
        Task {
            do {
                let record = try await RollShare.makePublic(roll: roll, film: camera.film(ofRoll: roll.number), profile: Profile.load()) { done, total in
                    addingToProfile = (done, total)
                }
                if roll.number == selected { shareRecord = record }
            } catch {
                camera.message = error.localizedDescription
            }
            addingToProfile = nil
        }
    }

    /// Put a part-shot roll in the camera and go back to shooting.
    private func load(_ number: Int) {
        confirmFinish = false
        camera.loadRoll(number)
        if camera.roll.number == number { dismiss() }
    }

    private var cameraRollLine: String {
        let r = camera.roll
        let name = r.title
        guard r.frames > 0 else { return "\(name) · nothing shot yet" }
        return "\(name) · \(r.frames)/\(Roll.length)" + (r.film.map { " · \($0)" } ?? "")
    }

    /// Rename and delete, kept out of the way behind "…".
    private func moreMenu(_ roll: Roll) -> some View {
        Menu {
            if ShareLinks.isConfigured, !developedFrames.isEmpty {
                // All the frames on one print, to post anywhere.
                Button("Share contact sheet", systemImage: "square.grid.3x3") { shareContactSheet(roll) }
                    .disabled(makingSheet)
            }
            Button("Rename", systemImage: "pencil") { startRenaming(roll) }
            if !frames.isEmpty {
                Button("Delete roll", systemImage: "trash", role: .destructive) {
                    withAnimation(.snappy(duration: 0.15)) { deleting = roll }
                }
            }
        } label: {
            Group {
                if makingSheet { ProgressView().controlSize(.small).tint(.white) }
                else { Image(systemName: "ellipsis") }
            }
                .font(.system(size: 15, weight: .bold))
                .frame(width: 36, height: 36)
                .background(Circle().fill(ProfileStyle.button))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More for \(roll.title)")
    }

    // MARK: Rename a roll

    private func startRenaming(_ roll: Roll) {
        nameDraft = roll.name ?? ""
        withAnimation(.snappy(duration: 0.15)) { renaming = roll }
    }

    private func renameCard(_ target: Roll) -> some View {
        let close = { withAnimation(.snappy(duration: 0.15)) { renaming = nil } }
        return ConfirmCard(title: "Name this roll",
                           message: "Its album in Photos becomes \"\(previewTitle(target))\". The name also goes on the roll's contact sheet and share card.",
                           onCancel: close) {
            ProfileField(prompt: "e.g. Beach day", text: $nameDraft, capitalization: .sentences) { saveName(target) }
                .accessibilityLabel("Roll name")
                .onChange(of: nameDraft) { _, new in
                    if new.count > Roll.maxNameLength { nameDraft = String(new.prefix(Roll.maxNameLength)) }
                }
            PillButton(text: "Save", filled: true, accent: accent) { saveName(target) }
            if target.name != nil {
                PillButton(text: "Clear name", accent: accent) {
                    nameDraft = ""
                    saveName(target)
                }
            }
            cancelButton(close)
        }
    }

    private func previewTitle(_ target: Roll) -> String {
        var preview = target
        preview.name = Roll.cleanName(nameDraft)
        return preview.albumTitle
    }

    private func saveName(_ target: Roll) {
        camera.renameRoll(target.number, to: nameDraft)
        withAnimation(.snappy(duration: 0.15)) { renaming = nil }
    }

    // MARK: Delete a roll

    private func deleteCard(_ target: Roll) -> some View {
        let close = { withAnimation(.snappy(duration: 0.15)) { deleting = nil } }
        return ConfirmCard(title: "Delete \(target.title)?", message: deleteDetail(target), onCancel: close) {
            DestructiveButton(text: "Delete roll, keep photos", icon: "trash") {
                camera.deleteRoll(target.number, deletingPhotos: false)
                deleting = nil
            }
            DestructiveButton(text: "Delete roll and photos", icon: "trash.fill") {
                camera.deleteRoll(target.number, deletingPhotos: true)
                deleting = nil
            }
            cancelButton(close)
        }
    }

    // MARK: Develop a frame early

    private func developEarlyCard(_ frame: Int) -> some View {
        let close = { withAnimation(.snappy(duration: 0.15)) { developingEarly = nil } }
        return ConfirmCard(title: "Develop this frame?",
                           message: String(format: "Take a peek at frame %02d before the rest of the roll develops. ", frame)
                               + "It only shows here, and goes into Photos with the roll when it develops \(roll.map(developWhen) ?? "on schedule"). Tap Hide on it to cover it up again.",
                           onCancel: close) {
            PillButton(text: "Develop it", filled: true, accent: accent) {
                if let number = selected { camera.setPeeking(roll: number, frame: frame, true) }
                close()
            }
            PillButton(text: "Keep waiting", accent: accent, action: close)
        }
    }

    private func developWhen(_ roll: Roll) -> String {
        switch roll.develop {
        case .instant: return "now"
        case .rollEnd: return "at the end of the roll"
        case .nextMorning: return "the morning after the roll is finished"
        }
    }

    private func deleteDetail(_ target: Roll) -> String {
        let stored = RollStore.frames(of: target.number)
        let waiting = RollStore.pendingFrames(of: target.number).count
        var lines = ["\(stored.count) \(stored.count == 1 ? "frame" : "frames"). Can't be undone."]
        lines.append("Delete roll, keep photos leaves them in Photos, in the album \"\(target.albumTitle)\".")
        lines.append("Delete roll and photos also removes that album and its photos from Photos. iOS asks you to confirm.")
        if waiting > 0 {
            lines.append("\(waiting) \(waiting == 1 ? "frame hasn't" : "frames haven't") developed yet and will be lost.")
        }
        if target.number == camera.roll.number {
            lines.append("It's the roll in the camera, so a new roll is loaded.")
        }
        return lines.joined(separator: "\n\n")
    }

    // MARK: Make a roll private

    private func privateCard(_ roll: Roll) -> some View {
        let close = { withAnimation(.snappy(duration: 0.15)) { confirmingPrivate = false } }
        let shared = shareRecord?.shownAudience.isShared == true
        return ConfirmCard(title: shared ? "Make \(roll.title) private?" : "Unshare \(roll.title)?",
                           message: (shared ? "It comes off your profile and out of the people's Shared with you, and its link stops working."
                                            : "Its link stops working for everyone you sent it to.")
                               + " The uploaded photos are deleted from the server. Your roll stays on this phone.",
                           onCancel: close) {
            DestructiveButton(text: shared ? "Make private" : "Unshare", icon: "lock") {
                confirmingPrivate = false
                unshare()
            }
            cancelButton(close)
        }
    }

    /// Cancel on a confirmation card: quiet grey text, full width.
    private func cancelButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Cancel").font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(Color(white: 0.6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A compact pill: orange with black text when it's the main action or the chosen option.
    private func chip(_ text: String, selected: Bool, busy: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .opacity(busy ? 0 : 1)
                .overlay { if busy { ProgressView().controlSize(.small).tint(selected ? .black : .white) } }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(selected ? accent : ProfileStyle.button))
                .foregroundStyle(selected ? .black : .white)
        }
        .buttonStyle(.plain)
    }

    // MARK: Share a roll as a link

    private func shareCard(_ target: Roll) -> some View {
        let count = developedFrames.count
        let close = { withAnimation(.snappy(duration: 0.15)) { confirmingShare = nil } }
        return ConfirmCard(title: "Share \(target.title)?",
                           message: """
                               Uploads its \(count) developed \(count == 1 ? "frame" : "frames") so anyone with the link can look through them, \
                               in Film Exposures or on the web, for \(RollShare.lifetimeDays) days. Unshare any time to delete them.

                               Only share photos you'd post publicly. Nudity, violence and hateful content are removed, and people can report or block you.
                               """,
                           onCancel: close) {
            PillButton(text: "Share roll", filled: true, accent: accent) {
                confirmingShare = nil
                shareRoll(target)
            }
            cancelButton(close)
        }
    }

    private func shareRoll(_ roll: Roll) {
        let frames = developedFrames
        let film = camera.film(ofRoll: roll.number)
        let profile = Profile.load()
        uploading = (0, frames.count + 1)
        Task {
            do {
                let (record, card) = try await RollShare.share(roll: roll, frames: frames, film: film, profile: profile) { done, total in
                    uploading = (done, total)
                }
                uploading = nil
                if roll.number == selected { shareRecord = record }
                sharing = ShareItems(items: [card.map(SharedPicture.init) as Any?, ShareCaption.text(.roll, link: record.url)].compactMap { $0 },
                                     activities: SendInAppActivity.forRoll(record.id),
                                     card: CardShare(link: record.url) { style in
                                         RollShare.card(for: roll, record: record, film: film, profile: profile, style: style)
                                     })
            } catch {
                uploading = nil
                camera.message = error.localizedDescription
            }
        }
    }

    private func shareLinkAgain(_ roll: Roll) {
        guard let record = shareRecord else { return }
        let film = camera.film(ofRoll: roll.number)
        let profile = Profile.load()
        sharing = ShareItems(items: [ShareCaption.text(.roll, link: record.url)], activities: SendInAppActivity.forRoll(record.id),
                             card: CardShare(link: record.url) { style in
                                 RollShare.card(for: roll, record: record, film: film, profile: profile, style: style)
                             })
    }

    private func unshare() {
        guard let number = selected else { return }
        unsharing = true
        Task {
            do {
                try await RollShare.unshare(roll: number)
                shareRecord = nil
            } catch {
                camera.message = error.localizedDescription
            }
            unsharing = false
        }
    }

    private func shareContactSheet(_ roll: Roll) {
        makingSheet = true
        let frames = developedFrames
        Task {
            let image = await Task.detached(priority: .userInitiated) {
                ContactSheet.render(roll: roll, frames: frames)
            }.value
            makingSheet = false
            if let image {
                sharing = ShareItems(items: [SharedPicture(image), ShareCaption.text(.contactSheet, link: RollShare.record(for: roll.number)?.url)])
            }
        }
    }

    // MARK: Loading

    private func reload() {
        rolls = RollStore.rolls()
        // The roll in the camera is always listed, even before its first frame.
        if !rolls.contains(where: { $0.number == camera.roll.number }) {
            rolls.insert(camera.roll, at: 0)
        }
        if selected == nil || !rolls.contains(where: { $0.number == selected }) {
            if let start = opensOnRoll, rolls.contains(where: { $0.number == start }) {
                selected = start
            } else if opensInCamera {
                selected = camera.roll.number
            } else {
                selected = rolls.first(where: { !RollStore.frames(of: $0.number).isEmpty })?.number ?? camera.roll.number
            }
        }
        loadFrames()
    }

    private func loadFrames() {
        guard let number = selected else { frames = []; pending = []; shareRecord = nil; return }
        frames = RollStore.frames(of: number)
        pending = Set(RollStore.pendingFrames(of: number))
        peeking = Set(pending.filter { RollStore.isPeeking(roll: number, frame: $0) })
        waitingForProfile = RollShare.waitsForProfile(number)
        shareRecord = RollShare.record(for: number)
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
    /// The app's own buttons in the share sheet (e.g. Send in Film Exposures).
    var activities: [UIActivity] = []
    /// A card that comes in LIGHT / DARK / SLIDE: the style is picked before the share sheet.
    var card: CardShare? = nil
}

/// The system share sheet.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    var activities: [UIActivity] = []

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: activities.isEmpty ? nil : activities)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Full-screen frames, swipe left and right, pinch or double-tap to zoom, with how each
/// one was shot over its corner.
/// View and share only.
private struct FramePager: View {
    let roll: Int
    let frames: [Int]
    let accent: Color
    /// Film names by frame, for frames shot before their settings were recorded.
    let films: [Int: String]
    @State private var current: Int
    @State private var sharing: ShareItems?
    @State private var settings: [Int: FrameSettings] = [:]
    /// The settings overlay is showing (the info button hides it to see the whole frame).
    @AppStorage("viewer.showsSettings") private var showsSettings = true
    @Environment(\.dismiss) private var dismiss

    init(roll: Int, frames: [Int], start: Int, accent: Color, films: [Int: String] = [:]) {
        self.roll = roll
        self.frames = frames
        self.accent = accent
        self.films = films
        _current = State(initialValue: start)
    }

    /// What's known about how a frame was shot.
    private func rows(for frame: Int) -> [(label: String, value: String)] {
        if let recorded = settings[frame] { return recorded.rows }
        if let film = films[frame] { return [("Film", film)] }
        return []
    }

    /// A frame's settings, small, over the top-left corner of the picture: a label and
    /// its value on each line.
    private func settingsOverlay(for frame: Int) -> some View {
        let lines = rows(for: frame)
        return Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 3) {
            if lines.isEmpty {
                GridRow { Text("Settings weren't recorded").foregroundStyle(.white.opacity(0.75)) }
            }
            ForEach(lines, id: \.label) { row in
                GridRow {
                    Text(row.label).foregroundStyle(.white.opacity(0.6))
                    Text(row.value).fontWeight(.semibold).foregroundStyle(.white)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .font(.system(size: 10.5))
        .lineLimit(1)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.55)))
        .padding(10)
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            TabView(selection: $current) {
                ForEach(frames, id: \.self) { frame in
                    // Pinch or double-tap to zoom. The settings sit in the picture's own
                    // corner, and step aside while it's zoomed.
                    ZoomablePage(url: RollStore.frameURL(roll: roll, frame: frame),
                                 isCurrent: frame == current, showsOverlay: showsSettings) {
                        settingsOverlay(for: frame)
                    }
                    .padding(.horizontal, 8)
                        .tag(frame)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            HStack(spacing: 10) {
                Text(String(format: "Roll %02d · Frame %02d", roll, current))
                    .font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
                    .contentTransition(.numericText())
                Spacer()
                roundButton(showsSettings ? "info.circle.fill" : "info.circle",
                            label: showsSettings ? "Hide settings" : "Show settings") {
                    withAnimation(.snappy(duration: 0.2)) { showsSettings.toggle() }
                }
                roundButton("square.and.arrow.up", label: "Share frame") {
                    if let image = UIImage(contentsOfFile: RollStore.frameURL(roll: roll, frame: current).path) {
                        sharing = ShareItems(items: [SharedPicture(image), ShareCaption.text(.frame, link: RollShare.frameLink(roll: roll, frame: current))])
                    }
                }
                roundButton("xmark", label: "Close") { dismiss() }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .task(id: roll) {
            let number = roll
            settings = await Task.detached { RollStore.settings(of: number) }.value
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .sensoryFeedback(.selection, trigger: current)
        .sheet(item: $sharing) { item in
            ShareSheetView(item: item)
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

/// One full-screen frame: the picture, zoomable, with an overlay pinned to its top-left
/// corner (wherever that falls once the picture is fitted to the screen).
private struct ZoomablePage<Overlay: View>: View {
    let url: URL
    /// The page on screen. A page that's swiped away goes back to its fitted size.
    let isCurrent: Bool
    let showsOverlay: Bool
    @ViewBuilder var overlay: () -> Overlay
    @State private var image: UIImage?
    @State private var zoomed = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if let image {
                    ZoomableImage(image: image, isCurrent: isCurrent, zoomed: $zoomed)
                    if showsOverlay, !zoomed {
                        let corner = Self.fittedOrigin(of: image.size, in: geo.size)
                        overlay().offset(x: corner.x, y: corner.y)
                    }
                } else {
                    Rectangle().fill(Color(white: 0.12))
                }
            }
            .animation(.easeOut(duration: 0.15), value: zoomed)
        }
        .task(id: url) {
            let path = url.path
            image = await Task.detached(priority: .userInitiated) {
                UIImage(contentsOfFile: path)?.preparingForDisplay()
            }.value
        }
    }

    /// Where the top-left corner of a picture lands when it's fitted, centred, in `box`.
    private static func fittedOrigin(of picture: CGSize, in box: CGSize) -> CGPoint {
        guard picture.width > 0, picture.height > 0 else { return .zero }
        let scale = min(box.width / picture.width, box.height / picture.height)
        return CGPoint(x: (box.width - picture.width * scale) / 2,
                       y: (box.height - picture.height * scale) / 2)
    }
}

/// A picture you can pinch to zoom, drag around while zoomed, and double-tap to zoom in
/// on a spot or back out. A scroll view, so at its fitted size a sideways swipe still
/// turns the page, and when zoomed it turns the page once you reach the picture's edge.
private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    let isCurrent: Bool
    @Binding var zoomed: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> ZoomScrollView {
        let scroll = ZoomScrollView()
        scroll.delegate = context.coordinator
        scroll.imageView.image = image
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)
        return scroll
    }

    func updateUIView(_ scroll: ZoomScrollView, context: Context) {
        context.coordinator.parent = self
        if scroll.imageView.image !== image {
            scroll.imageView.image = image
            scroll.setZoomScale(1, animated: false)
        }
        if !isCurrent, scroll.zoomScale != 1 { scroll.setZoomScale(1, animated: false) }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ZoomableImage

        init(_ parent: ZoomableImage) { self.parent = parent }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            (scrollView as? ZoomScrollView)?.imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            let zoomed = scrollView.zoomScale > 1.01
            guard zoomed != parent.zoomed else { return }
            DispatchQueue.main.async { self.parent.zoomed = zoomed }
        }

        /// Zoom in on the spot that was tapped, or back out to the whole picture.
        @objc func doubleTapped(_ gesture: UITapGestureRecognizer) {
            guard let scroll = gesture.view as? ZoomScrollView else { return }
            if scroll.zoomScale > 1.01 {
                scroll.setZoomScale(1, animated: true)
            } else {
                let scale = ZoomScrollView.doubleTapScale
                let point = gesture.location(in: scroll.imageView)
                let size = CGSize(width: scroll.bounds.width / scale, height: scroll.bounds.height / scale)
                scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                       width: size.width, height: size.height), animated: true)
            }
        }
    }
}

/// The scroll view behind `ZoomableImage`: the picture fills it, fitted, at 1×.
private final class ZoomScrollView: UIScrollView {
    static let doubleTapScale: CGFloat = 2.5
    let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        minimumZoomScale = 1
        // The roll keeps a screen-sharp copy (2048 px long side): past about 4× there's
        // nothing more to see.
        maximumZoomScale = 4
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .clear
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // At 1× the picture's view is exactly the scroll view, so there's nothing to
        // scroll and a sideways swipe goes to the pager.
        if zoomScale == minimumZoomScale, imageView.frame.size != bounds.size {
            imageView.frame = CGRect(origin: .zero, size: bounds.size)
            contentSize = bounds.size
        }
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
