import SwiftUI

/// Contador de FPS ultravisible: se muestra en la esquina inferior derecha,
/// justo encima del player bar (lejos de los status del iPhone donde era
/// difícil de ver). Cambia de color según el rendimiento:
/// verde ≥50fps, amarillo 30-49fps, rojo <30fps.
struct FPSCounter: View {
    @State private var fps: Int = 0
    @State private var frameCount: Int = 0
    @State private var lastTimestamp: CFTimeInterval = 0
    @State private var displayLink: CADisplayLink?

    // ✅ Color según rendimiento
    private var fpsColor: Color {
        if fps >= 50 { return .green }
        if fps >= 30 { return .yellow }
        return .red
    }

    var body: some View {
        HStack(spacing: 6) {
            // ✅ Dot con color dinámico de rendimiento (no solo verde)
            Circle()
                .fill(fpsColor)
                .frame(width: 7, height: 7)
                .shadow(color: fpsColor.opacity(0.8), radius: 4)

            // ✅ Número grande y claro (monospaced para que no vibre)
            Text("\(fps)")
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .monospacedDigit()

            Text("FPS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(fpsColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(Color.black.opacity(0.75))
                .overlay {
                    Capsule()
                        .strokeBorder(fpsColor.opacity(0.5), lineWidth: 1.2)
                }
        }
        .shadow(color: .black.opacity(0.5), radius: 6, x: 0, y: 3)
        .animation(.easeInOut(duration: 0.2), value: fps)
        .onAppear {
            startTracking()
        }
        .onDisappear {
            stopTracking()
        }
    }

    private func startTracking() {
        displayLink = CADisplayLink(target: DisplayLinkTarget { timestamp in
            if lastTimestamp == 0 {
                lastTimestamp = timestamp
            }
            frameCount += 1
            let elapsed = timestamp - lastTimestamp
            if elapsed >= 1.0 {
                self.fps = Int(Double(frameCount) / elapsed)
                self.frameCount = 0
                self.lastTimestamp = timestamp
            }
        }, selector: #selector(DisplayLinkTarget.fire(displayLink:)))
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopTracking() {
        displayLink?.invalidate()
        displayLink = nil
    }
}

/// Wrapper para usar CADisplayLink con SwiftUI
class DisplayLinkTarget: NSObject {
    private let handler: (CFTimeInterval) -> Void

    init(handler: @escaping (CFTimeInterval) -> Void) {
        self.handler = handler
        super.init()
    }

    @objc func fire(displayLink: CADisplayLink) {
        handler(displayLink.timestamp)
    }
}

/// Overlay que posiciona el FPS counter en la esquina INFERIOR DERECHA,
/// justo encima del player bar (área claramente visible sin tapar nada).
struct FPSCounterOverlay: View {
    let showFPS: Bool

    var body: some View {
        if showFPS {
            GeometryReader { geometry in
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        FPSCounter()
                            // ✅ 76pt = altura del player bar + padding inferior
                            .padding(.trailing, 14)
                            .padding(.bottom, geometry.safeAreaInsets.bottom + 82)
                    }
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .transition(.opacity.combined(with: .scale(scale: 0.85)))
        }
    }
}