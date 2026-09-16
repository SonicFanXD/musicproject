import SwiftUI

// MARK: - Shared CADisplayLink Helpers
// Clases utilitarias compartidas para CADisplayLink en todas las vistas

/// Wrapper para CADisplayLink con handler sin parámetros
final class DisplayLinkTarget: NSObject {
    private let handler: (CFTimeInterval) -> Void

    init(handler: @escaping (CFTimeInterval) -> Void) {
        self.handler = handler
        super.init()
    }

    @objc func fire(displayLink: CADisplayLink) {
        handler(displayLink.timestamp)
    }
}

/// Wrapper para CADisplayLink con handler simple (sin parámetros)
final class SimpleDisplayLinkTarget: NSObject {
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
        super.init()
    }

    @objc func fire(displayLink: CADisplayLink) {
        handler()
    }
}

// MARK: - Conditional DrawingGroup Modifier
/// Aplica drawingGroup() solo cuando se especifica, para optimizar rendimiento en A11
struct DrawingGroupModifier: ViewModifier {
    let shouldUse: Bool

    func body(content: Content) -> some View {
        if shouldUse {
            content.drawingGroup()
        } else {
            content
        }
    }
}
