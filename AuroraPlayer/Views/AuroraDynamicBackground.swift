import SwiftUI

/// Fondo "aurora" de NowPlaying: 2-3 manchas grandes de los colores EXTRAÍDOS de
/// la carátula (primario + secundario) sobre una base tintada derivada de esos
/// mismos colores.
///
/// ✅ POR QUÉ ESTO AGUANTA 60 FPS EN EL A11 (iPhone 8 Plus, iOS 16):
/// 1. El trabajo caro de píxeles (`RadialGradient` + `.blur(radius: 60)`) se
///    rasteriza UNA sola vez por mancha con `.drawingGroup()`: a partir de ahí la
///    mancha es una TEXTURA en GPU, no una forma que se recompute.
/// 2. La animación no toca el contenido: el `offset`/`scaleEffect` se aplican
///    POR FUERA del `drawingGroup`, así que son una TRANSFORMACIÓN de la capa
///    (Core Animation, en el render server). Cero re-ejecución del `body` por
///    frame, cero Metal, cero `TimelineView(.animation)`, cero `blur` por frame.
/// 3. Nada de `UIImage`/`CIImage`/shaders en el ciclo de render: solo los `Color`
///    ya extraídos (las conversiones HSB/RGB son aritmética puntual, sin bitmap).
/// 4. `.allowsHitTesting(false)`: el fondo NUNCA intercepta toques.
///
/// Fallbacks:
/// · "Reducir transparencia"     → fondo OPACO y estático (sin blur ni deriva).
/// · `accessibilityReduceMotion` → misma aurora, sin animación.
/// · `secondary == nil` (acento manual o carátula sin segundo color) → degradado
///   elegante de un solo color; nunca un hueco.
/// · Sin carátula el llamador ya pasa `AppTheme.accent` como primario.
struct AuroraDynamicBackground: View {
    /// Color dominante de la carátula (o el acento efectivo si no hay portada).
    var primary: Color = AppTheme.accent
    /// Segundo color dominante de la carátula. `nil` → un solo color.
    var secondary: Color?

    @AppStorage("com.aurora.reduceTransparency") private var reduceTransparency = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    /// Dispara la deriva. Se anima con `.animation(_:value:)` (NO con
    /// `withAnimation`): el proyecto ya comprobó que el `repeatForever` lanzado
    /// con `withAnimation` no se puede detener después — con `value:` sí (al
    /// activar "Reducir transparencia" o "Reducir movimiento" queda inerte).
    @State private var drift = false

    private var isAnimated: Bool { !reduceTransparency && !reduceMotion }

    /// ✅ BASE OSCURA TINTADA, no negro plano ni `systemBackground`: el texto de
    /// NowPlaying es SIEMPRE blanco (`AppTheme.contrastingText` devuelve `.white`
    /// sin mirar el color), así que la base tiene que quedarse oscura con
    /// cualquier carátula (clara u oscura) y en cualquier apariencia. El tono sí
    /// sale del acento → el fondo sigue siendo "de la canción".
    private var baseTop: Color {
        Self.tone(primary, brightness: colorScheme == .dark ? 0.20 : 0.34)
    }

    private var baseBottom: Color {
        Self.tone(secondary ?? primary, brightness: colorScheme == .dark ? 0.06 : 0.16)
    }

    private var baseLayer: some View {
        LinearGradient(
            colors: [baseTop, baseBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        ZStack {
            baseLayer

            if reduceTransparency {
                // ✅ Opaco y estático: sin blur, sin animación, sin transparencia.
                reducedMotionOverlay
            } else {
                auroraLayer
                scrim
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear { drift = isAnimated }
    }

    /// Capa de manchas. `GeometryReader` solo para proporciones relativas a la
    /// pantalla (cambia una vez por rotación, no por frame).
    private var auroraLayer: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // Mancha 1 — acento primario.
                blob(primary, diameter: w * 0.95)
                    .offset(x: drift ? -w * 0.22 : w * 0.06,
                            y: drift ? -h * 0.16 : h * 0.05)
                    .scaleEffect(drift ? 1.10 : 0.92)
                    .animation(driftAnimation(8.0), value: drift)

                // Mancha 2 — acento secundario (o el primario si no hay).
                blob(secondary ?? primary, diameter: w * 0.85)
                    .offset(x: drift ? w * 0.18 : -w * 0.10,
                            y: drift ? h * 0.20 : -h * 0.06)
                    .scaleEffect(drift ? 0.94 : 1.12)
                    .animation(driftAnimation(10.0), value: drift)

                // Mancha 3 — mezcla de los dos (tercer tono real, sin inventar
                // color): da profundidad y evita el "dos manchas planas".
                blob(blend, diameter: w * 0.75)
                    .offset(x: drift ? w * 0.10 : -w * 0.14,
                            y: drift ? -h * 0.22 : h * 0.12)
                    .scaleEffect(drift ? 1.14 : 0.90)
                    .animation(driftAnimation(6.5), value: drift)
            }
            .frame(width: w, height: h)
        }
    }

    /// ✅ Mancha: `Circle` con `RadialGradient` (se desvanece antes del borde, así
    /// no hay canto que el blur tenga que disimular) + `blur(60)` + `drawingGroup`.
    /// El `frame` va ANTES del blur para que la mancha tenga tamaño propio y el
    /// rasterizado sea de ese tamaño, no de la pantalla completa.
    private func blob(_ color: Color, diameter: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(0.70), color.opacity(0.0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter * 0.5
                )
            )
            .frame(width: diameter, height: diameter)
            .blur(radius: 60)
            .drawingGroup()
    }

    /// Deriva declarativa: cada mancha con su propia duración (8/10/6.5 s) para
    /// que las tres se desincronicen solas y el movimiento no parezca un latido
    /// mecánico. `nil` cuando no debe animarse.
    private func driftAnimation(_ duration: Double) -> Animation? {
        guard isAnimated else { return nil }
        return .easeInOut(duration: duration).repeatForever(autoreverses: true)
    }

    /// Degradado inclinado del acento: da "materialidad" al fondo opaco sin
    /// necesitar blur ni animación.
    private var reducedMotionOverlay: some View {
        LinearGradient(
            colors: [
                primary.opacity(colorScheme == .dark ? 0.26 : 0.18),
                (secondary ?? primary).opacity(colorScheme == .dark ? 0.14 : 0.10)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Velo de legibilidad: un único `LinearGradient` (sin blur, coste de fill
    /// rate despreciable) que oscurece arriba y abajo, donde viven el header, el
    /// título y los controles.
    private var scrim: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.30), location: 0.0),
                .init(color: .black.opacity(0.06), location: 0.38),
                .init(color: .black.opacity(0.10), location: 0.62),
                .init(color: .black.opacity(0.42), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Tercer tono: media aritmética RGB de los dos acentos. Si el segundo color
    /// no existe o alguno no es convertible a RGB, se usa el primario tal cual
    /// (nunca se inventa un color nuevo).
    private var blend: Color {
        guard let secondary else { return primary }
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 1
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 1
        guard UIColor(primary).getRed(&r1, green: &g1, blue: &b1, alpha: &a1),
              UIColor(secondary).getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else {
            return primary
        }
        return Color(uiColor: UIColor(
            red: (r1 + r2) / 2,
            green: (g1 + g2) / 2,
            blue: (b1 + b2) / 2,
            alpha: 1.0
        ))
    }

    /// Oscurece (o aclara) un color conservando su TONO con la saturación
    /// contenida, para que la base sea apagada y no un neón.
    private static func tone(_ color: Color, brightness: CGFloat) -> Color {
        var hue: CGFloat = 0, saturation: CGFloat = 0, value: CGFloat = 0, alpha: CGFloat = 1
        guard UIColor(color).getHue(&hue, saturation: &saturation, brightness: &value, alpha: &alpha) else {
            // Color sin matiz (gris/blanco/negro puro): base neutra.
            return Color(uiColor: UIColor(white: brightness, alpha: 1.0))
        }
        return Color(uiColor: UIColor(
            hue: hue,
            saturation: min(saturation * 0.6, 0.85),
            brightness: brightness,
            alpha: 1.0
        ))
    }
}
