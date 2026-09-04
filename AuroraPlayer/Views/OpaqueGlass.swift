import SwiftUI

// Simplificado para máxima compatibilidad con iOS 16 y rendimiento
extension View {
    func opaqueGlass(
        cornerRadius: CGFloat = 20,
        tint: Color = .white,
        tintIntensity: Double = 0.05,
        strokeIntensity: Double = 0.30,
        isPressed: Bool = false
    ) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.secondary.opacity(0.1))
        )
    }

    func opaqueGlassCapsule(
        tint: Color = .white,
        tintIntensity: Double = 0.05,
        strokeIntensity: Double = 0.30,
        isPressed: Bool = false
    ) -> some View {
        self.background(
            Capsule()
                .fill(Color.secondary.opacity(0.1))
        )
    }
}
