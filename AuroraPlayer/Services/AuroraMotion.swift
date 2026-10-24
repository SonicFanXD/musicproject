import SwiftUI

// ══════════════════════════════════════════════════════════════════════════
// AURORA MOTION — gramática de movimiento Material 3 Expressive (M3E),
// implementada con APIs nativas de SwiftUI (iOS 16, sin dependencias).
// ══════════════════════════════════════════════════════════════════════════

// MARK: - Top-level structs (accessible from entire app)

// MARK: - Press feedback (escala + opacidad con física M3E)

// ✅ Feedback de presión elástico. Es el MISMO `PressableButtonStyle` que ya
// usaba toda la app (30+ call sites) con dos mejoras, sin romper ninguno:
//  1. La curva pasa a `AuroraMotion.spatialFast` (antes era un spring a mano con
//     otro apretón: ahora TODO lo pulsable de la app comparte la misma
//     física, que es lo que hace que una app se sienta "de un sitio").
//  2. Nuevo parámetro opcional `pressedOpacity`: M3E apaga levemente la
//     superficie al presionar, lo que hace la pulsación legible sobre la
//     portada sin añadir ni un render pass (opacidad = capa del sistema).
// Sin haptics aquí dentro a propósito: los botones ya disparan `Haptics` en
// sus acciones; duplicarlo haría doble Taptic en cada toque.
struct PressableButtonStyle: ButtonStyle {
    let scale: CGFloat
    var pressedOpacity: Double = 1.0

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .opacity(configuration.isPressed ? pressedOpacity : 1.0)
            .animation(AuroraMotion.spatialFast, value: configuration.isPressed)
    }
}

// MARK: - Morphing shape (M3E: formas que se transforman)

// ✅ Forma animable que interpola entre círculo, squircle y píldora corta.
// El morph se resuelve interpolando SU PROPIO `animatableData` (radio + ancho).
// Se mantiene a nivel global para estar disponible en toda la app (NowPlaying, PlayerBar, etc.).
struct AuroraMorphShape: Shape, Animatable {
    var cornerRadiusRatio: CGFloat
    var widthRatio: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(cornerRadiusRatio, widthRatio) }
        set {
            cornerRadiusRatio = newValue.first
            widthRatio = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let width = side * widthRatio
        let radius = min(width, side) * cornerRadiusRatio
        return Path(roundedRect: CGRect(x: rect.midX - width / 2, y: rect.minY, width: width, height: side), cornerRadius: radius, style: .continuous)
    }
}

// MARK: - Emphasized typography (M3E type scale)

// ✅ Tokens de tipografía enfática Material 3 Expressive.
// Cada rol define tamaño (pt), peso y tracking para iOS 16 en hardware limitado.
// Estos valores están calibrados al vocabulario oficial de M3E y no deben
// modificarse sin consultar las guías de diseño de Google.
struct M3ETypography {
    // Título grande enfatizado: usado para el título de la canción en NowPlaying
    // y encabezados principales de sección.
    // ✅ FASE 2: peso "emphasized" = un paso por encima del baseline M3
    // (medium 500) → semibold 600. El tamaño y la altura de línea no cambian.
    static let titleLargeEmphasized: Font = .system(size: 22, weight: .semibold, design: .rounded)

    // Título pequeño enfatizado: usado para títulos de categoría en ContentView
    // y otros encabezados de sección medianos.
    static let headlineSmallEmphasized: Font = .system(size: 24, weight: .semibold, design: .rounded)

    // Etiqueta grande enfatizada: usado para texto de información secundaria,
    // como artista/álbum en NowPlaying y datos de pista.
    static let labelLargeEmphasized: Font = .system(size: 14, weight: .semibold, design: .rounded)

    // Subtítulo de pista: usado para información de calidad y route display.
    static let trackSubtitle: Font = .system(size: 10, weight: .regular)
        .monospacedDigit()

    // Texto de tiempo (formato mm:ss): siempre monospaced para alineación perfecta.
    static let timeDisplay: Font = .system(size: 20, weight: .medium)
        .monospacedDigit()
}

// MARK: - Morphing shape (M3E: formas que se transforman)

// ✅ Forma para CHIPS seleccionables que interpola SOLO el radio: rectángulo
// redondeado ↔ cápsula. El chip conserva todo su ancho (`rect`), así que el
// morph no mueve el layout ni cambia el tamaño del texto.
// Por qué `animatableData` y no `matchedGeometryEffect`: este último obliga a
// compartir un `Namespace` y re-instancia la jerarquía, lo que en un
// `ScrollView` horizontal produce el típico cross-fade entre el chip antiguo
// y el nuevo (y en el A11 añade trabajo por frame). Aquí cada chip interpola
// SU propia forma: cero coordinación global, cero vistas extra.
struct AuroraMorphChipShape: Shape, InsettableShape {
    /// Radio objetivo. Se acota a `min(ancho, alto) / 2`: pidiendo el alto/2 el
    /// chip se vuelve cápsula perfecta; con cualquier valor menor, esquinas M3E.
    var cornerRadius: CGFloat
    var insetAmount: CGFloat = 0

    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let box = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let radius = min(cornerRadius, min(box.width, box.height) / 2)
        return Path(roundedRect: box, cornerRadius: max(0, radius), style: .continuous)
    }

    func inset(by amount: CGFloat) -> AuroraMorphChipShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

// ══════════════════════════════════════════════════════════════════════════
// MARK: - AuroraMotion: contenedor principal de tokens M3E
// Solo variables estáticas (resortes) y shapes internas.
// ══════════════════════════════════════════════════════════════════════════

enum AuroraMotion {

    // MARK: - Tokens oficiales M3E (SOLO estos tres)

    // ✅ FASE 2: se eliminan quick / normal / emphasized / slow / lyricLine.
    // Cualquier animación de la app es uno de estos tres tokens:
    //  · spatialDefault → posición, tamaño y forma (rebote suave).
    //  · spatialFast    → toques rápidos (rebote más notable).
    //  · effectsDefault → opacidad y color (sin rebote).
    // Los pulsos continuos NO son tokens: los genera `TimelineView` con la
    // fecha de cada frame (ver `AuroraEqualizerBars`), nunca `repeatForever`.

    // ✅ FASE 1 (bucle de animaciones) — ESTA ERA LA CAUSA REAL DEL "BUCLE":
    // `Animation.interpolatingSpring(mass:stiffness:damping:)` espera el
    // COEFICIENTE de amortiguación (N·s/m), NO la razón de amortiguación.
    // Pasarle 0.8 (la razón que especifica M3E) con stiffness 380 deja el
    // sistema prácticamente sin freno: oscila durante decenas de segundos y
    // cada transición de vista parece no terminar nunca. El coeficiente
    // correcto es c = 2 · ζ · √(k · m). Convertimos la razón oficial de M3E
    // al coeficiente que SwiftUI necesita, sin cambiar el comportamiento
    // percibido (ζ 0.8 = rebote suave; ζ 1.0 = sin overshoot).
    private static func m3eSpring(stiffness: Double, dampingRatio: Double) -> Animation {
        let dampingCoefficient = 2 * dampingRatio * stiffness.squareRoot()
        return .interpolatingSpring(
            mass: 1,
            stiffness: stiffness,
            damping: dampingCoefficient,
            initialVelocity: 0
        )
    }

    /// ζ = 0.8 → rebote suave y acotado (~0.6 s). Posición, tamaño y forma.
    static let spatialDefault = m3eSpring(stiffness: 380, dampingRatio: 0.8)

    /// ζ = 0.6 → rebote más notable, para toques. Nunca llega a "vibrar".
    static let spatialFast = m3eSpring(stiffness: 800, dampingRatio: 0.6)

    /// ζ = 1.0 → críticamente amortiguado: opacidad y color, sin overshoot.
    static let effectsDefault = m3eSpring(stiffness: 1600, dampingRatio: 1.0)

    // ⚠️ Compatibilidad TEMPORAL con el commit de Fase 1: las vistas aún
    // referencian estos nombres. Se eliminan en el commit de Fase 2, cuando
    // todos los call sites ya usan los tres tokens de arriba.
    static let quick = spatialFast
    static let normal = spatialDefault
    static let emphasized = spatialDefault
    static let slow = spatialDefault
    static let lyricLine = spatialDefault
}

// ══════════════════════════════════════════════════════════════════════════
// MARK: - Indicadores continuos SIN `repeatForever`
// ══════════════════════════════════════════════════════════════════════════

// ✅ FASE 1. Antes cada barra del ecualizador arrancaba un `repeatForever` con
// `withAnimation`/`.animation(value:)`; en listas (y con el TimelineView de la
// barra ondulada en la misma jerarquía) eso deja transacciones rearmándose en
// cada re-render y la vista no termina de asentarse. Aquí la fase sale de la
// fecha de cada frame: no hay @State que rearmar, no hay bucle que cancelar y
// al pausar / pasar a segundo plano el TimelineView deja de pedir frames.
struct AuroraEqualizerBars: View {
    var color: Color = AppTheme.accent
    var isPlaying: Bool
    var barWidth: CGFloat = 2.5
    var spacing: CGFloat = 2.5
    var minHeight: CGFloat = 5
    var maxHeight: CGFloat = 13
    var height: CGFloat = 14

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isActive: Bool {
        isPlaying && scenePhase == .active && !reduceMotion
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                for index in 0..<3 {
                    let phase = t * 7.0 + Double(index) * 1.9
                    let level = isActive ? (sin(phase) * 0.5 + 0.5) : 0.0
                    let barHeight = minHeight + (maxHeight - minHeight) * CGFloat(level)
                    let rect = CGRect(
                        x: CGFloat(index) * (barWidth + spacing),
                        y: (size.height - barHeight) / 2,
                        width: barWidth,
                        height: barHeight
                    )
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: barWidth / 2),
                        with: .color(color)
                    )
                }
            }
        }
        .frame(width: barWidth * 3 + spacing * 2, height: height)
        .accessibilityHidden(true)
    }
}