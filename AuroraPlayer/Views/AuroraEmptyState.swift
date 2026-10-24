import SwiftUI

// ═══════════════════════════════════════════════════════════════════════════
// AURORA EMPTY STATE — estado vacío con el lenguaje tipográfico de M3E.
//
// · Icono "hero" en badge circular con gradiente del sistema (el mismo
//   `auroraIconBadge` de las cabeceras: cero vocabulario nuevo).
// · Título grande (24pt bold rounded) + mensaje 15pt: la jerarquía fuerte que
//   pide M3E — antes el vacío era un icono de 48pt con texto de 18pt, más
//   parecido a un error del sistema que a una invitación.
// · Respiración MUY sutil (escala 0.97 ↔ 1.04, opacidad 0.80 ↔ 1.0) con un
//   spring críticamente amortiguado (damping 1.0): se mueve sin rebotar, que
//   es lo que la hace calmada en vez de nerviosa.
//
// PRESUPUESTO A11: la respiración es SOLO escala + opacidad sobre el badge
// (dos transformaciones GPU, una pasada). El bucle se DESTRUYE al pasar la app
// a segundo plano (se renderiza la versión estática y con ella muere el
// `repeatForever`), no se deja "animando" con la pantalla apagada.
// ═══════════════════════════════════════════════════════════════════════════

struct AuroraEmptyState: View {
    let icon: String
    let title: String
    let message: String
    /// Versión compacta para estados vacíos dentro de listas (Cola): reduce
    /// espaciados y el tamaño del título, sin cambiar la estructura.
    var compact: Bool = false

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: compact ? 12 : 18) {
            // ✅ Dos subárboles DISTINTOS a propósito: con la app activa se
            // pinta el que respira; en segundo plano se pinta el estático y la
            // animación `repeatForever` desaparece con él (mismo patrón y misma
            // razón que las barras del ecualizador de QueueView).
            Group {
                if scenePhase == .active {
                    breathingBadge
                } else {
                    badge
                }
            }

            Text(title)
                .font(compact ? M3ETypography.titleMediumEmphasized : M3ETypography.headlineSmallEmphasized)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            Text(message)
                .font(.system(size: compact ? 13 : 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, compact ? 8 : 20)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, compact ? 28 : 36)
        .accessibilityElement(children: .combine)
    }

    /// Badge estático: idéntico al de la versión animada en su punto de reposo,
    /// así el paso a segundo plano no produce ningún salto visual.
    private var badge: some View {
        Image(systemName: icon)
            .auroraIconBadge(size: AuroraIconSize.hero, color: AppTheme.accent, shape: .circle, iconSize: 36)
    }

    private var breathingBadge: some View {
        // El modificador aplica él mismo la escala y la opacidad animadas
        // (0.97 ↔ 1.04 / 0.80 ↔ 1.0): no se declaran aquí para no duplicar
        // transformaciones ni multiplicar la escala.
        badge.modifier(BreathingModifier())
    }
}

/// ✅ FASE 1 (bucle infinito): la respiración ya NO usa `repeatForever` ni
/// `withAnimation` en `onAppear`. La fase se calcula con la fecha de cada
/// frame del `TimelineView`, así que no hay ninguna transacción viva que
/// SwiftUI pueda rearmar cuando esta vista se re-renderiza (p. ej. al cambiar
/// de sección o al abrir/cerrar un sheet).
private struct BreathingModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let phase = CGFloat((sin(2 * Double.pi * t / 3.2) + 1) / 2)
                content
                    .scaleEffect(0.97 + 0.07 * phase)
                    .opacity(Double(0.80 + 0.20 * phase))
            }
        }
    }
}
