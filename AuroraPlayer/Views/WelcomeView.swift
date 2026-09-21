import SwiftUI

/// ✅ PESTAÑA BIENVENIDA (3.0): pantalla nueva, por ahora un placeholder.
/// Deja "Añadir carpeta" totalmente funcional reutilizando FolderPickerView (el
/// mismo selector de carpetas que usaba la Biblioteca), para no perder ninguna
/// funcionalidad mientras se construye la pantalla definitiva.
struct WelcomeView: View {
    @ObservedObject var fileAccessService: FileAccessService
    // ✅ Observado para que los textos se re-rendericen al cambiar de idioma.
    @ObservedObject private var localization = Localization.shared

    @State private var showFolderPicker = false

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                headerSection
                addFolderButton
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
        }
        .sheet(isPresented: $showFolderPicker) {
            FolderPickerView(fileAccessService: fileAccessService)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(AppTheme.accentGradient(opacity: 0.12))
                    .frame(width: 96, height: 96)
                    .overlay(
                        Circle().stroke(AppTheme.accent.opacity(0.25), lineWidth: 1)
                    )
                    .shadow(color: AppTheme.accent.opacity(0.2), radius: 12, y: 6)

                Image(systemName: "sparkles")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(AppTheme.accentGradient)
            }

            VStack(spacing: 6) {
                Text(Localization.localized("welcome.title"))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(Localization.localized("welcome.comingSoon"))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.accentGradient)

                Text(Localization.localized("welcome.comingSoonMessage"))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Añadir carpeta (funcional)

    private var addFolderButton: some View {
        Button {
            Haptics.light()
            showFolderPicker = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                Text(Localization.localized("actions.addFolder"))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background {
                Capsule().fill(AppTheme.accentGradient)
            }
            .shadow(color: AppTheme.accent.opacity(0.35), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.96))
    }
}
