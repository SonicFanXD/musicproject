import SwiftUI

// ══════════════════════════════════════════════════════════════════════════
// AURORA MOTION — gramática de movimiento Material 3 Expressive (M3E),
// implementada con APIs nativas de SwiftUI (iOS 16, sin dependencias).
// ══════════════════════════════════════════════════════════════════════════

// MARK: - Top-level structs (accessible from entire app)

// MARK: - Press feedback (escala + opacidad con física M3E)

// ✅ Feedback de presión elástico. Es el MISMO `PressableButtonStyle` que ya
// usaba toda la app (30+ call sites) con dos mejoras, sin romper ninguno:
//  1. La curva pasa a `AuroraMotion.quick` (antes era un spring a mano con
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
            .animation(AuroraMotion.quick, value: configuration.isPressed)
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
    static let titleLargeEmphasized: Font = .system(size: 22, weight: .medium, design: .rounded)

    // Título pequeño enfatizado: usado para títulos de categoría en ContentView
    // y otros encabezados de sección medianos.
    static let headlineSmallEmphasized: Font = .system(size: 24, weight: .medium, design: .rounded)

    // Etiqueta grande enfatizada: usado para texto de información secundaria,
    // como artista/álbum en NowPlaying y datos de pista.
    static let labelLargeEmphasized: Font = .system(size: 14, weight: .medium, design: .rounded)

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

    // MARK: - Motion tokens (interpolatingSpring por defecto)

// M3E "spatialDefault": movimiento con rebote suave (stiffness 380, damping 0.8).
    static let spatialDefault = Animation.interpolatingSpring(mass: 1, stiffness: 380, damping: 0.8, initialVelocity: 0)

// M3E "spatialFast": rebote más notable, para toques (stiffness 800, damping 0.6).
    static let spatialFast = Animation.interpolatingSpring(mass: 1, stiffness: 800, damping: 0.6, initialVelocity: 0)

// M3E "effectsDefault": cambios de opacidad/color sin rebote (stiffness 1600, damping 1.0).
    static let effectsDefault = Animation.interpolatingSpring(mass: 1, stiffness: 1600, damping: 1.0, initialVelocity: 0)

// M3E "quick": toques y feedback de presión.
    static let quick = Animation.interpolatingSpring(mass: 1, stiffness: 400, damping: 0.7, initialVelocity: 0)

// M3E "normal": transiciones de estado de UI.
    static let normal = Animation.interpolatingSpring(mass: 1, stiffness: 200, damping: 0.82, initialVelocity: 0)

// M3E "emphasized": el momento expresivo (morph play/pausa).
    static let emphasized = Animation.interpolatingSpring(mass: 1, stiffness: 450, damping: 0.68, initialVelocity: 0)

// M3E "slow": modales y hojas que se asientan.
    static let slow = Animation.interpolatingSpring(mass: 1, stiffness: 120, damping: 0.88, initialVelocity: 0)

// Activación de línea de letra (karaoke). Misma calibración que el .spring(0.4, 0.75).
    static let lyricLine = Animation.interpolatingSpring(mass: 1, stiffness: 200, damping: 0.75, initialVelocity: 0)

// ✅ Respiración de los estados vacíos: spring CRÍTICAMENTE amortiguado
// (damping 1.0 = sin overshoot) en bucle. No es un `easeInOut` porque el
// contrato de movimiento de la app son resortes; con damping 1.0 el spring
// entra y sale sin rebote, así que se lee como respiración y no como pulso.
// El bucle lo arranca `AuroraEmptyState` SOLO con la app en primer plano.
    static let breathing = Animation.interpolatingSpring(mass: 1, stiffness: 50, damping: 1.0, initialVelocity: 0).repeatForever(autoreverses: true)

// MARK: - Morphing shape (M3E: formas que se transforman)

// Forma animable que interpola entre círculo, squircle y píldora corta.
// El morph se resuelve interpolando SU PROPIO `animatableData` (radio + ancho).
    struct AuroraMorphShape: Shape {
        var cornerRadiusRatio: CGFloat
        var widthRatio: CGFloat

        var animatableData: AnimatablePair<CGFloat, CGFloat> {
            get { AnimatablePair(cornerRadiusRatio, widthRatio) }
            newValue { cornerRadiusRatio = newValue.first; widthRatio = newValue.second }
        }

        func path(in rect: CGRect) -> Path {
            let side = min(rect.width, rect.height)
            let width = side * widthRatio
            let radius = min(width, side) * cornerRadiusRatio
            return Path(roundedRect: CGRect(x: rect.midX - width / 2, y: rect.minY, width: width, height: side), cornerRadius: radius, style: .continuous)
        }
    }

// MARK: - Squircle Shape (simplificado con RoundedRectangle)

// Shape de squircle usando RoundedRectangle animable.
    struct M3ESquircleShape: Shape {
        var cornerRadius: CGFloat = 16

        var animatableData: CGFloat {
            get { cornerRadius }
            set { cornerRadius = newValue }
        }

        func path(in rect: CGRect) -> Path {
            return Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous)
        }
    }
}