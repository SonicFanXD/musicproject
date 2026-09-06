import SwiftUI

/// Contador de FPS que se muestra en la esquina superior derecha,
/// debajo de los status del iPhone (batería, wifi, etc.).
struct FPSCounter: View {
    @State private var fps: Int = 0
    @State private var frameCount: Int = 0
    @State private var lastTimestamp: CFTimeInterval = 0
    @State private var displayLink: CADisplayLink?
    
    var body: some View {
        Text("\(fps) FPS")
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(.green)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background {
                Capsule()
                    .fill(Color.black.opacity(0.6))
            }
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

/// Overlay que posiciona el FPS counter en la esquina superior derecha,
/// respetando los safe areas del iPhone (island, notch, etc.).
struct FPSCounterOverlay: View {
    let showFPS: Bool
    
    var body: some View {
        if showFPS {
            GeometryReader { geometry in
                VStack {
                    HStack {
                        Spacer()
                        FPSCounter()
                            .padding(.trailing, 8)
                    }
                    Spacer()
                }
                .padding(.top, geometry.safeAreaInsets.top + 4)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}