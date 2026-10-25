import SwiftUI

// ══════════════════════════════════════════════════════════════════════════
// M3E SNACKBAR — feedback breve, sólido y tonal.
//
// · `inverseSurface` + `inverseOnSurface`: contraste Material 3 sin material
//   translúcido ni blur.
// · El host decide la entrada/salida con `emphasizedDecelerate`; este
//   componente solo pinta el contenido.
// · El botón de acción usa el ripple pasivo de `PressableButtonStyle`
//   (`configuration.isPressed`), nunca un `DragGesture`.
// ══════════════════════════════════════════════════════════════════════════

struct M3ESnackbar: View {
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .font(M3ETypography.bodyMedium)
                .tracking(0.25)
                .foregroundStyle(M3EColor.inverseOnSurface)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let actionTitle, let action {
                Button {
                    Haptics.light()
                    action()
                } label: {
                    Text(actionTitle)
                        .font(M3ETypography.labelLargeEmphasized)
                        .foregroundStyle(M3EColor.inversePrimary)
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(
                    PressableButtonStyle(
                        scale: 0.94,
                        pressedOpacity: 0.85,
                        rippleColor: M3EColor.inversePrimary.opacity(0.16),
                        cornerRadius: 10
                    )
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(M3EColor.inverseSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(M3EColor.outline.opacity(0.18), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
struct M3ESnackbar_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            M3ESnackbar(message: "Añadido a la cola")
            M3ESnackbar(
                message: "Eliminado de favoritos",
                actionTitle: "Deshacer",
                action: {}
            )
        }
        .padding(20)
        .background(M3EColor.surface)
    }
}
#endif
