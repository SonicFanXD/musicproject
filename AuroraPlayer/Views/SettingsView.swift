import SwiftUI

struct SettingsView: View {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var fileAccessService: FileAccessService
    @Environment(\.dismiss) private var dismiss

    @State private var showFolderPicker = false
    @State private var showLogs = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        headerSection

                        // Library Section
                        settingsSection(
                            icon: "folder.fill",
                            title: "Biblioteca",
                            color: .blue
                        ) {
                            settingsButton(
                                title: "Carpetas de música",
                                subtitle: "\(fileAccessService.folders.count) carpetas",
                                icon: "folder.fill",
                                color: .blue
                            ) {
                                showFolderPicker = true
                            }

                            settingsDivider

                            settingsButton(
                                title: "Actualizar biblioteca",
                                subtitle: fileAccessService.isScanning ? "Escaneando..." : "Rescanear carpetas",
                                icon: "arrow.clockwise",
                                color: .orange
                            ) {
                                fileAccessService.refreshAllFolders()
                            }
                            .disabled(fileAccessService.isScanning)
                        }

                        // Audio Section
                        settingsSection(
                            icon: "waveform",
                            title: "Audio",
                            color: .purple
                        ) {
                            settingsButton(
                                title: "Equalizador",
                                subtitle: audioEngine.isEQEnabled ? audioEngine.eqPreset.displayName : "Desactivado",
                                icon: "slider.horizontal.3",
                                color: .purple
                            ) {
                                audioEngine.toggleEQ()
                            }

                            settingsDivider

                            settingsButton(
                                title: "Crossfade",
                                subtitle: audioEngine.isCrossfadeEnabled ? "Activado" : "Desactivado",
                                icon: "forward.end.fill",
                                color: .teal
                            ) {
                                audioEngine.toggleCrossfade()
                            }

                            settingsDivider

                            settingsButton(
                                title: "Calidad de salida",
                                subtitle: "\(Int(audioEngine.outputSampleRate / 1000)) kHz · \(audioEngine.outputChannelCount) canales",
                                icon: "speaker.wave.2.fill",
                                color: .indigo
                            ) {}
                        }

                        // Visual Section
                        settingsSection(
                            icon: "paintbrush.fill",
                            title: "Apariencia",
                            color: .pink
                        ) {
                            settingsButton(
                                title: "Tema",
                                subtitle: "Sistema (claro/oscuro)",
                                icon: "circle.lefthalf.filled",
                                color: .gray
                            ) {}

                            settingsDivider

                            settingsButton(
                                title: "Color de acento",
                                subtitle: "Morado (predeterminado)",
                                icon: "drop.fill",
                                color: .accentColor
                            ) {}
                        }

                        // Stats Section
                        settingsSection(
                            icon: "chart.bar.fill",
                            title: "Estadísticas",
                            color: .green
                        ) {
                            statRow(title: "Canciones", value: "\(fileAccessService.songs.count)")
                            settingsDivider
                            statRow(title: "Álbumes", value: "\(fileAccessService.albums.count)")
                            settingsDivider
                            statRow(title: "Artistas", value: "\(fileAccessService.artists.count)")
                        }

                        // Advanced Section
                        settingsSection(
                            icon: "wrench.and.screwdriver.fill",
                            title: "Avanzado",
                            color: .orange
                        ) {
                            settingsButton(
                                title: "Registros",
                                subtitle: "Ver logs de la app",
                                icon: "doc.text.magnifyingglass",
                                color: .gray
                            ) {
                                showLogs = true
                            }

                            settingsDivider

                            settingsButton(
                                title: "Acerca de",
                                subtitle: "Aurora Player v1.0",
                                icon: "info.circle.fill",
                                color: .blue
                            ) {}
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") { dismiss() }
                        .foregroundStyle(Color.accentColor)
                }
            }
            .sheet(isPresented: $showFolderPicker) {
                FolderPickerView(fileAccessService: fileAccessService)
            }
            .sheet(isPresented: $showLogs) {
                LogsView()
            }
        }
    }

    // MARK: - Header
    private var headerSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.3), Color.accentColor.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 90, height: 90)

                Image(systemName: "gearshape.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 4) {
                Text("Ajustes")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.primary)

                Text("Configura Aurora Player a tu gusto")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .nativeGlass(cornerRadius: 24)
    }

    // MARK: - Section Builder
    @ViewBuilder
    private func settingsSection<Content: View>(
        icon: String,
        title: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 28, height: 28)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(color.opacity(0.12))
                    }

                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content()
            }
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
    }

    // MARK: - Button Row
    @ViewBuilder
    private func settingsButton(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(color.opacity(0.1))
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Stat Row
    private func statRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical: 12)
    }

    // MARK: - Divider
    private var settingsDivider: some View {
        Divider()
            .opacity(0.1)
            .padding(.leading, 64)
    }
}

#Preview {
    SettingsView(audioEngine: AudioEngine(), fileAccessService: FileAccessService())
}