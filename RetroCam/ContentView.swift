import SwiftUI

private extension Font {
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

private let amber = Color(red: 1.0, green: 0.69, blue: 0.0)
private let cameraBody = Color(white: 0.09)

struct ContentView: View {
    @StateObject private var camera = CameraModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var focusPoint: CGPoint?
    @State private var showingPrint = false

    var body: some View {
        ZStack {
            cameraBody.ignoresSafeArea()

            VStack(spacing: 14) {
                topPlate
                viewfinder
                dials
                lensPicker
                stockPicker
                controls
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if let message = camera.message {
                toast(message)
            }
        }
        .preferredColorScheme(.dark)
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
        .sheet(isPresented: $showingPrint) {
            if let print = camera.lastPrint { PrintView(image: print) }
        }
    }

    // MARK: Top plate: frame counter, film loaded, exposure dial

    private var topPlate: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("FRAME")
                    .font(.mono(9)).foregroundStyle(.secondary)
                Text(String(format: "%02d", camera.framesShot) + "/\(CameraModel.rollLength)")
                    .font(.mono(20, .bold)).foregroundStyle(amber)
                    .contentTransition(.numericText())
            }
            .frame(width: 100, alignment: .leading)

            Spacer()

            VStack(spacing: 2) {
                Text(camera.stock.name).font(.mono(13, .semibold))
                Text("ISO \(camera.stock.iso)").font(.mono(10)).foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 14) {
                if camera.flashAvailable {
                    plateToggle(title: "FLASH", value: camera.flash.label, active: camera.flash != .off) {
                        camera.cycleFlash()
                    }
                }
                plateToggle(title: "STAMP", value: camera.stampMode.label, active: camera.stampMode != .off) {
                    camera.cycleStamp()
                }
            }
            .frame(width: 100, alignment: .trailing)
        }
    }

    /// Small tap-to-cycle control in the top plate (FLASH, STAMP).
    private func plateToggle(title: String, value: String, active: Bool,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title).font(.mono(9)).foregroundStyle(.secondary)
                Text(value)
                    .font(.mono(12, .bold))
                    .foregroundStyle(active ? amber : Color(white: 0.6))
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: value)
    }

    // MARK: Dials: exposure and grain

    private var dials: some View {
        HStack {
            dial(label: "EV", value: String(format: "%+.1f", camera.exposureBias),
                 minus: { camera.nudgeExposure(by: -1 / 3) },
                 plus: { camera.nudgeExposure(by: 1 / 3) })
            Spacer()
            dial(label: "GRAIN",
                 value: camera.grainLevel == 0 ? "OFF" : "\(Int((camera.grainLevel * 100).rounded()))%",
                 minus: { camera.nudgeGrain(by: -1) },
                 plus: { camera.nudgeGrain(by: 1) })
        }
        .padding(.horizontal, 4)
    }

    private func dial(label: String, value: String,
                      minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            dialButton("minus", action: minus)
            VStack(spacing: 2) {
                Text(label).font(.mono(9)).foregroundStyle(.secondary)
                Text(value)
                    .font(.mono(14, .bold)).foregroundStyle(amber)
                    .contentTransition(.numericText())
            }
            .frame(width: 52)
            dialButton("plus", action: plus)
        }
    }

    private func dialButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color(white: 0.18)))
        }
        .foregroundStyle(.white)
    }

    // MARK: Viewfinder

    private var viewfinder: some View {
        GeometryReader { geo in
            ZStack {
                ViewfinderView(renderer: camera.renderer)

                if let focusPoint {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(amber, lineWidth: 1.5)
                        .frame(width: 64, height: 64)
                        .position(focusPoint)
                        .transition(.opacity)
                }

                // Shutter blackout.
                Color.black.opacity(camera.shutterBlink ? 1 : 0)

                statusOverlay
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                camera.focus(at: CGPoint(x: location.x / geo.size.width, y: location.y / geo.size.height))
                withAnimation(.easeOut(duration: 0.15)) { focusPoint = location }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation { if focusPoint == location { focusPoint = nil } }
                }
            }
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(white: 0.25), lineWidth: 1))
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
                Text("RetroCam needs camera access.").font(.mono(13))
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.mono(13, .bold)).foregroundStyle(amber)
            }
            .padding()
        case .failed(let reason):
            Text(reason).font(.mono(12)).multilineTextAlignment(.center).padding()
        }
    }

    // MARK: Lens picker (only lenses this phone can do well; hidden if there's just one)

    @ViewBuilder
    private var lensPicker: some View {
        if camera.lenses.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(camera.lenses) { option in
                        let selected = option == camera.lens
                        Button { camera.selectLens(option) } label: {
                            Text(option.name)
                                .font(.mono(12, .bold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(selected ? amber.opacity(0.18) : Color(white: 0.14)))
                                .overlay(Capsule().stroke(selected ? amber : .clear, lineWidth: 1.2))
                                .foregroundStyle(selected ? amber : .white)
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
            .sensoryFeedback(.selection, trigger: camera.lens)
        }
    }

    // MARK: Film picker

    private var stockPicker: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(FilmStock.all) { stock in
                        canister(stock)
                            .id(stock.id)
                            .onTapGesture {
                                withAnimation(.snappy) {
                                    camera.stock = stock
                                    proxy.scrollTo(stock.id, anchor: .center)
                                }
                            }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private func canister(_ stock: FilmStock) -> some View {
        let selected = stock == camera.stock
        return VStack(alignment: .leading, spacing: 3) {
            Text(stock.name).font(.mono(11, .bold))
            Text(stock.blurb).font(.mono(9)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 170, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(selected ? amber.opacity(0.15) : Color(white: 0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(selected ? amber : .clear, lineWidth: 1.2)
        )
        .foregroundStyle(selected ? amber : .white)
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
                        ProgressView().tint(amber)
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .disabled(camera.lastPrint == nil)

            Spacer()

            if camera.rollFinished {
                Button { withAnimation { camera.rewindRoll() } } label: {
                    Text("REWIND")
                        .font(.mono(15, .bold))
                        .foregroundStyle(.black)
                        .frame(width: 84, height: 84)
                        .background(Circle().fill(amber))
                }
            } else {
                Button { camera.shoot() } label: { EmptyView() }
                    .buttonStyle(ShutterButtonStyle())
                .disabled(camera.status != .running)
            }

            Spacer()

            Button { camera.flipCamera() } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 20))
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
                .padding(.bottom, 140)
        }
        .transition(.opacity)
        .task(id: text) {
            try? await Task.sleep(for: .seconds(3))
            withAnimation { camera.message = nil }
        }
    }
}

/// Copper shutter release recessed in a dark machined collar. Modelled on anodised
/// metal rather than glossy plastic: matte flat face, fine grain, a bevel that catches
/// light at the top edge, and faint lathe rings in the collar.
private struct ShutterButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    private static let copperTop = Color(red: 0.92, green: 0.43, blue: 0.13)
    private static let copperBottom = Color(red: 0.80, green: 0.37, blue: 0.11)
    private static let bevelLight = Color(red: 1.00, green: 0.72, blue: 0.48)
    private static let bevelDark = Color(red: 0.42, green: 0.17, blue: 0.04)

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
            collar.frame(width: 88, height: 88)

            // Well the button sits in, with a soft contact shadow.
            Circle()
                .fill(Color(white: 0.02))
                .overlay(
                    Circle()
                        .stroke(Color.black, lineWidth: 4)
                        .blur(radius: 2.5)
                        .offset(y: 1)
                        .clipShape(Circle())
                )
                .frame(width: 69, height: 69)

            button
                .frame(width: 60, height: 60)
                .shadow(color: .black.opacity(pressed ? 0.35 : 0.6), radius: pressed ? 0.8 : 2, y: pressed ? 0.3 : 1.2)
                .brightness(pressed ? -0.06 : 0)
                .scaleEffect(pressed ? 0.96 : 1)
        }
        .saturation(isEnabled ? 1 : 0.2)
        .opacity(isEnabled ? 1 : 0.6)
        .contentShape(Circle())
        .animation(.easeOut(duration: 0.08), value: pressed)
    }

    /// Matte black anodised collar: faint lathe rings, chamfered outer edge.
    private var collar: some View {
        Circle()
            .fill(LinearGradient(colors: [Color(white: 0.105), Color(white: 0.045)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(
                Canvas { ctx, size in
                    let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                    var radius: CGFloat = 35
                    var i = 0
                    while radius < size.width / 2 - 1 {
                        let ring = Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius,
                                                          width: radius * 2, height: radius * 2))
                        ctx.stroke(ring, with: .color(.white.opacity(i % 3 == 0 ? 0.045 : 0.02)), lineWidth: 0.5)
                        radius += 0.9
                        i += 1
                    }
                }
            )
            .overlay(
                Circle().strokeBorder(
                    LinearGradient(colors: [Color(white: 0.30), Color(white: 0.12), Color(white: 0.02)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1.2)
            )
    }

    /// Flat matte copper face with fine grain and a bevelled edge.
    private var button: some View {
        Circle()
            .fill(LinearGradient(colors: [Self.copperTop, Self.copperBottom],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(
                Canvas { ctx, size in
                    for g in Self.grain {
                        let p = CGRect(x: g.x * size.width, y: g.y * size.height, width: g.r * 2, height: g.r * 2)
                        ctx.fill(Path(ellipseIn: p),
                                 with: .color((g.light ? Color.white : Color.black).opacity(g.alpha)))
                    }
                }
                .clipShape(Circle())
            )
            .overlay(
                Circle().strokeBorder(
                    LinearGradient(colors: [Self.bevelLight.opacity(0.9), .clear, Self.bevelDark.opacity(0.9)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1.4)
            )
    }
}

private struct PrintView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding(12)
                .background(Color(white: 0.95))   // white print border
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).padding()
            }
            .foregroundStyle(.white)
        }
    }
}

#Preview {
    ContentView()
}
