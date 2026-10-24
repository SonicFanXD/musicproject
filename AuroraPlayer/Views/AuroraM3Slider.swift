import SwiftUI
import UIKit

// ═══════════════════════════════════════════════════════════════════════════
// AURORA M3 SLIDER — slider de Material 3 Expressive para el ecualizador.
//
// POR QUÉ UN SLIDER PROPIO (y no `Slider` de SwiftUI):
//  · `Slider` no permite cambiar el grosor de la pista ni el tamaño del thumb:
//    el sistema impone ~4 pt de pista y ~28 pt de thumb. M3E pide una pista
//    claramente más gruesa (10 pt) y un thumb con respuesta elástica al
//    agarrarlo, y eso solo se consigue dibujándolo.
//  · El relleno del EQ es DESDE EL CENTRO (0 dB): positivo crece a la derecha
//    y negativo a la izquierda. `Slider` solo rellena desde el mínimo.
//
// INTERACCIÓN (pensada para no romper el scroll del ecualizador):
//  · El ARRASTRE vive SOLO en el thumb (área táctil de 44 pt). Así el gesto
//    vertical sobre las filas sigue siendo del ScrollView: diez sliders con
//    `DragGesture` a pantalla completa secuestrarían el scroll.
//  · El TOQUE en la pista salta al valor con `SpatialTapGesture` (iOS 16), que
//    no compite con el scroll del contenedor.
//  · Durante el arrastre se usa la TRASLACIÓN del dedo (`translation.width`)
//    sobre el ancho útil de la pista: las coordenadas del gesto dentro del
//    thumb no son las del slider, así que `location` no sirve aquí.
//  · El thumb escala con `AuroraMotion.spatialDefault` (el spring con rebote de
//    M3E, damping 0.68) mientras se arrastra y suelta un haptic al soltar.
//    `PressableButtonStyle` no aplica: no hay `Button` que pulsar; esta es la
//    misma física (escala + spring) aplicada al estado de arrastre.
//
// RENDIMIENTO: una pista (Capsule), un relleno (Capsule) y un thumb (Circle).
// Ningún blur, ningún material, ninguna sombra animada: el thumb es una capa
// de 26 pt y su sombra es estática (radius 4, no se recalcula por frame).
//
// Requisitos: iOS 16.0 (`SpatialTapGesture` es 16.0; nada de iOS 17).
// ═══════════════════════════════════════════════════════════════════════════

struct AuroraM3Slider: View {
    // MARK: Configuración

    /// Valor actual (controlado por el padre).
    let value: Double
    let range: ClosedRange<Double>
    /// 0 = continuo. En el EQ, 0.5 dB.
    var step: Double = 0
    var isEnabled: Bool = true

    /// Relleno desde 0 (o desde el mínimo si el rango no cruza 0). El EQ lo
    /// usa para crecer desde el centro.
    var fillFromCenter: Bool = false

    /// Dos paradas de acento. `nil` = par de `AppTheme` (reactivo al tema).
    var tintColors: [Color]? = nil
    /// `SurfaceVariant` tonal: pista inactiva sólida.
    var trackColor: Color = Color.secondary.opacity(0.16)

    var accessibilityLabel: String = ""

    /// Se llama con el valor YA redondeado/acotado. El padre decide qué hacer
    /// (en el EQ: `setEQGain`), nunca el slider.
    let onChange: (Double) -> Void

    // MARK: Estado

    /// Valor durante el arrastre: el thumb sigue al dedo sin esperar a que el
    /// padre publique el nuevo valor (evita lag de un frame por tick).
    @State private var dragValue: Double?
    /// Valor al empezar el arrastre (base para la traslación del dedo).
    @State private var dragStartValue: Double?
    @State private var isDragging = false

    /// Métricas M3E (no dependen del ancho, así que no se recalculan por fila).
    private let sliderHeight: CGFloat = 44
    private let trackHeight: CGFloat = 10
    private let thumbSize: CGFloat = 26

    // MARK: Derivados

    private var resolvedTint: [Color] {
        tintColors ?? [AppTheme.accent, AppTheme.accent.opacity(0.55)]
    }

    private var displayValue: Double {
        dragValue ?? value
    }

    private var lower: Double { range.lowerBound }
    private var upper: Double { range.upperBound }

    private func fraction(for value: Double) -> CGFloat {
        guard upper > lower else { return 0 }
        return CGFloat((value - lower) / (upper - lower))
    }

    private var zeroFraction: CGFloat {
        fillFromCenter ? min(max(fraction(for: 0), 0), 1) : 0
    }

    // MARK: Body

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            // El thumb nunca sale de la pista: su centro recorre
            // [thumb/2, ancho − thumb/2].
            let usable = max(1, width - thumbSize)
            let progress = min(max(fraction(for: displayValue), 0), 1)
            let thumbX = thumbSize / 2 + usable * progress
            let fillOrigin = thumbSize / 2 + usable * zeroFraction
            let fillWidth = max(0, abs(thumbX - fillOrigin))

            ZStack(alignment: .leading) {
                // Pista (SurfaceVariant sólida).
                Capsule()
                    .fill(trackColor)
                    .frame(width: width, height: trackHeight)

                // Relleno (acento de DOS colores, identidad Aurora).
                Capsule()
                    .fill(LinearGradient(colors: resolvedTint, startPoint: .leading, endPoint: .trailing))
                    .frame(width: fillWidth, height: trackHeight)
                    .offset(x: min(thumbX, fillOrigin))

                thumb(usable: usable)
                    .position(x: thumbX, y: sliderHeight / 2)
            }
            .frame(width: width, height: sliderHeight, alignment: .leading)
            // ✅ Toque en la pista (no compite con el scroll vertical).
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture()
                    .onEnded { tap in
                        guard isEnabled else { return }
                        let x = tap.location.x - thumbSize / 2
                        let fraction = min(max(x / usable, 0), 1)
                        send(lower + Double(fraction) * (upper - lower))
                        Haptics.light()
                    }
            )
        }
        .frame(height: sliderHeight)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityValue(Text(String(format: "%+.1f", displayValue)))
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            let delta = step > 0 ? step : (upper - lower) / 20
            switch direction {
            case .increment: send(displayValue + delta)
            case .decrement: send(displayValue - delta)
            @unknown default: break
            }
        }
    }

    // MARK: Thumb

    private func thumb(usable: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: resolvedTint, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: thumbSize, height: thumbSize)
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 2)
                }
                // Sombra estática (capa de 26 pt): no se recalcula por frame.
                .shadow(color: .black.opacity(isDragging ? 0.3 : 0.18),
                        radius: isDragging ? 6 : 4, x: 0, y: 2)
                // ✅ M3E: respuesta elástica al agarrar el thumb.
                .scaleEffect(isDragging ? 1.18 : 1)
                .animation(AuroraMotion.spatialDefault, value: isDragging)
        }
        // Área táctil de 44 pt (mínimo de accesibilidad), sin agrandar el dibujo.
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    guard isEnabled else { return }
                    if !isDragging {
                        isDragging = true
                        dragStartValue = dragValue ?? value
                        Haptics.selection()
                    }
                    let start = dragStartValue ?? value
                    // Traslación vertical intencional: no mueve el valor.
                    let delta = Double(drag.translation.width / usable) * (upper - lower)
                    send(start + delta)
                }
                .onEnded { _ in
                    guard isEnabled else { return }
                    isDragging = false
                    dragStartValue = nil
                    dragValue = nil
                    Haptics.light()
                }
        )
    }

    // MARK: Cálculo del valor

    /// Redondeo por paso, acotado al rango y deduplicado. Aquí no se toca el
    /// motor: solo se avisa al padre.
    ///
    /// `dragValue` SOLO se usa mientras `isDragging`: si se fijara al tocar la
    /// pista o al ajustar por VoiceOver, el thumb se quedaría clavado en ese
    /// valor aunque el padre cambiase `value` después (preset, reset...).
    private func send(_ raw: Double) {
        guard raw.isFinite else { return }
        var snapped = raw
        if step > 0 {
            snapped = (raw / step).rounded() * step
        }
        let clamped = min(max(snapped, lower), upper)
        if isDragging {
            if let drag = dragValue, abs(drag - clamped) < 0.0001 { return }
            dragValue = clamped
        }
        if abs(clamped - value) > 0.0001 {
            onChange(clamped)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct AuroraM3Slider_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 24) {
            AuroraM3Slider(value: 4, range: -12...12, step: 0.5, fillFromCenter: true,
                           accessibilityLabel: "32 Hz") { _ in }
            AuroraM3Slider(value: -7, range: -12...12, step: 0.5, fillFromCenter: true,
                           accessibilityLabel: "125 Hz") { _ in }
            AuroraM3Slider(value: 0.6, range: 0...1, accessibilityLabel: "Volumen") { _ in }
            AuroraM3Slider(value: 4, range: -12...12, step: 0.5, isEnabled: false,
                           fillFromCenter: true, accessibilityLabel: "Desactivado") { _ in }
        }
        .padding(24)
        .background(Color(UIColor.systemBackground))
    }
}
#endif
