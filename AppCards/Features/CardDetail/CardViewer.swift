import SwiftUI
import CoreMotion

/// Inclinación suave según cómo sostienes el teléfono (giroscopio). Sin permisos.
@MainActor
final class DeviceTilt: ObservableObject {
    @Published private(set) var x: Double = 0
    @Published private(set) var y: Double = 0
    private let manager = CMMotionManager()
    private var reference: CMAttitude?

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1 / 60
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let attitude = motion?.attitude else { return }
            if self.reference == nil { self.reference = attitude.copy() as? CMAttitude }
            if let reference = self.reference { attitude.multiply(byInverseOf: reference) }
            // ±10° como máximo: es un detalle, no debe marear.
            self.x = max(min(attitude.pitch * 180 / .pi, 10), -10)
            self.y = max(min(attitude.roll * 180 / .pi, 10), -10)
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        reference = nil
    }
}

/// Visor de carta a pantalla completa.
/// Arrastra para inclinarla en 3D con brillo holográfico, pellizca o toca dos veces para acercar.
struct CardViewer: View {
    let url: URL?
    let title: String
    var color: Color = .vaultBlue
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var deviceTilt = DeviceTilt()

    @State private var appeared = false
    @State private var drag: CGSize = .zero
    @State private var isTouching = false
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var lastPan: CGSize = .zero

    private let maxTilt: Double = 28

    var body: some View {
        GeometryReader { geo in
            let cardWidth = min(geo.size.width - 48, (geo.size.height - 200) * 0.716, 520)
            let tilt = tiltAngles(in: geo.size)

            ZStack {
                background
                    .onTapGesture { if scale == 1 { close() } }

                card(width: cardWidth, tilt: tilt)
                    .scaleEffect(scale * (appeared ? 1 : 0.85))
                    .offset(pan)
                    .gesture(dragGesture(in: geo.size))
                    .simultaneousGesture(magnifyGesture)
                    .onTapGesture(count: 2) { toggleZoom() }
                    .accessibilityLabel("Carta \(title)")
                    .accessibilityHint("Arrastra para inclinarla. Toca dos veces para acercar.")
                    .accessibilityAddTraits(.isImage)
                    .accessibilityIdentifier("card-viewer-card")

                VStack {
                    HStack {
                        Text(title)
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer()
                        Button(action: close) {
                            Image(systemName: "xmark")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(.white.opacity(0.18), in: Circle())
                        }
                        .accessibilityLabel("Cerrar")
                    }
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.top, 8)
                    Spacer()
                    Text(scale > 1 ? "Arrastra para mover · toca dos veces para alejar" : "Arrastra para inclinar · pellizca para acercar")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.bottom, 24)
                        .animation(Motion.gentle, value: scale > 1)
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden()
        .onAppear {
            DiagnosticsLog.event("viewer appeared title=\(title)")
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) { appeared = true }
            if !reduceMotion { deviceTilt.start() }
        }
        .onDisappear {
            DiagnosticsLog.event("viewer disappeared")
            deviceTilt.stop()
        }
    }

    // MARK: Piezas

    private var background: some View {
        ZStack {
            Color.black
            RadialGradient(colors: [color.opacity(0.55), .clear], center: .center, startRadius: 20, endRadius: 520)
                .blur(radius: 30)
        }
        .ignoresSafeArea()
    }

    private func card(width: CGFloat, tilt: (x: Double, y: Double)) -> some View {
        let shape = RoundedRectangle(cornerRadius: width * 0.045, style: .continuous)
        return AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().interpolation(.high).antialiased(true).scaledToFit()
            } else {
                shape.fill(.white.opacity(0.1))
                    .aspectRatio(0.716, contentMode: .fit)
                    .overlay { ProgressView().tint(.white) }
            }
        }
        .frame(width: width)
        .overlay { holoShine(tilt: tilt).clipShape(shape) }
        .clipShape(shape)
        .shadow(color: color.opacity(0.55), radius: 30, x: -tilt.y * 1.2, y: 20 + tilt.x * 1.2)
        .shadow(color: .black.opacity(0.5), radius: 12, x: -tilt.y * 0.6, y: 10 + tilt.x * 0.6)
        .rotation3DEffect(.degrees(tilt.x), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
        .rotation3DEffect(.degrees(tilt.y), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        .scaleEffect(isTouching && scale == 1 ? 1.03 : 1)
    }

    /// Reflejo que recorre la carta según la inclinación.
    private func holoShine(tilt: (x: Double, y: Double)) -> some View {
        let strength = min((abs(tilt.x) + abs(tilt.y)) / maxTilt, 1)
        let px = 0.5 + tilt.y / (maxTilt * 2)
        let py = 0.5 - tilt.x / (maxTilt * 2)
        return ZStack {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white.opacity(0.55), location: 0.5),
                    .init(color: .clear, location: 1),
                ],
                startPoint: UnitPoint(x: px - 0.6, y: py - 0.6),
                endPoint: UnitPoint(x: px + 0.6, y: py + 0.6)
            )
            .blendMode(.overlay)
            AngularGradient(colors: [.pink, .yellow, .green, .cyan, .purple, .pink], center: UnitPoint(x: px, y: py))
                .opacity(0.22 * strength)
                .blendMode(.colorDodge)
        }
        .opacity(0.25 + 0.75 * strength)
        .allowsHitTesting(false)
    }

    // MARK: Gestos

    private func tiltAngles(in size: CGSize) -> (x: Double, y: Double) {
        guard scale == 1 else { return (0, 0) }
        let dx = Double(drag.width / max(size.width, 1)) * maxTilt * 2.2
        let dy = Double(drag.height / max(size.height, 1)) * maxTilt * 2.2
        let x = max(min(-dy + deviceTilt.x, maxTilt), -maxTilt)
        let y = max(min(dx + deviceTilt.y, maxTilt), -maxTilt)
        return (x, y)
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isTouching {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { isTouching = true }
                }
                if scale > 1 {
                    pan = CGSize(width: lastPan.width + value.translation.width, height: lastPan.height + value.translation.height)
                } else {
                    withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.85)) { drag = value.translation }
                }
            }
            .onEnded { _ in
                lastPan = pan
                withAnimation(.spring(response: 0.55, dampingFraction: 0.55)) {
                    drag = .zero
                    isTouching = false
                }
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in scale = min(max(lastScale * value.magnification, 1), 4) }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1.01 { resetZoom() }
            }
    }

    private func toggleZoom() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            if scale > 1 { resetZoomValues() } else { scale = 2.2; lastScale = 2.2 }
        }
    }

    private func resetZoom() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { resetZoomValues() }
    }

    private func resetZoomValues() {
        scale = 1; lastScale = 1; pan = .zero; lastPan = .zero
    }

    private func close() {
        DiagnosticsLog.event("viewer close tapped")
        deviceTilt.stop()
        onClose()
    }
}
