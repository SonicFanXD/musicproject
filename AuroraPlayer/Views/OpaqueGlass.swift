import SwiftUI

// Liquid glass style - clean, no glowing borders, optimized for performance
// ✅ FIX REDUCIR TRANSPARENCIA (reactivo): los 4 modificadores de vidrio leían
// UserDefaults en tiempo de body (`static var` computada, sin @AppStorage), así
// que togglear el ajuste en Ajustes NO repintaba los elementos ya montados y la
// app quedaba medio desincronizada (el design system ya era reactivo vía
// @AppStorage). Ahora la superficie vive en un ViewModifier con @AppStorage: al
// cambiar el ajuste, cada vista que use uno de los 4 se re-evalúa al instante.
// La firma externa es IDÉNTICA (nombre, parámetros y valores por defecto); solo
// cambia la implementación, que pasa a ser UNA sola para los 4 (solo cambia la
// Shape) en vez de cuatro copias del mismo body.
extension View {
    func nativeGlass(cornerRadius: CGFloat = 12) -> some View {
        modifier(NativeGlassModifier(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
    }

    func nativeGlassCapsule() -> some View {
        modifier(NativeGlassModifier(shape: Capsule()))
    }

    func nativeThinGlass(cornerRadius: CGFloat = 12) -> some View {
        modifier(NativeGlassModifier(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
    }

    func enhancedGlass(cornerRadius: CGFloat = 16) -> some View {
        modifier(NativeGlassModifier(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
    }
}

// ✅ AURORA DESIGN: superficie de vidrio del sistema, reactiva a "Reducir
// transparencia": activo → superficie OPACA del sistema (menos blur, más
// rendimiento en el A11), inactivo → .ultraThinMaterial, como hasta ahora.
private struct NativeGlassModifier<S: Shape>: ViewModifier {
    @AppStorage("com.aurora.reduceTransparency") private var reduceTransparency = false
    let shape: S

    func body(content: Content) -> some View {
        content.background {
            Group {
                if reduceTransparency {
                    shape.fill(Color(UIColor.secondarySystemBackground))
                } else {
                    shape.fill(.ultraThinMaterial)
                }
            }
        }
    }
}