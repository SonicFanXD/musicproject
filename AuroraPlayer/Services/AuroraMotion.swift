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

    /// M3E "fast/transient": toques y feedback de presión.
    static let quick = Animation.spring(response: 0.22, dampingFraction: 0.72)

    /// M3E "medium/standard": transiciones de estado de UI.
    static let normal = Animation.spring(response: 0.40, dampingFraction: 0.82)

    /// M3E "emphasized": el momento expresivo (morph play/pausa).
    static let emphasized = Animation.spring(response: 0.50, dampingFraction: 0.68)

    /// M3E "slow/duration long": modales y hojas que se asientan.
    static let slow = Animation.spring(response: 0.58, dampingFraction: 0.88)

    /// Activación de línea de letra (karaoke). Misma calibración que el
    /// `.spring(0.4, 0.75)` con el que LyricsView ya estaba afinado.
    static let lyricLine = Animation.spring(response: 0.40, dampingFraction: 0.75)

    /// ✅ Respiración de los estados vacíos: spring CRÍTICAMENTE amortiguado
    /// (damping 1.0 = sin overshoot) en bucle. No es un `easeInOut` porque el
    /// contrato de movimiento de la app son resortes; con damping 1.0 el spring
    /// entra y sale sin rebote, así que se lee como respiración y no como pulso.
    /// El bucle lo arranca `AuroraEmptyState` SOLO con la app en primer plano.
    static let breathing = Animation.spring(response: 1.8, dampingFraction: 1.0).repeatForever(autoreverses: true)
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
