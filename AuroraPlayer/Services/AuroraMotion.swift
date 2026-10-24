import SwiftUI

// ══════════════════════════════════════════════════════════════════════════
// AURORA MOTION — gramática de movimiento Material 3 Expressive (M3E),
// implementada con APIs nativas de SwiftUI (iOS 16, sin dependencias).
// ══════════════════════════════════════════════════════════════════════════

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

// Activación de línea de letra (karaoke). Misma calibración que el .spring(0.4, 0.75)
static let lyricLine = Animation.interpolatingSpring(mass: 1, stiffness: 200, damping: 0.75, initialVelocity: 0)

// ✅ Respiración de los estados vacíos: spring CRÍTICAMENTE amortiguado (damping 1.0 = sin overshoot)
static let breathing = Animation.interpolatingSpring(mass: 1, stiffness: 50, damping: 1.0, initialVelocity: 0).repeatForever(autoreverses: true)

// MARK: - Morphing shape (M3E: formas que se transforman)

// Forma animable que interpola entre círculo, squircle y píldora corta.
// El morph se resuelve interpolando SU PROPIO `animatableData` (radio + ancho).
struct AuroraMorphShape: Shape {
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

// MARK: - Morphing de chips (solo radio)

// Forma para CHIPS seleccionables que interpola SOLO el radio.
struct AuroraMorphChipShape: Shape, InsettableShape {
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

// MARK: - Squircle Shape (REPLAZADO con RoundedRectangle)

// Shape de squircle simplificado usando RoundedRectangle animable.
// Mantiene la esencia visual sin las matemáticas complejas de superelipse.
struct M3ESquircleShape: Shape {
    // Ya no usamos exponent/cornerRatio complejos.
    // Usamos un radio fijo que simula squircle visual.
    var cornerRadius: CGFloat = 16

    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        // Simple RoundedRectangle con cornerRadius animable.
        // Esto es visualmente equivalente al squircle M3E para la mayoría de casos.
        return Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous)
    }
}

// MARK: - Press feedback

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

// MARK: - Emphasized typography

struct M3ETypography {
    // Título grande enfatizado: título de canción en NowPlaying y encabezados.
    static let titleLargeEmphasized: Font = .system(size: 22, weight: .medium, design: .rounded)

    // Título pequeño enfatizado: títulos de categoría en ContentView.
    static let headlineSmallEmphasized: Font = .system(size: 24, weight: .medium, design: .rounded)

    // Etiqueta grande enfatizada: información secundaria (artista/álbum).
    static let labelLargeEmphasized: Font = .system(size: 14, weight: .medium, design: .rounded)

    // Subtítulo de pista.
    static let trackSubtitle: Font = .system(size: 10, weight: .regular).monospacedDigit()

    // Texto de tiempo (mm:ss).
    static let timeDisplay: Font = .system(size: 20, weight: .medium).monospacedDigit()
}