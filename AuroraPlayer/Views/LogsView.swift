import SwiftUI

struct LogsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var copied = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: 18) {
                        header

                        statusSection
                        informationSection
                        tipsSection

                        Spacer(minLength: 30)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Registros")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(
                .ultraThinMaterial,
                for: .navigationBar
            )
            .toolbarBackground(
                .visible,
                for: .navigationBar
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        Color.accentColor.opacity(0.16)
                    )
                    .frame(
                        width: 76,
                        height: 76
                    )

                Image(
                    systemName: "doc.text.magnifyingglass"
                )
                .font(
                    .system(
                        size: 31,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    Color.accentColor
                )
            }

            Text("Diagnóstico")
                .font(
                    .system(
                        size: 24,
                        weight: .bold
                    )
                )

            Text(
                "Información útil para comprobar el estado de Aurora Player."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 18)
        .opaqueGlass(
            cornerRadius: 25,
            tint: .accentColor
        )
    }

    // MARK: - Status

    private var statusSection: some View {
        logSection(
            title: "Estado",
            icon: "checkmark.shield.fill"
        ) {
            VStack(spacing: 0) {
                statusRow(
                    icon: "checkmark.circle.fill",
                    title: "Aplicación",
                    value: "Funcionando"
                )

                divider

                statusRow(
                    icon: "waveform",
                    title: "Motor de audio",
                    value: "Activo"
                )

                divider

                statusRow(
                    icon: "folder.fill",
                    title: "Acceso a archivos",
                    value: "Gestionado por el sistema"
                )
            }
        }
    }

    // MARK: - Information

    private var informationSection: some View {
        logSection(
            title: "Información",
            icon: "info.circle.fill"
        ) {
            VStack(spacing: 0) {
                informationRow(
                    title: "Aplicación",
                    value: "Aurora Player"
                )

                divider

                informationRow(
                    title: "Plataforma",
                    value: "iOS"
                )

                divider

                informationRow(
                    title: "Interfaz",
                    value: "SwiftUI"
                )

                divider

                informationRow(
                    title: "Audio",
                    value: "AVFoundation"
                )

                divider

                informationRow(
                    title: "Diseño",
                    value: "Aurora Glass"
                )
            }
        }
    }

    // MARK: - Tips

    private var tipsSection: some View {
        logSection(
            title: "Solución de problemas",
            icon: "wrench.and.screwdriver.fill"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                tip(
                    icon: "folder",
                    title: "La música no aparece",
                    description:
                        "Comprueba que Aurora Player tenga acceso a la carpeta donde están tus canciones."
                )

                tip(
                    icon: "speaker.wave.2",
                    title: "No se escucha el audio",
                    description:
                        "Comprueba el volumen del dispositivo y la salida de audio seleccionada."
                )

                tip(
                    icon: "arrow.clockwise",
                    title: "La biblioteca está desactualizada",
                    description:
                        "Vuelve a seleccionar tus carpetas de música para actualizar el contenido."
                )
            }
        }
    }

    // MARK: - Section

    private func logSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(
                        Color.accentColor
                    )

                Text(title)
                    .font(.headline)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content()
            }
            .background {
                RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
                .fill(.ultraThinMaterial)
            }
            .overlay {
                RoundedRectangle(
                    cornerRadius: 22,
                    style: .continuous
                )
                .stroke(
                    .white.opacity(0.16),
                    lineWidth: 1
                )
            }
            .shadow(
                color: .black.opacity(0.10),
                radius: 14,
                y: 6
            )
        }
    }

    // MARK: - Status Row

    private func statusRow(
        icon: String,
        title: String,
        value: String
    ) -> some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(
                    cornerRadius: 10,
                    style: .continuous
                )
                .fill(
                    Color.accentColor.opacity(0.12)
                )

                Image(systemName: icon)
                    .font(
                        .system(
                            size: 16,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        Color.accentColor
                    )
            }
            .frame(
                width: 38,
                height: 38
            )

            Text(title)
                .font(
                    .subheadline.weight(
                        .semibold
                    )
                )

            Spacer()

            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
    }

    // MARK: - Information Row

    private func informationRow(
        title: String,
        value: String
    ) -> some View {
        HStack {
            Text(title)
                .font(
                    .subheadline.weight(
                        .medium
                    )
                )
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(
                    .subheadline.weight(
                        .semibold
                    )
                )
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
    }

    // MARK: - Tip

    private func tip(
        icon: String,
        title: String,
        description: String
    ) -> some View {
        HStack(
            alignment: .top,
            spacing: 13
        ) {
            ZStack {
                RoundedRectangle(
                    cornerRadius: 10,
                    style: .continuous
                )
                .fill(
                    Color.accentColor.opacity(0.12)
                )

                Image(systemName: icon)
                    .font(
                        .system(
                            size: 15,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        Color.accentColor
                    )
            }
            .frame(
                width: 38,
                height: 38
            )

            VStack(
                alignment: .leading,
                spacing: 4
            ) {
                Text(title)
                    .font(
                        .subheadline.weight(
                            .semibold
                        )
                    )

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
    }

    // MARK: - Divider

    private var divider: some View {
        Divider()
            .opacity(0.12)
            .padding(.leading, 66)
    }
}

