import SwiftUI

private extension Font {
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

private let cameraBody = Color(white: 0.09)

/// The settings that live behind the icon bar.
private enum SettingPanel: String, Identifiable {
    case film, adjust, fx, lens, exposure, grain, border
    var id: String { rawValue }

    var title: String {
        switch self {
        case .film: return "FILM"
        case .adjust: return "ADJUST"
        case .fx: return "FX"
        case .lens: return "LENS"
        case .exposure: return "EXPOSURE"
        case .grain: return "GRAIN"
        case .border: return "BORDER"
        }
    }

    var symbol: String {
        switch self {
        case .film: return "film"
        case .adjust: return "slider.horizontal.3"
        case .fx: return "wand.and.rays"
        case .lens: return "camera.aperture"
        case .exposure: return "plusminus.circle"
        case .grain: return "aqi.medium"
        case .border: return "photo.artframe"
        }
    }
}

struct ContentView: View {
    @StateObject private var camera = CameraModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var focusPoint: CGPoint?
    @State private var showingPrint = false
    /// The settings panel floating over the bottom of the viewfinder, if any.
    /// It overlays the viewfinder, so opening it never moves the viewfinder or the shutter.
    @State private var openPanel: SettingPanel?
    /// Which setting the ADJUST panel's dial is editing.
    @State private var adjusting: AdjustParam = .contrast
    /// Saving or renaming a film: shows the name card.
    @State private var naming: FilmNaming?
    @State private var filmName = ""
    @FocusState private var nameFieldFocused: Bool
    /// Long-pressed film card whose actions (rename, reset, delete) the FILM panel shows.
    @State private var managingFilm: String?
    /// Film whose recipe is being shared (QR / link).
    @State private var sharingFilm: FilmStock?
    /// A film someone shared, waiting for "ADD".
    @State private var incomingFilm: FilmStock?
    @State private var confirmingDelete = false
    @AppStorage(ShutterFinish.storageKey) private var finishRaw = ShutterFinish.copper.rawValue

    private var finish: ShutterFinish { ShutterFinish(rawValue: finishRaw) ?? .copper }
    /// The app's one accent: always the shutter's finish (copper by default).
    private var accent: Color { finish.palette.accent }

    var body: some View {
        ZStack {
            cameraBody.ignoresSafeArea()

            VStack(spacing: 12) {
                // Spare height on tall phones goes above the camera body, not between
                // the icon bar and the shutter: everything sits low, near the thumb,
                // and the shutter stays close to the settings it works with.
                Spacer(minLength: 0)
                topPlate
                    .padding(.horizontal, 16)
                // Full screen width: the 3:4 frame is as big as the phone's width allows.
                viewfinder
                    .overlay { panelLayer }
                iconBar
                    .padding(.horizontal, 12)
                Spacer(minLength: 4).frame(maxHeight: 24)
                controls
                    .padding(.horizontal, 16)
            }
            .padding(.vertical, 8)

            if let message = camera.message {
                toast(message)
            }

            if let naming {
                nameCard(naming)
                    .transition(.opacity)
            }

            if let film = incomingFilm {
                importCard(film)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea(.keyboard)
        .animation(.snappy(duration: 0.2), value: naming)
        .onChange(of: openPanel) { _, _ in
            managingFilm = nil
            confirmingDelete = false
        }
        .preferredColorScheme(.dark)
        .tint(accent)
        .statusBarHidden()
        .onAppear { camera.start() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: camera.start()
            case .background: camera.stop()
            default: break
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: camera.framesShot)
        .fullScreenCover(isPresented: $showingPrint) {
            RollViewer(camera: camera, accent: accent)
        }
        .sheet(item: $sharingFilm) { film in
            FilmShareSheet(film: film, accent: accent)
        }
        .onOpenURL { url in
            if let film = FilmCode.film(from: url) {
                withAnimation(.snappy(duration: 0.2)) { incomingFilm = film }
            } else {
                camera.message = "That film link didn't work."
            }
        }
    }

    /// The open settings panel, laid over the viewfinder along whichever edge is "down"
    /// for the person holding the phone: the bottom when upright, the side when it's
    /// turned. The panel is built in a box the shape of the viewfinder *as they see it*
    /// (width and height swapped when sideways) and the box is turned to match, so the
    /// panel reads level and scrubs/scrolls along their horizontal.
    private var panelLayer: some View {
        GeometryReader { geo in
            let sideways = abs(camera.uiRotation) == 90
            let box = sideways ? CGSize(width: geo.size.height, height: geo.size.width) : geo.size
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                if let panel = openPanel {
                    panelView(panel)
                        .padding(8)
                        .transition(.opacity.combined(with: .offset(y: 14)))
                }
            }
            .frame(width: box.width, height: box.height)
            .rotationEffect(.degrees(camera.uiRotation))
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(.snappy(duration: 0.3), value: camera.uiRotation)
        }
    }

    private func toggle(_ panel: SettingPanel) {
        withAnimation(.snappy(duration: 0.25)) {
            openPanel = openPanel == panel ? nil : panel
        }
    }

    // MARK: Top plate: frame counter, film loaded, flash and date stamp

    private var topPlate: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text(String(format: "ROLL %02d", camera.roll.number))
                    .font(.mono(8, .semibold)).foregroundStyle(.secondary)
                Text(String(format: "%02d", camera.framesShot) + "/\(CameraModel.rollLength)")
                    .font(.mono(15, .bold)).foregroundStyle(accent)
                    .contentTransition(.numericText())
            }
                .frame(width: 90, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Roll \(camera.roll.number), frame \(camera.framesShot) of \(CameraModel.rollLength)")
                // Hidden: long-press for a camera-orientation readout (for bug reports).
                .onLongPressGesture { camera.showDiagnostics.toggle() }

            Spacer()

            Button { toggle(.film) } label: {
                HStack(spacing: 6) {
                    Text(camera.stock.name).font(.mono(12, .semibold))
                    Text("\(camera.stock.iso)").font(.mono(10)).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Choose film")

            Spacer()

            HStack(spacing: 6) {
                if camera.flashAvailable {
                    plateIcon(flashSymbol, active: camera.flash != .off,
                              label: "Flash \(camera.flash.label)") { camera.cycleFlash() }
                        .sensoryFeedback(.selection, trigger: camera.flash)
                }
                plateIcon("calendar", active: camera.stampMode != .off,
                          badge: camera.stampMode == .dateTime ? "T" : nil,
                          label: "Date stamp \(camera.stampMode.label)") { camera.cycleStamp() }
                    .sensoryFeedback(.selection, trigger: camera.stampMode)
            }
            .frame(width: 90, alignment: .trailing)
        }
        .frame(height: 34)
    }

    private var flashSymbol: String {
        switch camera.flash {
        case .off: return "bolt.slash"
        case .auto: return "bolt.badge.automatic"
        case .on: return "bolt.fill"
        }
    }

    /// Small tap-to-cycle icon in the top plate (flash, date stamp).
    private func plateIcon(_ symbol: String, active: Bool, badge: String? = nil, label: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 34, height: 34)
                .overlay(alignment: .bottomTrailing) {
                    if let badge {
                        Text(badge).font(.mono(8, .bold)).offset(x: -4, y: -4)
                    }
                }
                .foregroundStyle(active ? accent : Color(white: 0.55))
                .rotationEffect(.degrees(camera.uiRotation))
                .animation(.snappy(duration: 0.3), value: camera.uiRotation)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: Icon bar: every setting one tap away, opening above the bar

    private var iconBar: some View {
        HStack(spacing: 4) {
            barItem(.film, value: camera.stock.shortName)
            barItem(.adjust, value: camera.isFilmEdited ? "EDITED" : "EDIT",
                    highlighted: camera.isFilmEdited)
            if camera.lenses.count > 1 {
                barItem(.lens, value: camera.lens.map { "\($0.focalLength)" } ?? "—")
            }
            barItem(.exposure, value: exposureText, highlighted: camera.exposureBias != 0)
            barItem(.grain, value: grainText)
            barItem(.border, value: camera.border.label, highlighted: camera.border != .none)
            barItem(.fx, value: camera.stock.effect == .none ? "OFF" : camera.stock.effect.label,
                    highlighted: camera.stock.effect != .none)
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.12)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(white: 0.2), lineWidth: 0.5))
        .sensoryFeedback(.selection, trigger: openPanel)
    }

    private func barItem(_ panel: SettingPanel, value: String, highlighted: Bool = false) -> some View {
        let open = openPanel == panel
        return Button { toggle(panel) } label: {
            VStack(spacing: 4) {
                Image(systemName: panel.symbol)
                    .font(.system(size: 16, weight: .medium))
                    .frame(height: 18)
                Text(value)
                    .font(.mono(9, .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
            }
            .rotationEffect(.degrees(camera.uiRotation))
            .animation(.snappy(duration: 0.3), value: camera.uiRotation)
            .foregroundStyle(open || highlighted ? accent : Color(white: 0.8))
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 9).fill(open ? accent.opacity(0.18) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(panel.title.capitalized), \(value)")
        .accessibilityAddTraits(open ? .isSelected : [])
    }

    private var exposureText: String {
        camera.exposureBias == 0 ? "±0" : String(format: "%+.1f", camera.exposureBias)
    }

    private var grainText: String {
        camera.grainLevel == 0 ? "OFF" : "\(Int((camera.grainLevel * 100).rounded()))%"
    }

    // MARK: Panels

    private func panelView(_ panel: SettingPanel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(panel.title).font(.mono(10, .semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(panelValue(panel)).font(.mono(10, .bold)).foregroundStyle(accent)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 4)

            switch panel {
            case .film:
                if let id = managingFilm, let film = camera.library.current(id: id) {
                    filmActions(film)
                } else {
                    stockPicker
                }
            case .adjust: adjustPanel
            case .fx: fxPanel
            case .lens: lensPicker
            case .exposure:
                ScrubDial(value: Double(camera.exposureBias), range: -2...2, step: 1.0 / 3,
                          majorEvery: 3, accent: accent,
                          label: { v in abs(v) < 0.01 ? "0" : String(format: "%+.0f", v.rounded()) },
                          spoken: { v in String(format: "%+.1f stops", v) },
                          onChange: { camera.setExposure(Float($0)) })
            case .grain:
                ScrubDial(value: camera.grainLevel, range: 0...2, step: 0.1,
                          majorEvery: 5, accent: accent,
                          label: { v in v < 0.01 ? "OFF" : "\(Int((v * 100).rounded()))" },
                          spoken: { v in v == 0 ? "Off" : "\(Int(v * 100)) percent" },
                          onChange: { camera.setGrainLevel($0) })
            case .border: borderPicker
            }
        }
        .padding(Self.panelPadding)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.11).opacity(0.94)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(white: 0.25), lineWidth: 0.5))
    }

    private func panelValue(_ panel: SettingPanel) -> String {
        switch panel {
        case .film: return "ISO \(camera.stock.iso)"
        case .adjust: return camera.stock.name + (camera.isFilmEdited ? " · EDITED" : "")
        case .fx:
            let fx = camera.stock.effect
            return fx == .none ? "OFF" : "\(fx.label) · \(Int((camera.stock.effectAmount * 100).rounded()))"
        case .lens: return camera.lens.map { $0.isNative ? $0.name : "\($0.name) CROP" } ?? ""
        case .exposure: return exposureText + " EV"
        case .grain: return grainText
        case .border: return camera.border == .none ? camera.border.label : "\(camera.border.label) · \(borderWidthText)"
        }
    }

    private func chip(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.mono(12, .bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(selected ? accent.opacity(0.18) : Color(white: 0.17)))
                .overlay(Capsule().stroke(selected ? accent : .clear, lineWidth: 1.2))
                .foregroundStyle(selected ? accent : .white)
        }
        .buttonStyle(.plain)
    }

    // MARK: Viewfinder

    private var viewfinder: some View {
        GeometryReader { geo in
            ZStack {
                ViewfinderView(renderer: camera.renderer)

                if let focusPoint {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(accent, lineWidth: 1.5)
                        .frame(width: 64, height: 64)
                        .position(focusPoint)
                        .transition(.opacity)
                }

                // Shutter blackout.
                Color.black.opacity(camera.shutterBlink ? 1 : 0)

                statusOverlay

                // FX open: drag on the picture to move the effect's centre.
                if openPanel == .fx, camera.stock.effect.usesCenter {
                    Circle()
                        .stroke(accent, lineWidth: 1.5)
                        .background(Circle().fill(accent.opacity(0.15)))
                        .frame(width: 30, height: 30)
                        .overlay(Circle().fill(accent).frame(width: 4, height: 4))
                        .position(x: camera.stock.effectX * geo.size.width,
                                  y: camera.stock.effectY * geo.size.height)
                        .allowsHitTesting(false)
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { drag in
                                    let x = min(max(drag.location.x / geo.size.width, 0.03), 0.97)
                                    let y = min(max(drag.location.y / geo.size.height, 0.03), 0.97)
                                    camera.adjustFilm { $0.effectX = x; $0.effectY = y }
                                }
                        )
                }

                if let diagnostics = camera.diagnostics {
                    Text(diagnostics)
                        .font(.mono(10))
                        .padding(6)
                        .background(Color.black.opacity(0.7))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(6)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                // With a panel open, a tap on the picture just closes it.
                if openPanel != nil {
                    withAnimation(.snappy(duration: 0.25)) { openPanel = nil }
                    return
                }
                camera.focus(at: CGPoint(x: location.x / geo.size.width, y: location.y / geo.size.height))
                withAnimation(.easeOut(duration: 0.15)) { focusPoint = location }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation { if focusPoint == location { focusPoint = nil } }
                }
            }
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        .clipped()
    }

    @ViewBuilder
    private var statusOverlay: some View {
        switch camera.status {
        case .running:
            EmptyView()
        case .starting:
            Text("LOADING FILM…").font(.mono(13)).foregroundStyle(.secondary)
        case .unauthorized:
            VStack(spacing: 12) {
                Text("Exposures needs camera access.").font(.mono(13))
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.mono(13, .bold)).foregroundStyle(accent)
            }
            .padding()
        case .failed(let reason):
            Text(reason).font(.mono(12)).multilineTextAlignment(.center).padding()
        }
    }

    // MARK: Panel contents

    /// Lenses this phone can do well (the bar hides the lens item if there's just one).
    private var lensPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(camera.lenses) { option in
                    chip(option.name, selected: option == camera.lens) { camera.selectLens(option) }
                }
            }
            .padding(.horizontal, Self.scrollInset)
        }
        .edgeFade(Self.scrollInset)
        .padding(.horizontal, -Self.panelPadding)
        .sensoryFeedback(.selection, trigger: camera.lens)
    }

    private var borderWidthText: String { "\(Int((camera.borderWidth * 100).rounded()))%" }

    /// Style chips, then the width dial (only when there is a border to size).
    private var borderPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(BorderStyle.allCases, id: \.self) { style in
                    chip(style.label, selected: style == camera.border) { camera.selectBorder(style) }
                }
                Spacer(minLength: 0)
            }
            .sensoryFeedback(.selection, trigger: camera.border)

            if camera.border != .none {
                ScrubDial(value: camera.borderWidth * 100,
                          range: PrintBorder.widthRange.lowerBound * 100...PrintBorder.widthRange.upperBound * 100,
                          step: 1, majorEvery: 2, accent: accent,
                          label: { v in "\(Int(v.rounded()))" },
                          spoken: { v in "Border width \(Int(v.rounded())) percent" },
                          onChange: { camera.setBorderWidth($0 / 100) })
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.2), value: camera.border == .none)
    }

    private var stockPicker: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(camera.library.all) { stock in
                        canister(stock)
                            .id(stock.id)
                            .onTapGesture {
                                withAnimation(.snappy) {
                                    camera.selectFilm(id: stock.id)
                                    proxy.scrollTo(stock.id, anchor: .center)
                                }
                            }
                            // Long press: this film's actions, in the panel's own style.
                            .onLongPressGesture(minimumDuration: 0.35) {
                                guard hasActions(stock) else { return }
                                withAnimation(.snappy(duration: 0.2)) {
                                    managingFilm = stock.id
                                    confirmingDelete = false
                                }
                            }
                    }
                }
                .padding(.horizontal, Self.scrollInset)
            }
            .edgeFade(Self.scrollInset)
            .onAppear { proxy.scrollTo(camera.stock.id, anchor: .center) }
        }
        .padding(.horizontal, -Self.panelPadding)
        .sensoryFeedback(.selection, trigger: camera.stock.id)
        .sensoryFeedback(.impact(weight: .light), trigger: managingFilm)
    }

    /// Every film can at least be shared; your own and edited ones have more.
    private func hasActions(_ stock: FilmStock) -> Bool { true }

    private func canister(_ stock: FilmStock) -> some View {
        let selected = stock.id == camera.stock.id
        let edited = camera.library.isEdited(id: stock.id)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                if stock.isCustom {
                    Image(systemName: "person.crop.square").font(.system(size: 9, weight: .bold))
                }
                Text(stock.name).font(.mono(11, .bold)).lineLimit(1)
                if edited {
                    Circle().fill(accent).frame(width: 5, height: 5)
                        .accessibilityLabel("Edited")
                }
            }
            Text(stock.blurb).font(.mono(9)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 160, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? accent.opacity(0.15) : Color(white: 0.17))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? accent : .clear, lineWidth: 1.2)
        )
        .foregroundStyle(selected ? accent : .white)
        .accessibilityAddTraits(.isButton)
    }

    /// A long-pressed film's actions, shown in place of the film strip.
    private func filmActions(_ film: FilmStock) -> some View {
        let edited = camera.library.isEdited(id: film.id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if film.isCustom {
                    Image(systemName: "person.crop.square").font(.system(size: 10, weight: .bold))
                }
                Text(film.name).font(.mono(12, .bold)).lineLimit(1)
                if edited {
                    Text("EDITED").font(.mono(9, .bold)).foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(accent)
            .padding(.horizontal, 4)

            HStack(spacing: 6) {
                if film.isCustom {
                    smallChip("RENAME", selected: false) {
                        filmName = film.name
                        naming = .rename(film.id)
                        managingFilm = nil
                    }
                }
                if edited {
                    smallChip("RESET", selected: false) {
                        camera.selectFilm(id: film.id)
                        camera.resetFilm()
                        managingFilm = nil
                    }
                }
                if film.isCustom {
                    Button {
                        if confirmingDelete {
                            camera.deleteFilm(id: film.id)
                            managingFilm = nil
                            confirmingDelete = false
                        } else {
                            withAnimation(.snappy(duration: 0.15)) { confirmingDelete = true }
                        }
                    } label: {
                        Text(confirmingDelete ? "TAP TO DELETE" : "DELETE")
                            .font(.mono(10, .bold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.red.opacity(confirmingDelete ? 0.28 : 0.12)))
                            .overlay(Capsule().stroke(Color.red.opacity(confirmingDelete ? 0.9 : 0), lineWidth: 1))
                            .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.4))
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.warning, trigger: confirmingDelete) { _, new in new }
                }
                Spacer(minLength: 0)
                smallChip("SHARE", selected: false) {
                    sharingFilm = film
                    managingFilm = nil
                }
                smallChip("DONE", selected: true) {
                    withAnimation(.snappy(duration: 0.2)) { managingFilm = nil }
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// Name a film (save as new / rename): a card in the panels' style above the
    /// keyboard, instead of the system alert.
    private func nameCard(_ mode: FilmNaming) -> some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { naming = nil }

            VStack(alignment: .leading, spacing: 12) {
                Text(mode.title).font(.mono(10, .semibold)).foregroundStyle(.secondary)

                TextField("", text: $filmName, prompt: Text("FILM NAME").foregroundColor(Color(white: 0.35)))
                    .font(.mono(20, .bold))
                    .foregroundStyle(accent)
                    .tint(accent)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($nameFieldFocused)
                    .onSubmit { commitName(mode) }
                    .onChange(of: filmName) { _, new in
                        let capped = String(new.uppercased().prefix(FilmLibrary.maxNameLength))
                        if capped != new { filmName = capped }
                    }
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(accent.opacity(0.6)).frame(height: 1)
                    }

                if !mode.message.isEmpty {
                    Text(mode.message).font(.mono(10)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    smallChip("CANCEL", selected: false) { naming = nil }
                    Spacer()
                    smallChip(mode.action, selected: true) { commitName(mode) }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.11)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(white: 0.25), lineWidth: 0.5))
            .padding(.horizontal, 20)
            .padding(.top, 110)
            .onAppear { nameFieldFocused = true }
        }
    }

    /// Someone shared a film with you: add it to your films?
    private func importCard(_ film: FilmStock) -> some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { incomingFilm = nil }

            VStack(alignment: .leading, spacing: 12) {
                Text("FILM SHARED WITH YOU").font(.mono(10, .semibold)).foregroundStyle(.secondary)
                Text(film.name).font(.mono(20, .bold)).foregroundStyle(accent)
                Text(filmSummary(film)).font(.mono(10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    smallChip("NOT NOW", selected: false) { incomingFilm = nil }
                    Spacer()
                    smallChip("ADD TO MY FILMS", selected: true) {
                        camera.addSharedFilm(film)
                        incomingFilm = nil
                        camera.message = "\(film.name) ADDED"
                    }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.11)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(white: 0.25), lineWidth: 0.5))
            .padding(.horizontal, 20)
            .padding(.top, 110)
        }
    }

    private func filmSummary(_ film: FilmStock) -> String {
        var parts = ["FILTER " + (film.colorFilter?.label ?? "CUSTOM"),
                     "CONTRAST \(Int((film.contrast * 100).rounded()))"]
        if film.tone != .neutral, film.toneAmount > 0 { parts.append("TONE " + film.tone.label) }
        if film.effect != .none { parts.append("FX " + film.effect.label) }
        return parts.joined(separator: " · ")
    }

    private func commitName(_ mode: FilmNaming) {
        switch mode {
        case .saveNew: camera.saveFilm(named: filmName)
        case .rename(let id): camera.renameFilm(id: id, to: filmName)
        }
        nameFieldFocused = false
        naming = nil
    }

    // MARK: FX panel: lens and print effects

    private var fxPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            chipRow(LensEffect.allCases, label: \.label, selected: camera.stock.effect) { effect in
                camera.adjustFilm { $0.effect = effect }
            }
            .sensoryFeedback(.selection, trigger: camera.stock.effect)

            if camera.stock.effect != .none {
                ScrubDial(value: Double(camera.stock.effectAmount), range: 0...1, step: 0.05,
                          majorEvery: 4, accent: accent,
                          label: { "\(Int(($0 * 100).rounded()))" },
                          spoken: { "Effect strength \(Int(($0 * 100).rounded())) percent" },
                          onChange: { v in camera.adjustFilm { $0.effectAmount = CGFloat(v) } })

                if camera.stock.effect.usesCenter {
                    HStack(spacing: 6) {
                        Text("DRAG THE PICTURE TO MOVE IT")
                            .font(.mono(9)).foregroundStyle(.secondary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Spacer(minLength: 4)
                        smallChip("CENTER", selected: false) {
                            camera.adjustFilm { $0.effectX = 0.5; $0.effectY = 0.5 }
                        }
                        smallChip("TILT", selected: camera.tiltSteering) {
                            camera.tiltSteering.toggle()
                        }
                    }
                }
            }
        }
        .animation(.snappy(duration: 0.2), value: camera.stock.effect == .none)
    }

    // MARK: Adjust panel: per-film contrast, curve, tone, lens character

    private var adjustPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            adjustTabs
                .sensoryFeedback(.selection, trigger: adjusting)

            adjustControl(adjusting)
                .id(adjusting)
                .frame(minHeight: 42)

            HStack(spacing: 8) {
                Text(adjustValueText(adjusting))
                    .font(.mono(10, .bold)).foregroundStyle(accent)
                    .contentTransition(.numericText())
                Spacer(minLength: 0)
                if camera.isFilmEdited {
                    smallChip("RESET", selected: false) { camera.resetFilm() }
                }
                if camera.stock.isCustom {
                    Menu {
                        Button("Update \u{201C}\(camera.stock.name)\u{201D}") { camera.updateSavedFilm() }
                            .disabled(!camera.isFilmEdited)
                        Button("Save as new film\u{2026}") { beginSaving() }
                    } label: { chipLabel("SAVE", selected: true) }
                } else {
                    smallChip("SAVE AS MY FILM", selected: true) { beginSaving() }
                }
            }
        }
    }

    /// Which setting the dial edits: text tabs with an accent underline, so they read as
    /// navigation and not as another row of values.
    private var adjustTabs: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(AdjustParam.allCases) { param in
                        let on = param == adjusting
                        Button {
                            withAnimation(.snappy(duration: 0.2)) { adjusting = param }
                        } label: {
                            Text(param.title)
                                .font(.mono(10, .bold))
                                .foregroundStyle(on ? accent : Color(white: 0.55))
                                .padding(.vertical, 6)
                                .overlay(alignment: .bottom) {
                                    Rectangle().fill(on ? accent : .clear).frame(height: 2)
                                }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(param)
                    }
                }
                .padding(.horizontal, Self.scrollInset)
            }
            .edgeFade(Self.scrollInset)
            .onAppear { proxy.scrollTo(adjusting, anchor: .center) }
            .onChange(of: adjusting) { _, param in
                withAnimation(.snappy(duration: 0.25)) { proxy.scrollTo(param, anchor: .center) }
            }
        }
        .padding(.horizontal, -Self.panelPadding)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(white: 0.22)).frame(height: 0.5).padding(.horizontal, -Self.panelPadding)
        }
    }

    /// Panel content padding, and how far scrolling rows run into it before fading out.
    static let panelPadding: CGFloat = 10
    static let scrollInset: CGFloat = 14

    private func beginSaving() {
        filmName = camera.stock.isCustom ? camera.stock.name : "MY " + camera.stock.shortName
        naming = .saveNew
    }

    @ViewBuilder
    private func adjustControl(_ param: AdjustParam) -> some View {
        switch param {
        case .filter:
            chipRow(ColorFilter.allCases, label: \.label,
                    selected: camera.stock.colorFilter) { filter in
                camera.adjustFilm { $0.apply(filter) }
            }
        case .tone:
            chipRow(Toning.allCases, label: \.label, selected: camera.stock.tone) { tone in
                camera.adjustFilm {
                    $0.tone = tone
                    if tone != .neutral && $0.toneAmount < 0.05 { $0.toneAmount = 1 }
                }
            }
        default:
            if let path = param.keyPath {
                ScrubDial(value: Double(camera.stock[keyPath: path]),
                          range: param.range, step: param.step, majorEvery: param.majorEvery,
                          accent: accent,
                          label: { param.format($0) },
                          spoken: { "\(param.title.capitalized) \(param.format($0))" },
                          onChange: { v in camera.adjustFilm { $0[keyPath: path] = CGFloat(v) } })
            }
        }
    }

    private func adjustValueText(_ param: AdjustParam) -> String {
        switch param {
        case .filter: return "FILTER " + (camera.stock.colorFilter?.label ?? "CUSTOM")
        case .tone: return "TONE " + camera.stock.tone.label
        default:
            guard let path = param.keyPath else { return "" }
            return param.title + " " + param.format(Double(camera.stock[keyPath: path]))
        }
    }

    private func chipRow<T: Identifiable & Equatable>(_ items: [T], label: KeyPath<T, String>, selected: T?,
                                                    action: @escaping (T) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items) { item in
                    smallChip(item[keyPath: label], selected: item == selected) { action(item) }
                }
            }
            .padding(.horizontal, Self.scrollInset)
            .padding(.vertical, 4)
        }
        .edgeFade(Self.scrollInset)
        .padding(.horizontal, -Self.panelPadding)
    }

    private func smallChip(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { chipLabel(text, selected: selected) }
            .buttonStyle(.plain)
    }

    private func chipLabel(_ text: String, selected: Bool) -> some View {
        Text(text)
            .font(.mono(10, .bold))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Capsule().fill(selected ? accent.opacity(0.18) : Color(white: 0.17)))
            .overlay(Capsule().stroke(selected ? accent : .clear, lineWidth: 1))
            .foregroundStyle(selected ? accent : .white)
    }

    // MARK: Shutter row

    private var controls: some View {
        HStack {
            Button { showingPrint = true } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 4).fill(Color(white: 0.15))
                    if let print = camera.lastPrint {
                        Image(uiImage: print).resizable().scaledToFill()
                    }
                    if camera.developing > 0 {
                        ProgressView().tint(accent)
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .rotationEffect(.degrees(camera.uiRotation))
                .animation(.snappy(duration: 0.3), value: camera.uiRotation)
            }
            .disabled(camera.lastPrint == nil)
            .accessibilityLabel("Your rolls")

            Spacer()

            if camera.rollFinished {
                Button { withAnimation { camera.rewindRoll() } } label: {
                    Text("REWIND")
                        .font(.mono(15, .bold))
                        .foregroundStyle(.black)
                        .frame(width: 84, height: 84)
                        .background(Circle().fill(accent))
                }
            } else {
                Button { camera.shoot() } label: { EmptyView() }
                    .buttonStyle(ShutterButtonStyle(finish: finish))
                    .disabled(camera.status != .running)
                    // Long-press the shutter to change its finish (and the app's accent).
                    .contextMenu {
                        // Inline picker: iOS draws the checkmark on the current finish;
                        // each row shows a swatch of that finish's shutter face.
                        Picker("Shutter finish", selection: $finishRaw) {
                            ForEach(ShutterFinish.allCases) { option in
                                Label {
                                    Text(option.name)
                                } icon: {
                                    Image(uiImage: option.swatch)
                                }
                                .tag(option.rawValue)
                            }
                        }
                        .pickerStyle(.inline)
                    }
                    .sensoryFeedback(.selection, trigger: finishRaw)
                    .accessibilityLabel("Shutter")
                    .accessibilityHint("Long press to change the shutter finish")
            }

            Spacer()

            Button { camera.flipCamera() } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 20))
                    .rotationEffect(.degrees(camera.uiRotation))
                    .animation(.snappy(duration: 0.3), value: camera.uiRotation)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(Color(white: 0.15)))
            }
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 8)
    }

    private func toast(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.mono(12))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Capsule().fill(Color(white: 0.2)))
                .rotationEffect(.degrees(camera.uiRotation))
                .padding(.bottom, 140)
        }
        .transition(.opacity)
        .task(id: text) {
            try? await Task.sleep(for: .seconds(3))
            withAnimation { camera.message = nil }
        }
    }
}

private extension FilmStock {
    /// One word for the icon bar.
    var shortName: String {
        switch id {
        case "sepia": return "SEPIA"
        case "lith": return "LITH"
        default: return String(name.split(separator: " ").first ?? "")
        }
    }
}

private extension View {
    /// Fade both ends of a horizontal scroller, so a clipped item reads as "more this
    /// way" rather than as a mistake.
    func edgeFade(_ width: CGFloat) -> some View {
        mask(
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: width)
                Rectangle().fill(Color.black)
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: width)
            }
        )
    }
}

/// The film settings the ADJUST panel edits, with each one's dial scale.
private enum AdjustParam: String, CaseIterable, Identifiable {
    case filter, contrast, key, fade, whites, tone, toneAmount, glow, grainSize, vignette, softness, fog

    var id: String { rawValue }

    var title: String {
        switch self {
        case .filter: return "FILTER"
        case .contrast: return "CONTRAST"
        case .key: return "KEY"
        case .fade: return "FADE"
        case .whites: return "WHITES"
        case .tone: return "TONE"
        case .toneAmount: return "TONE %"
        case .glow: return "GLOW"
        case .grainSize: return "GRAIN SIZE"
        case .vignette: return "VIGNETTE"
        case .softness: return "SOFTNESS"
        case .fog: return "FOG"
        }
    }

    var keyPath: WritableKeyPath<FilmStock, CGFloat>? {
        switch self {
        case .filter, .tone: return nil
        case .contrast: return \.contrast
        case .key: return \.key
        case .fade: return \.blackLift
        case .whites: return \.whitePoint
        case .toneAmount: return \.toneAmount
        case .glow: return \.bloom
        case .grainSize: return \.grainSize
        case .vignette: return \.vignette
        case .softness: return \.edgeSoftness
        case .fog: return \.fog
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .key: return -1...1
        case .fade: return 0...0.25
        case .whites: return 0.75...1
        case .grainSize: return 0.6...3.0
        case .vignette: return 0...1.2
        default: return 0...1
        }
    }

    var step: Double {
        switch self {
        case .key: return 0.1
        case .fade, .whites: return 0.01
        case .grainSize: return 0.1
        default: return 0.05
        }
    }

    var majorEvery: Int {
        switch self {
        case .key, .fade, .whites: return 5
        default: return 4
        }
    }

    /// How a value reads on the dial and in the panel.
    func format(_ v: Double) -> String {
        switch self {
        case .key:
            let n = Int((v * 10).rounded())
            return n == 0 ? "0" : String(format: "%+d", n)
        case .grainSize: return String(format: "%.1f", v)
        default: return "\(Int((v * 100).rounded()))"
        }
    }
}

/// Naming a film in the name card: saving a new one or renaming one of the user's own.
private enum FilmNaming: Equatable {
    case saveNew
    case rename(String)

    var title: String {
        switch self {
        case .saveNew: return "NAME YOUR FILM"
        case .rename: return "RENAME FILM"
        }
    }

    var action: String {
        switch self {
        case .saveNew: return "SAVE"
        case .rename: return "RENAME"
        }
    }

    var message: String {
        switch self {
        case .saveNew: return "Keeps every setting, so you can load it again from the film picker."
        case .rename: return ""
        }
    }
}

/// A ruler you drag under a fixed needle, like the scale on a lens barrel.
/// Clicks to `step`; major ticks every `majorEvery` steps carry a label.
private struct ScrubDial: View {
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let majorEvery: Int
    let accent: Color
    let label: (Double) -> String
    let spoken: (Double) -> String
    let onChange: (Double) -> Void

    @State private var dragStart: Double?
    /// Points of travel per click.
    private let spacing: CGFloat = 14

    private var steps: Int { Int(((range.upperBound - range.lowerBound) / step).rounded()) }

    private func snapped(_ raw: Double) -> Double {
        let clicks = ((raw - range.lowerBound) / step).rounded()
        return min(max(range.lowerBound + clicks * step, range.lowerBound), range.upperBound)
    }

    var body: some View {
        Canvas { ctx, size in
            let mid = size.width / 2
            for i in 0...steps {
                let v = range.lowerBound + Double(i) * step
                let x = mid + CGFloat((v - value) / step) * spacing
                guard x > -20, x < size.width + 20 else { continue }
                let major = i % majorEvery == 0
                // Ticks fade towards the ends, as if the scale wraps round a barrel.
                let fade = 1 - min(abs(x - mid) / mid, 1) * 0.8
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: 6))
                tick.addLine(to: CGPoint(x: x, y: major ? 22 : 14))
                ctx.stroke(tick, with: .color(.white.opacity((major ? 0.8 : 0.4) * fade)),
                           lineWidth: major ? 1.5 : 1)
                if major {
                    ctx.draw(Text(label(v)).font(.mono(9)).foregroundColor(.white.opacity(0.75 * fade)),
                             at: CGPoint(x: x, y: 34))
                }
            }
            // Fixed index needle.
            var needle = Path()
            needle.move(to: CGPoint(x: mid, y: 0))
            needle.addLine(to: CGPoint(x: mid, y: 26))
            ctx.stroke(needle, with: .color(accent), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .frame(height: 42)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    let start = dragStart ?? value
                    if dragStart == nil { dragStart = start }
                    // Dragging right pulls lower values under the needle.
                    let next = snapped(start - Double(drag.translation.width / spacing) * step)
                    if abs(next - value) > step / 2 { onChange(next) }
                }
                .onEnded { _ in dragStart = nil }
        )
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement()
        .accessibilityValue(spoken(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(snapped(value + step))
            case .decrement: onChange(snapped(value - step))
            @unknown default: break
            }
        }
    }
}

/// Shutter release sunk into the body, in the chosen anodised finish (copper by default).
/// Lit from above like the rest of the app,
/// so the hole is dark under its top lip and light on its bottom lip, and the lip's
/// shadow falls across the top of the button. Anodised, not glossy: matte flat face,
/// fine grain, a small bevel, faint lathe rings in the bore.
private struct ShutterButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let finish: ShutterFinish

    /// Fixed speckle pattern for the anodised face (same every launch, so it never shimmers).
    private static let grain: [(x: CGFloat, y: CGFloat, r: CGFloat, light: Bool, alpha: Double)] = {
        var seed: UInt64 = 0x5EED
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53)
        }
        return (0..<700).map { _ in
            (CGFloat(next()), CGFloat(next()), CGFloat(0.25 + next() * 0.35), next() < 0.5, 0.05 + next() * 0.08)
        }
    }()

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return ZStack {
            bore.frame(width: 67, height: 67)

            button(pressed: pressed)
                .frame(width: 60, height: 60)
                .brightness(pressed ? -0.05 : 0)
                .scaleEffect(pressed ? 0.97 : 1)
        }
        .saturation(isEnabled ? 1 : 0.2)
        .opacity(isEnabled ? 1 : 0.6)
        .contentShape(Circle())
        .animation(.easeOut(duration: 0.08), value: pressed)
    }

    /// The hole cut into the body: concave, so darker at the top and lighter at the bottom.
    private var bore: some View {
        Circle()
            .fill(LinearGradient(colors: [Color(white: 0.03), Color(white: 0.09)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(
                Canvas { ctx, size in
                    let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                    var radius: CGFloat = 30.5
                    var i = 0
                    while radius < size.width / 2 - 1 {
                        let ring = Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius,
                                                          width: radius * 2, height: radius * 2))
                        ctx.stroke(ring, with: .color(.white.opacity(i % 3 == 0 ? 0.03 : 0.015)), lineWidth: 0.5)
                        radius += 0.9
                        i += 1
                    }
                }
            )
            // Shadow thrown into the hole by the upper lip.
            .overlay(
                Circle()
                    .stroke(Color.black.opacity(0.85), lineWidth: 3)
                    .blur(radius: 1.5)
                    .offset(y: 1.5)
                    .clipShape(Circle())
            )
            // Only the lower lip faces the light.
            .overlay(
                Circle().strokeBorder(
                    LinearGradient(colors: [.clear, .clear, Color.white.opacity(0.18)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.6)
            )
    }

    /// Flat matte anodised face with fine grain, a small bevel, and the lip's shadow across
    /// its top (deeper while pressed, as it sinks further).
    private func button(pressed: Bool) -> some View {
        Circle()
            .fill(LinearGradient(colors: [finish.palette.faceTop, finish.palette.faceBottom],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(
                Canvas { ctx, size in
                    for g in Self.grain {
                        let p = CGRect(x: g.x * size.width, y: g.y * size.height, width: g.r * 2, height: g.r * 2)
                        ctx.fill(Path(ellipseIn: p),
                                 with: .color((g.light ? Color.white : Color.black).opacity(g.alpha * finish.palette.grain)))
                    }
                }
                .clipShape(Circle())
            )
            .overlay(
                Circle().strokeBorder(
                    LinearGradient(colors: [finish.palette.bevelLight.opacity(0.6), .clear, finish.palette.bevelDark.opacity(0.9)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1.2)
            )
            .overlay(
                Circle().fill(
                    LinearGradient(colors: [Color.black.opacity(pressed ? 0.6 : 0.45), .clear],
                                   startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.45)))
            )
    }
}

#Preview {
    ContentView()
}
