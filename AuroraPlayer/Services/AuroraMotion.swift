import SwiftUI
import UIKit
import CoreText

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
    /// El ripple se puede desactivar en controles donde el scale ya basta.
    var showsRipple: Bool = true
    var rippleColor: Color = M3EColor.onSurface.opacity(0.12)

    func makeBody(configuration: Configuration) -> some View {
        rippleLabel(configuration)
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .opacity(configuration.isPressed ? pressedOpacity : 1.0)
            .animation(AuroraMotion.spatialFast, value: configuration.isPressed)
    }

    @ViewBuilder
    private func rippleLabel(_ configuration: ButtonStyleConfiguration) -> some View {
        if showsRipple {
            configuration.label
                .auroraRipple(cornerRadius: 16, color: rippleColor)
        } else {
            configuration.label
        }
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

// MARK: - Roboto (registro defensivo + fallback)

/// ✅ GOLPE FINAL: Roboto se registra DOS veces, por si `UIAppFonts` no basta:
/// al primer uso de cualquier rol se recorre el bundle y se registra cada .ttf
/// con CoreText. Si el archivo no llegó al bundle (o el nombre no coincide),
/// `font(_:size:weight:)` cae a `Font.system` SIN `.rounded`, que es el
/// fallback que pide el contrato visual.
private enum RobotoFont {
    /// ✅ GOLPE FINAL: registrar TODOS los .ttf del bundle recorriendo sus
    /// recursos, sin asumir si Xcode los copia a la raíz o dentro de una
    /// subcarpeta. Esto elimina la causa real de que Roboto no se viera: el
    /// archivo existía, pero iOS no lo encontraba en la ruta esperada.
    private static let registration: Void = {
        guard let resourceURL = Bundle.main.resourceURL,
              let enumerator = FileManager.default.enumerator(
                at: resourceURL,
                includingPropertiesForKeys: nil
              )
        else { return }

        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "ttf" else { continue }
            _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()

    static func font(_ name: String, size: CGFloat, weight: Font.Weight) -> Font {
        _ = registration
        if UIFont(name: name, size: size) != nil {
            return .custom(name, size: size)
        }
        // Fallback explícito: fuente del sistema SIN `.rounded`, que es el
        // último recurso si el .ttf no llegó al bundle.
        return .system(size: size, weight: weight)
    }
}

// ✅ Escala tipográfica Material 3 (15 roles) + variantes emphasized.
// Roboto es la fuente de Android; el énfasis usa Medium (500), no Bold.
struct M3ETypography {
    // Display
    static let displayLarge = RobotoFont.font("Roboto-Regular", size: 57, weight: .regular)
    static let displayMedium = RobotoFont.font("Roboto-Regular", size: 45, weight: .regular)
    static let displaySmall = RobotoFont.font("Roboto-Regular", size: 36, weight: .regular)

    // Headline
    static let headlineLarge = RobotoFont.font("Roboto-Regular", size: 32, weight: .regular)
    static let headlineMedium = RobotoFont.font("Roboto-Regular", size: 28, weight: .regular)
    static let headlineSmall = RobotoFont.font("Roboto-Regular", size: 24, weight: .regular)

    // Title
    static let titleLarge = RobotoFont.font("Roboto-Regular", size: 22, weight: .regular)
    static let titleMedium = RobotoFont.font("Roboto-Medium", size: 16, weight: .medium)
    static let titleSmall = RobotoFont.font("Roboto-Medium", size: 14, weight: .medium)

    // Body
    static let bodyLarge = RobotoFont.font("Roboto-Regular", size: 16, weight: .regular)
    static let bodyMedium = RobotoFont.font("Roboto-Regular", size: 14, weight: .regular)
    static let bodySmall = RobotoFont.font("Roboto-Regular", size: 12, weight: .regular)

    // Label
    static let labelLarge = RobotoFont.font("Roboto-Medium", size: 14, weight: .medium)
    static let labelMedium = RobotoFont.font("Roboto-Medium", size: 12, weight: .medium).monospacedDigit()
    static let labelSmall = RobotoFont.font("Roboto-Medium", size: 11, weight: .medium).monospacedDigit()

    // Emphasized (M3E: Medium sobre el baseline Regular)
    static let displayTitle = RobotoFont.font("Roboto-Bold", size: 36, weight: .bold)
    static let headlineLargeEmphasized = RobotoFont.font("Roboto-Medium", size: 32, weight: .medium)
    static let headlineSmallEmphasized = RobotoFont.font("Roboto-Medium", size: 24, weight: .medium)
    static let titleLargeEmphasized = RobotoFont.font("Roboto-Medium", size: 22, weight: .medium)
    static let titleMediumEmphasized = RobotoFont.font("Roboto-Medium", size: 16, weight: .medium)
    static let labelLargeEmphasized = RobotoFont.font("Roboto-Medium", size: 14, weight: .medium)

    // Datos numéricos y tiempos
    static let labelLargeNumeric = RobotoFont.font("Roboto-Medium", size: 14, weight: .medium).monospacedDigit()
    static let trackSubtitle = RobotoFont.font("Roboto-Regular", size: 10, weight: .regular)
        .monospacedDigit()
    static let timeDisplay = RobotoFont.font("Roboto-Medium", size: 20, weight: .medium)
        .monospacedDigit()
    static let timeDisplayCompact = RobotoFont.font("Roboto-Medium", size: 13, weight: .medium)
        .monospacedDigit()
}

/// Un rol M3 completo: fuente + altura de línea + tracking. Las vistas que
/// necesitan la especificación completa usan estos tokens; las que solo
/// necesitan el `Font` siguen usando `M3ETypography`.
struct M3ETextStyle {
    let font: Font
    let lineHeight: CGFloat
    let tracking: CGFloat
}

extension M3ETextStyle {
    static let displayLarge = M3ETextStyle(font: M3ETypography.displayLarge, lineHeight: 64, tracking: -0.25)
    static let displayMedium = M3ETextStyle(font: M3ETypography.displayMedium, lineHeight: 52, tracking: 0)
    static let displaySmall = M3ETextStyle(font: M3ETypography.displaySmall, lineHeight: 44, tracking: 0)
    static let headlineLarge = M3ETextStyle(font: M3ETypography.headlineLarge, lineHeight: 40, tracking: 0)
    static let headlineMedium = M3ETextStyle(font: M3ETypography.headlineMedium, lineHeight: 36, tracking: 0)
    static let headlineSmall = M3ETextStyle(font: M3ETypography.headlineSmall, lineHeight: 32, tracking: 0)
    static let titleLarge = M3ETextStyle(font: M3ETypography.titleLarge, lineHeight: 28, tracking: 0)
    static let titleMedium = M3ETextStyle(font: M3ETypography.titleMedium, lineHeight: 24, tracking: 0.15)
    static let titleSmall = M3ETextStyle(font: M3ETypography.titleSmall, lineHeight: 20, tracking: 0.1)
    static let bodyLarge = M3ETextStyle(font: M3ETypography.bodyLarge, lineHeight: 24, tracking: 0.5)
    static let bodyMedium = M3ETextStyle(font: M3ETypography.bodyMedium, lineHeight: 20, tracking: 0.25)
    static let bodySmall = M3ETextStyle(font: M3ETypography.bodySmall, lineHeight: 16, tracking: 0.4)
    static let labelLarge = M3ETextStyle(font: M3ETypography.labelLarge, lineHeight: 20, tracking: 0.1)
    static let labelMedium = M3ETextStyle(font: M3ETypography.labelMedium, lineHeight: 16, tracking: 0.5)
    static let labelSmall = M3ETextStyle(font: M3ETypography.labelSmall, lineHeight: 16, tracking: 0.5)
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

    // MARK: - Resortes oficiales M3E

    // ✅ FASE 2: se eliminan quick / normal / emphasized / slow / lyricLine.
    // Cualquier animación de la app es uno de estos tres tokens EXPRESIVOS
    // (el esquema por defecto de M3E):
    //  · spatialDefault → posición, tamaño y forma (rebote suave).
    //  · spatialFast    → toques rápidos (rebote más notable).
    //  · effectsDefault → opacidad y color (sin rebote).
    //
    // ✅ REMAKE: M3E define DOS esquemas. El expresivo (arriba) es el de la
    // marca y el que usan cards, chips, héroes y transiciones. El ESTÁNDAR
    // (abajo) es utilitario: misma rigidez, ζ = 1.0, sin overshoot, para
    // elementos donde un rebote distraería (listas densas, ajustes, barras
    // de navegación). Ambos comparten `m3eSpring`, así que la física es la
    // misma y solo cambia la amortiguación.
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

    // MARK: - Esquema ESTÁNDAR (utilitario, sin overshoot)

    /// Posición/tamaño en contextos utilitarios: misma rigidez que el
    /// expresivo pero críticamente amortiguado (ζ = 1.0).
    static let standardSpatialDefault = m3eSpring(stiffness: 380, dampingRatio: 1.0)

    /// Toques en contextos utilitarios: rápido y sin rebote.
    static let standardSpatialFast = m3eSpring(stiffness: 800, dampingRatio: 1.0)

    /// Efectos utilitarios: idéntico al expresivo (ya es ζ = 1.0).
    static let standardEffectsDefault = effectsDefault

    // MARK: - Curvas M3 (5 familias × 3 duraciones)

    // M3 combina curvas de easing con duraciones cortas/medias/largas. Las
    // funciones devuelven una `Animation` nueva en cada llamada para que el
    // llamador pueda encadenar `.delay` sin compartir estado.
    private static func m3Curve(
        _ x1: Double,
        _ y1: Double,
        _ x2: Double,
        _ y2: Double,
        duration: Double
    ) -> Animation {
        .timingCurve(x1, y1, x2, y2, duration: duration)
    }

    static let emphasizedDecelerate = m3Curve(0.05, 0.7, 0.1, 1.0, duration: 0.30)
    static let emphasizedAccelerate = m3Curve(0.3, 0.0, 0.8, 0.15, duration: 0.30)
    static let decelerate = m3Curve(0.0, 0.0, 0.0, 1.0, duration: 0.30)
    static let accelerate = m3Curve(0.3, 0.0, 1.0, 1.0, duration: 0.30)
    static let linear = Animation.linear(duration: 0.30)

    static func emphasizedDecelerateShort() -> Animation {
        m3Curve(0.05, 0.7, 0.1, 1.0, duration: 0.20)
    }

    static func emphasizedDecelerateMedium() -> Animation {
        m3Curve(0.05, 0.7, 0.1, 1.0, duration: 0.30)
    }

    static func emphasizedDecelerateLong() -> Animation {
        m3Curve(0.05, 0.7, 0.1, 1.0, duration: 0.50)
    }

    static func emphasizedAccelerateShort() -> Animation {
        m3Curve(0.3, 0.0, 0.8, 0.15, duration: 0.20)
    }

    static func emphasizedAccelerateMedium() -> Animation {
        m3Curve(0.3, 0.0, 0.8, 0.15, duration: 0.30)
    }

    static func emphasizedAccelerateLong() -> Animation {
        m3Curve(0.3, 0.0, 0.8, 0.15, duration: 0.50)
    }

    static func decelerateShort() -> Animation {
        m3Curve(0.0, 0.0, 0.0, 1.0, duration: 0.20)
    }

    static func decelerateMedium() -> Animation {
        m3Curve(0.0, 0.0, 0.0, 1.0, duration: 0.30)
    }

    static func decelerateLong() -> Animation {
        m3Curve(0.0, 0.0, 0.0, 1.0, duration: 0.50)
    }

    static func accelerateShort() -> Animation {
        m3Curve(0.3, 0.0, 1.0, 1.0, duration: 0.20)
    }

    static func accelerateMedium() -> Animation {
        m3Curve(0.3, 0.0, 1.0, 1.0, duration: 0.30)
    }

    static func accelerateLong() -> Animation {
        m3Curve(0.3, 0.0, 1.0, 1.0, duration: 0.50)
    }

    static func linearShort() -> Animation { .linear(duration: 0.20) }
    static func linearMedium() -> Animation { .linear(duration: 0.30) }
    static func linearLong() -> Animation { .linear(duration: 0.50) }
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