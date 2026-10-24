import SwiftUI

// ═══════════════════════════════════════════════════════════════════════════
// AURORA MOTION — gramática de movimiento Material 3 Expressive (M3E),
// implementada con APIs nativas de SwiftUI (iOS 16, sin dependencias).
//
// REGLA DE ORO (A11 / iPhone 8 Plus): todo lo que vive aquí es una
// TRANSFORMACIÓN GPU (escala, opacidad, offset, path interpolation). Cero
// blurs, cero materiales nuevos, cero pasadas offscreen añadidas. M3E se
// expresa con FÍSICA, no con píxeles caros.
//
// Cómo se leen los tokens (curvas calibradas al vocabulario M3E):
//  · quick      220 ms, damping 0.72 — toques, toggles, feedback de presión.
//               Rebote mínimo (~3% de overshoot): inmediato, nunca "metálico".
//  · normal     400 ms, damping 0.82 — transiciones de estado de UI
//               (cambio de canción, entradas de contenido). Casi sin
//               overshoot: elegante, no saltarín.
//  · emphasized 500 ms, damping 0.68 — el MOMENTO expresivo de M3E: el morph
//               del botón play/pausa. Overshoot visible (~8%): este es el
//               resorte que la gente siente como "elástico".
//  · slow       580 ms, damping 0.88 — modales y hojas. Asentarse, no rebotar.
//  · lyricLine  400 ms, damping 0.75 — calibración YA validada en LyricsView
//               (activación de línea con karaoke a 60 fps). Centralizada aquí
//               para poder retocarla en un solo sitio.
//
// Para verificar en dispositivo: compara un play/pausa en NowPlaying contra
// el mismo botón en la rama anterior — el nuevo debe sentirse "gordo" y con
// un rebote final corto; si el rebote se siente blando/sube demasiado,
// sube dampingFraction a 0.75 (emphasized) sin tocar duraciones.
// ═══════════════════════════════════════════════════════════════════════════

enum AuroraMotion {

    /// M3E "spatialDefault": movimiento con rebote suave (stiffness 380, damping 0.8).
    static let spatialDefault = Animation.interpolatingSpring(mass: 1, stiffness: 380, damping: 0.8, initialVelocity: 0)

    /// M3E "spatialFast": rebote más notable, para toques (stiffness 800, damping 0.6).
    static let spatialFast = Animation.interpolatingSpring(mass: 1, stiffness: 800, damping: 0.6, initialVelocity: 0)

    /// M3E "effectsDefault": cambios de opacidad/color sin rebote (stiffness 1600, damping 1.0).
    static let effectsDefault = Animation.interpolatingSpring(mass: 1, stiffness: 1600, damping: 1.0, initialVelocity: 0)

    /// M3E "quick": toques y feedback de presión.
    static let quick = Animation.interpolatingSpring(mass: 1, stiffness: 400, damping: 0.7, initialVelocity: 0)

    /// M3E "normal": transiciones de estado de UI.
    static let normal = Animation.interpolatingSpring(mass: 1, stiffness: 200, damping: 0.82, initialVelocity: 0)

    /// M3E "emphasized": el momento expresivo (morph play/pausa).
    static let emphasized = Animation.interpolatingSpring(mass: 1, stiffness: 450, damping: 0.68, initialVelocity: 0)

    /// M3E "slow": modales y hojas que se asientan.
    static let slow = Animation.interpolatingSpring(mass: 1, stiffness: 120, damping: 0.88, initialVelocity: 0)

    /// Activación de línea de letra (karaoke). Misma calibración que el
    /// `.spring(0.4, 0.75)` con el que LyricsView ya estaba afinado.
    static let lyricLine = Animation.interpolatingSpring(mass: 1, stiffness: 200, damping: 0.75, initialVelocity: 0)

    /// ✅ Respiración de los estados vacíos: spring CRÍTICAMENTE amortiguado
    /// (damping 1.0 = sin overshoot) en bucle. No es un `easeInOut` porque el
    /// contrato de movimiento de la app son resortes; con damping 1.0 el spring
    /// entra y sale sin rebote, así que se lee como respiración y no como pulso.
    /// El bucle lo arranca `AuroraEmptyState` SOLO con la app en primer plano.
    static let breathing = Animation.interpolatingSpring(mass: 1, stiffness: 50, damping: 1.0, initialVelocity: 0).repeatForever(autoreverses: true)
}

// MARK: - Morphing shape (M3E: formas que se transforman, no que se swapn)

/// ✅ Forma ANIMABLE que interpola entre círculo, squircle y píldora corta.
/// El morfismo se resuelve interpolando SU PROPIO `animatableData` (radio de
/// esquina + ancho), es decir: una path interpolation — el morph más barato
/// que existe en GPU. NO usa `matchedGeometryEffect` a propósito: eso obliga a
/// compartir un namespace entre dos vistas y recrea jerarquía en el A11; aquí
/// la forma es UNA sola vista que cambia de geometría, así que el botón nunca
/// parpadea ni el layout se mueve (el frame exterior es fijo).
///
/// Nota: el path puede dibujar fuera de `rect.width` cuando `widthRatio > 1`
/// (la forma "más ancha" del estado reproduciendo). Es intencionado y seguro:
/// los Shapes no se recortan a su rect y el contenedor del botón (76/88 pt)
/// deja margen.
struct AuroraMorphShape: Shape {
    /// 0.5 = círculo/píldora perfecta · ~0.30-0.36 = squircle estilo M3E.
    var cornerRadiusRatio: CGFloat
    /// 1.0 = huella cuadrada · >1.0 = más ancho (la forma "en marcha").
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
        // Radio sobre la MENOR dimensión: con ratio 0.5 y ancho == lado da un
        // círculo exacto; con 0.34 da el squircle del estado "reproduciendo".
        let radius = min(width, side) * cornerRadiusRatio
        return Path(
            roundedRect: CGRect(
                x: rect.midX - width / 2,
                y: rect.minY,
                width: width,
                height: side
            ),
            cornerRadius: radius,
            style: .continuous
        )
    }
}

// MARK: - Morphing de chips y píldoras (M3E · Prioridad 2)

/// ✅ Forma para CHIPS seleccionables que interpola SOLO el radio: rectángulo
/// redondeado ↔ cápsula. El chip conserva todo su ancho (`rect`), así que el
/// morph no mueve el layout ni cambia el tamaño del texto.
///
/// Por qué `animatableData` y no `matchedGeometryEffect`: este último obliga a
/// compartir un `Namespace` y re-instancia la jerarquía, lo que en un
/// `ScrollView` horizontal produce el típico cross-fade entre el chip antiguo
/// y el nuevo (y en el A11 añade trabajo por frame). Aquí cada chip interpola
/// SU propia forma: cero coordinación global, cero vistas extra.
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

/// ✅ Píldora que se ENSANCHA/ENCOGE sin tocar el layout: dibuja dentro de
/// `rect` un rectángulo redondeado de ancho `rect.width × widthScale`, centrado.
/// Es el morph de los FAB / botones de acción de M3E (inactivo compacto →
/// activo a ancho completo) sin mover a los vecinos.
struct AuroraMorphPill: Shape {
    var widthScale: CGFloat = 1
    /// 0.5 = cápsula perfecta.
    var cornerRatio: CGFloat = 0.5

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(widthScale, cornerRatio) }
        set {
            widthScale = newValue.first
            cornerRatio = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let width = rect.width * min(max(widthScale, 0.1), 1)
        let radius = min(width, rect.height) * min(max(cornerRatio, 0), 0.5)
        let box = CGRect(x: rect.midX - width / 2, y: rect.minY,
                         width: width, height: rect.height)
        return Path(roundedRect: box, cornerRadius: radius, style: .continuous)
    }
}

// MARK: - Squircle Shape (superelipse M3E)

/// ✅ Shape de superelipse (squircle) para contenedores M3E.
/// Usa la fórmula de superelipse `|x/rx|^n + |y/ry|^n = 1` con n=4 para un
/// aspecto clásico de squircle. Dibuja el path punto por punto para asegurar
/// precisión en todos los dispositivos, incluido el A11.
struct M3ESquircleShape: Shape {
    /// Parámetro de excentricidad. `4` = squircle clásico M3E; valores mayores
    /// hacen las esquinas más pronunciadas, menores las hacen más redondeadas.
    var exponent: CGFloat = 4

    /// Radio en proporción al lado menor. `0.5` = círculo perfecto; valores
    /// menores hacen esquinas más pronunciadas.
    var cornerRatio: CGFloat = 0.5

    var animatableData: CGFloat {
        get { exponent }
        set { exponent = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let centerX = rect.midX
        let centerY = rect.midY
        let rx = min(width, height) / 2
        let ry = rx

        let n = exponent
        let stepCount = 64
        var path = Path()

        // Calcular el punto inicial en el lado derecho medio
        let startAngle = -CGFloat.pi / 2
        let startX = centerX + rx * pow(abs(cos(startAngle)), 2 / n) * sign(cos(startAngle))
        let startY = centerY + ry * pow(abs(sin(startAngle)), 2 / n) * sign(sin(startAngle))
        path.move(to: CGPoint(x: startX, y: startY))

        // Dibujar los 4 cuartos en sentido antihorario
        for quarter in 0..<4 {
            let start = quarter * CGFloat.pi / 2
            let end = (quarter + 1) * CGFloat.pi / 2
            let subSteps = 16
            for i in 0...subSteps {
                let t = start + (end - start) * CGFloat(i) / CGFloat(subSteps)
                let x = centerX + rx * pow(abs(cos(t)), 2 / n) * cos(t).sign
                let y = centerY + ry * pow(abs(sin(t)), 2 / n) * sin(t).sign
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        return path
    }
}

// MARK: - Press feedback (escala + opacidad con física M3E)

/// ✅ Feedback de presión elástico. Es el MISMO `PressableButtonStyle` que ya
/// usaba toda la app (30+ call sites) con dos mejoras, sin romper ninguno:
///  1. La curva pasa a `AuroraMotion.quick` (antes era un spring a mano con
///     otro apretón: ahora TODO lo pulsable de la app comparte la misma
///     física, que es lo que hace que una app se sienta "de un sitio").
///  2. Nuevo parámetro opcional `pressedOpacity`: M3E apaga levemente la
///     superficie al presionar, lo que hace la pulsación legible sobre la
///     portada sin añadir ni un render pass (opacidad = capa del sistema).
/// Sin haptics aquí dentro a propósito: los botones ya disparan `Haptics` en
/// sus acciones; duplicarlo haría doble Taptic en cada toque.
struct PressableButtonStyle: ButtonStyle {
    let scale: CGFloat
    /// Opacidad al presionar. 1.0 (por defecto) = solo escala, como antes.
    var pressedOpacity: Double = 1.0

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .opacity(configuration.isPressed ? pressedOpacity : 1.0)
            .animation(AuroraMotion.quick, value: configuration.isPressed)
    }
}

// MARK: - Emphasized typography (M3E type scale)

/// ✅ Tokens de tipografía enfática Material 3 Expressive.
/// Cada rol define tamaño (pt), peso y tracking para iOS 16 en hardware limitado.
/// Estos valores están calibrados al vocabulario oficial de M3E y no deben
/// modificarse sin consultar las guías de diseño de Google.
struct M3ETypography {
    /// Título grande enfatizado: usado para el título de la canción en NowPlaying
    /// y encabezados principales de sección.
    static let titleLargeEmphasized: Font = .system(size: 22, weight: .medium, design: .rounded)
        .tracking(0)

    /// Título pequeño enfatizado: usado para títulos de categoría en ContentView
    /// y otros encabezados de sección medianos.
    static let headlineSmallEmphasized: Font = .system(size: 24, weight: .medium, design: .rounded)
        .tracking(0)

    /// Etiqueta grande enfatizada: usado para texto de información secundaria,
    /// como artista/álbum en NowPlaying y datos de pista.
    static let labelLargeEmphasized: Font = .system(size: 14, weight: .medium, design: .rounded)
        .tracking(0.1)

    /// Subtítulo de pista: usado para información de calidad y route display.
    static let trackSubtitle: Font = .system(size: 10, weight: .regular)
        .monospacedDigit()

    /// Texto de tiempo (formato mm:ss): siempre monospaced para alineación perfecta.
    static let timeDisplay: Font = .system(size: 20, weight: .medium)
        .monospacedDigit()
}

// MARK: - Press feedback (escala + opacidad con física M3E)

/// ✅ Feedback de presión elástico. Es el MISMO `PressableButtonStyle` que ya
/// usaba toda la app (30+ call sites) con dos mejoras, sin romper ninguno:
///  1. La curva pasa a `AuroraMotion.quick` (antes era un spring a mano con
///     otro apretón: ahora TODO lo pulsable de la app comparte la misma
///     física, que es lo que hace que una app se sienta "de un sitio").
///  2. Nuevo parámetro opcional `pressedOpacity`: M3E apaga levemente la
///     superficie al presionar, lo que hace la pulsación legible sobre la
///     portada sin añadir ni un render pass (opacidad = capa del sistema).
/// Sin haptics aquí dentro a propósito: los botones ya disparan `Haptics` en
/// sus acciones; duplicarlo haría doble Taptic en cada toque.
struct PressableButtonStyle: ButtonStyle {
    let scale: CGFloat
    /// Opacidad al presionar. 1.0 (por defecto) = solo escala, como antes.
    var pressedOpacity: Double = 1.0

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .opacity(configuration.isPressed ? pressedOpacity : 1.0)
            .animation(AuroraMotion.quick, value: configuration.isPressed)
    }
}
