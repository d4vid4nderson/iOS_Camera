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

            Spacer()

            VStack(spacing: 2) {
                Text(camera.stock.name).font(.mono(13, .semibold))
                Text("ISO \(camera.stock.iso)").font(.mono(10)).foregroundStyle(.secondary)
            }

            Spacer()

            // Balances the FRAME counter so the film name stays centred.
            Color.clear.frame(width: 70, height: 1)
        }
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
                Button { camera.shoot() } label: {
                    ZStack {
                        Circle().stroke(Color(white: 0.85), lineWidth: 4).frame(width: 84, height: 84)
                        Circle().fill(Color(white: 0.92)).frame(width: 70, height: 70)
                    }
                }
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

private struct ShutterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
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
