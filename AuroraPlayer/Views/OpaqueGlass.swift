import SwiftUI

// Liquid glass style - clean, no glowing borders, optimized for performance
extension View {
    // ✅ "Reducir transparencia": cuando está activo, los materiales de vidrio
    // se sustituyen por fondos opacos (menos blur, más rendimiento).
    private static var useOpaqueGlass: Bool {
        UserDefaults.standard.bool(forKey: "com.aurora.reduceTransparency")
    }

    private static var glassStyle: AnyShapeStyle {
        useOpaqueGlass
            ? AnyShapeStyle(Color(UIColor.secondarySystemBackground))
            : AnyShapeStyle(.ultraThinMaterial)
    }

    func nativeGlass(cornerRadius: CGFloat = 12) -> some View {
        self.background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Self.glassStyle)
        }
    }

    func nativeGlassCapsule() -> some View {
        self.background {
            Capsule()
                .fill(Self.glassStyle)
        }
    }

    func nativeThinGlass(cornerRadius: CGFloat = 12) -> some View {
        self.background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Self.glassStyle)
        }
    }

    func enhancedGlass(cornerRadius: CGFloat = 16) -> some View {
        self.background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Self.glassStyle)
        }
    }
}