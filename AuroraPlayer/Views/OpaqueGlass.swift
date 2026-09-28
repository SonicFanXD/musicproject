import SwiftUI

// Liquid glass style - clean, no glowing borders, optimized for performance
// ✅ FIX REDUCIR TRANSPARENCIA (reactivo): los modificadores de vidrio leían
// UserDefaults en tiempo de body (`static var` computada, sin @AppStorage), así
// que togglear el ajuste en Ajustes NO repintaba los elementos ya montados y la
// app quedaba medio desincronizada (el design system ya era reactivo vía
// @AppStorage). Ahora la superficie vive en una vista con @AppStorage: al
// cambiar el ajuste, cada vista que la use se re-evalúa al instante.
// La firma externa de los 3 restantes es IDÉNTICA (nombre, parámetros y valores
// por defecto) y los 3 comparten la misma implementación.
// ✅ FASE C1: `nativeThinGlass` eliminado (tenía 0 call sites en el proyecto).
extension View {
    func nativeGlass(cornerRadius: CGFloat = 12) -> some View {
        modifier(NativeGlassModifier(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
    }

    func nativeGlassCapsule() -> some View {
        modifier(NativeGlassModifier(shape: Capsule()))
    }

    func enhancedGlass(cornerRadius: CGFloat = 16) -> some View {
        modifier(NativeGlassModifier(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
    }
}

// ✅ AURORA DESIGN: superficie de vidrio del sistema, reactiva a "Reducir
// transparencia": activo → superficie OPACA del sistema (menos blur, más
// rendimiento en el A11), inactivo → .ultraThinMaterial, como hasta ahora.
// Es la ÚNICA implementación del vidrio y la consumen los 3 modificadores de
// arriba y `auroraGlass()` (para un Shape suelto: círculos, cápsulas…).
private struct NativeGlassSurface<S: Shape>: View {
    @AppStorage("com.aurora.reduceTransparency") private var reduceTransparency = false
    let shape: S

    var body: some View {
        Group {
            if reduceTransparency {
                shape.fill(Color(UIColor.secondarySystemBackground))
            } else {
                shape.fill(.ultraThinMaterial)
            }
        }
    }
}

private struct NativeGlassModifier<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        content.background { NativeGlassSurface(shape: shape) }
    }
}

extension Shape {
    /// ✅ AURORA DESIGN: relleno de vidrio del sistema para CUALQUIER Shape
    /// (Círculo, Cápsula, RoundedRectangle…), reactivo a "Reducir
    /// transparencia". Se usa donde no encaja ninguno de los 3 modificadores
    /// (p. ej. una capa dentro de un ZStack, o un `.fill` de material a pelo):
    /// sustituye EXACTAMENTE al `.fill` del material, sin tocar geometría.
    func auroraGlass() -> some View {
        NativeGlassSurface(shape: self)
    }
}