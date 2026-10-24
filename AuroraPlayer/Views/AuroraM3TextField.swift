import SwiftUI
import UIKit

// ═══════════════════════════════════════════════════════════════════════════
// AURORA M3 TEXT FIELD — campo de texto con la forma y el "containment" de
// Material 3 Expressive.
//
// QUÉ APORTA FRENTE A UN TextField CON `.textFieldStyle(.roundedBorder)`:
//  · Forma de PÍLDORA (radio = alto/2), no un rectángulo con radio fijo: es la
//    forma canónica de M3E para campos de búsqueda y entradas de una línea.
//  · Contenedor SÓLIDO y TONAL (`M3EColor.surfaceVariant`, derivado del
//    acento), sin material ni blur: cero capas offscreen por frame en el A11,
//    y sin el gris de iOS que delataba el look nativo.
//  · El borde CAMBIA de color y grosor al enfocar (outline de M3E) con el
//    spring rápido de la app; el foco se anima, no se "salta".
//  · Icono guía a la izquierda y botón de limpiar que aparece/desaparece con
//    un spring corto (antes el `xmark` aparecía a golpe de layout).
//
// El foco puede ser EXTERNO (`FocusState<Bool>.Binding`, para que el padre
// conserve su `@FocusState` y pueda reenfocar al limpiar) o interno si no se
// pasa binding. Ninguna API por encima de iOS 16.0.
// ═══════════════════════════════════════════════════════════════════════════

struct AuroraM3TextField: View {
    let placeholder: String
    @Binding var text: String

    /// Icono guía (M3E: leading icon). `nil` = sin icono.
    var icon: String? = "magnifyingglass"
    var showsClearButton: Bool = true
    var clearAccessibilityLabel: String? = nil
    /// Se invoca justo después de vaciar el texto (ContentView lo usa para
    /// reaplicar la búsqueda al instante, sin esperar al debounce).
    var onClear: (() -> Void)? = nil

    var submitLabel: SubmitLabel = .search
    var keyboardType: UIKeyboardType = .default
    var onSubmit: (() -> Void)? = nil
    var isEnabled: Bool = true

    /// Foco controlado por el padre. Si es `nil`, el componente gestiona un
    /// `@FocusState` propio (y el toque en el contenedor lo activa).
    var focus: FocusState<Bool>.Binding? = nil

    /// Acento del borde al enfocar. `nil` = `AppTheme.accent` (reactivo al tema).
    var accent: Color? = nil

    @FocusState private var internalFocus: Bool

    private let fieldHeight: CGFloat = 48

    private var resolvedAccent: Color { accent ?? AppTheme.accent }

    private var isEditing: Bool {
        focus?.wrappedValue ?? internalFocus
    }

    private var borderColor: Color {
        isEditing ? resolvedAccent.opacity(0.9) : M3EColor.outline.opacity(0.28)
    }

    private var borderWidth: CGFloat {
        isEditing ? 1.5 : 0.75
    }

    var body: some View {
        HStack(spacing: 10) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isEditing ? resolvedAccent : Color.secondary)
                    .animation(AuroraMotion.spatialFast, value: isEditing)
            }

            field

            if showsClearButton && !text.isEmpty {
                clearButton
                    .transition(.opacity.combined(with: .scale(scale: 0.7)))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: fieldHeight)
        // ✅ SurfaceContainer tonal sólido (cero material).
        .background {
            Capsule().fill(M3EColor.surfaceVariant)
        }
        // ✅ Outline que cambia con el foco (M3E).
        .overlay {
            Capsule().strokeBorder(borderColor, lineWidth: borderWidth)
        }
        .contentShape(Capsule())
        .onTapGesture { requestFocus() }
        .animation(AuroraMotion.spatialFast, value: isEditing)
        .animation(AuroraMotion.spatialFast, value: text.isEmpty)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Campo

    @ViewBuilder
    private var field: some View {
        if let focus = focus {
            baseField.focused(focus)
        } else {
            baseField.focused($internalFocus)
        }
    }

    private var baseField: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(M3ETypography.bodyLarge)
            .foregroundStyle(.primary)
            .submitLabel(submitLabel)
            .keyboardType(keyboardType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .disabled(!isEnabled)
            .onSubmit { onSubmit?() }
    }

    // MARK: - Limpiar

    private var clearButton: some View {
        Button {
            Haptics.light()
            text = ""
            onClear?()
            requestFocus()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.secondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle(scale: AuroraPressScale.chip, pressedOpacity: 0.7))
        .accessibilityLabel(Text(clearAccessibilityLabel ?? "Limpiar"))
    }

    private func requestFocus() {
        guard isEnabled else { return }
        if let focus = focus {
            focus.wrappedValue = true
        } else {
            internalFocus = true
        }
    }
}

// MARK: - Preview

#if DEBUG
struct AuroraM3TextField_Previews: PreviewProvider {
    struct Host: View {
        @State private var text = ""
        @State private var filled = "Kind of Blue"
        @FocusState private var focus: Bool

        var body: some View {
            VStack(spacing: 20) {
                AuroraM3TextField(
                    placeholder: "Buscar en la biblioteca",
                    text: $text,
                    clearAccessibilityLabel: "Limpiar búsqueda",
                    focus: $focus
                )
                AuroraM3TextField(
                    placeholder: "Buscar en la biblioteca",
                    text: $filled,
                    clearAccessibilityLabel: "Limpiar búsqueda",
                    focus: $focus
                )
                AuroraM3TextField(placeholder: "Desactivado", text: .constant(""), isEnabled: false)
            }
            .padding(24)
            .background(M3EColor.surface)
        }
    }

    static var previews: some View {
        Host()
    }
}
#endif
