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
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: reload)
        .onChange(of: camera.rollsVersion) { _, _ in reload() }
        .onChange(of: selected) { _, _ in loadFrames() }
        .fullScreenCover(item: $viewing) { ref in
            FramePager(roll: ref.roll, frames: visibleFrames, start: ref.frame, accent: accent)
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

    /// The roll as a contact sheet: three across, frame numbers under each print.
    /// Frames still developing show as blank, numbered spaces.
    private var contactSheet: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 10) {
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
                            Group {
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
                                    LocalImage(url: RollStore.thumbURL(roll: selected ?? 0, frame: frame), fill: true)
                                }
                            }
                            .aspectRatio(3 / 4, contentMode: .fit)
                            .clipped()
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
                    // Keeps its label (and its size) while the sheet prints: a longer label
                    // got squeezed to "…" in this row and the pill turned into a circle.
                    chip("Sheet", selected: !ShareLinks.isConfigured, busy: makingSheet) { shareContactSheet(roll) }
                        .disabled(makingSheet)
                        .accessibilityValue(makingSheet ? "Printing" : "")
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
                    chip(unsharing ? "Unsharing…" : audience.isShared ? "Make private" : "Unshare", selected: false) { unshare() }
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
        if ShareLinks.isConfigured, account.isSignedIn, let roll, !frames.isEmpty, shareRecord?.onProfile != true {
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
            Button("Rename", systemImage: "pencil") { startRenaming(roll) }
            if !frames.isEmpty {
                Button("Delete roll", systemImage: "trash", role: .destructive) {
                    withAnimation(.snappy(duration: 0.15)) { deleting = roll }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .bold))
                .frame(width: 36, height: 36)
                .background(Circle().fill(ProfileStyle.button))
                .foregroundStyle(.white)
                .contentShape(Circle())
        }
        .accessibilityLabel("More for \(roll.title)")
    }

    // MARK: Rename a roll

    private func startRenaming(_ roll: Roll) {
        nameDraft = roll.name ?? ""
        withAnimation(.snappy(duration: 0.15)) { renaming = roll }
    }

    private func renameCard(_ target: Roll) -> some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.6).ignoresSafeArea()
                .onTapGesture { withAnimation(.snappy(duration: 0.15)) { renaming = nil } }
            VStack(alignment: .leading, spacing: 12) {
                cardTitle("Name this roll")
                ProfileField(prompt: "e.g. Beach day", text: $nameDraft, capitalization: .sentences) { saveName(target) }
                    .onChange(of: nameDraft) { _, new in
                        if new.count > Roll.maxNameLength { nameDraft = String(new.prefix(Roll.maxNameLength)) }
                    }
                cardDetail("Its album in Photos becomes \"\(previewTitle(target))\". The name also goes on the roll's contact sheet and share card.")
                cardButton("Save", destructive: false) { saveName(target) }
                if target.name != nil {
                    cardButton("Clear name", destructive: false, quiet: true) {
                        nameDraft = ""
                        saveName(target)
                    }
                }
                cardButton("Cancel", destructive: false, quiet: true) {
                    withAnimation(.snappy(duration: 0.15)) { renaming = nil }
                }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 20).fill(ProfileStyle.background))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(ProfileStyle.divider, lineWidth: 1))
            .padding(.horizontal, 22)
            .padding(.top, 80)
        }
        .transition(.opacity)
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
        let name = target.title
        return ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
                .onTapGesture { withAnimation(.snappy(duration: 0.15)) { deleting = nil } }
            VStack(alignment: .leading, spacing: 12) {
                cardTitle("Delete \(name)?")
                cardDetail(deleteDetail(target))
                cardButton("Delete from Film Exposures", destructive: false) {
                    camera.deleteRoll(target.number, deletingPhotos: false)
                    deleting = nil
                }
                cardButton("Delete roll and its photos", destructive: true) {
                    camera.deleteRoll(target.number, deletingPhotos: true)
                    deleting = nil
                }
                cardButton("Cancel", destructive: false, quiet: true) {
                    withAnimation(.snappy(duration: 0.15)) { deleting = nil }
                }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 20).fill(ProfileStyle.background))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(ProfileStyle.divider, lineWidth: 1))
            .padding(.horizontal, 22)
        }
        .transition(.opacity)
    }

    // MARK: Develop a frame early

    private func developEarlyCard(_ frame: Int) -> some View {
        let close = { withAnimation(.snappy(duration: 0.15)) { developingEarly = nil } }
        return ZStack {
            Color.black.opacity(0.6).ignoresSafeArea().onTapGesture(perform: close)
            VStack(alignment: .leading, spacing: 12) {
                cardTitle("Develop this photo?")
                cardDetail(String(format: "Take a peek at frame %02d before the rest of the roll develops. ", frame)
                     + "It only shows here, and goes into Photos with the roll when it develops \(roll.map(developWhen) ?? "on schedule"). Tap Hide on it to cover it up again.")
                cardButton("Develop it", destructive: false) {
                    if let number = selected { camera.setPeeking(roll: number, frame: frame, true) }
                    close()
                }
                cardButton("Keep waiting", destructive: false, quiet: true, action: close)
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 20).fill(ProfileStyle.background))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(ProfileStyle.divider, lineWidth: 1))
            .padding(.horizontal, 22)
        }
        .transition(.opacity)
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
        lines.append("Delete from Film Exposures keeps the photos in Photos, in the album \"\(target.albumTitle)\".")
        lines.append("Delete roll and its photos also removes that album and its photos from Photos. iOS asks you to confirm.")
        if waiting > 0 {
            lines.append("\(waiting) \(waiting == 1 ? "frame hasn't" : "frames haven't") developed yet and will be lost.")
        }
        if target.number == camera.roll.number {
            lines.append("It's the roll in the camera, so a new roll is loaded.")
        }
        return lines.joined(separator: "\n\n")
    }

    private func cardTitle(_ text: String) -> some View {
        Text(text).font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func cardDetail(_ text: String) -> some View {
        Text(text).font(.system(size: 14)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// A full-width button on an overlay card: the main action in orange, a destructive one
    /// in red, a quiet one (Cancel) as plain grey text.
    private func cardButton(_ text: String, destructive: Bool, quiet: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Capsule().fill(destructive ? Color.red.opacity(0.16) : quiet ? Color.clear : accent))
                .foregroundStyle(destructive ? ProfileStyle.destructive : quiet ? Color(white: 0.6) : Color.black)
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
        let name = target.title
        let count = developedFrames.count
        return ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
                .onTapGesture { withAnimation(.snappy(duration: 0.15)) { confirmingShare = nil } }
            VStack(alignment: .leading, spacing: 12) {
                cardTitle("Share \(name)?")
                cardDetail("""
                    Uploads its \(count) developed \(count == 1 ? "frame" : "frames") so anyone with the link can look through them, \
                    in Film Exposures or on the web, for \(RollShare.lifetimeDays) days. Unshare any time to delete them.

                    Only share photos you'd post publicly. Nudity, violence and hateful content are removed, and people can report or block you.
                    """)
                cardButton("Share roll", destructive: false) {
                    confirmingShare = nil
                    shareRoll(target)
                }
                cardButton("Cancel", destructive: false, quiet: true) {
                    withAnimation(.snappy(duration: 0.15)) { confirmingShare = nil }
                }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 20).fill(ProfileStyle.background))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(ProfileStyle.divider, lineWidth: 1))
            .padding(.horizontal, 22)
        }
        .transition(.opacity)
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
                sharing = ShareItems(items: [card as Any?, record.url].compactMap { $0 },
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
        sharing = ShareItems(items: [record.url], activities: SendInAppActivity.forRoll(record.id),
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
            if let image { sharing = ShareItems(items: [image]) }
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
                Text(String(format: "Roll %02d · Frame %02d", roll, current))
                    .font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
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
