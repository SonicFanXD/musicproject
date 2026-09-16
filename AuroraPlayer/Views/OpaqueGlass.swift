import SwiftUI

// Liquid glass style - clean, no glowing borders, optimized for performance
extension View {
    // ✅ "Reducir transparencia": cuando está activo, los materiales de vidrio
    // se sustituyen por fondos opacos (menos blur, más rendimiento).
    private static var useOpaqueGlass: Bool {
        UserDefaults.standard.bool(forKey: "com.aurora.reduceTransparency")
    }
    
    // ✅ OPTIMIZACIÓN A11: usar material menos costoso en dispositivos A11
    private static var glassStyle: AnyShapeStyle {
        if useOpaqueGlass {
            return AnyShapeStyle(Color(UIColor.secondarySystemBackground))
        }
        
        // En dispositivos A11, usar regularMaterial en lugar de ultraThinMaterial
        // para reducir el costo de blur sin perder el efecto visual
        if !HardwareCapabilities.shared.useHighQualityBlur {
            return AnyShapeStyle(.regularMaterial)
        }
        
        return AnyShapeStyle(.ultraThinMaterial)
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