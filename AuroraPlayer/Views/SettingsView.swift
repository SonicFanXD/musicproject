import SwiftUI

struct SettingsView: View {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var fileAccessService: FileAccessService

    @State private var showFolderPicker = false
    @State private var showLogs = false

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 20) {
                    header

                    playbackSection
                    librarySection
                    audioSection
                    aboutSection

                    Spacer(minLength: 30)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Ajustes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(isPresented: $showFolderPicker) {
            FolderPickerView(
                fileAccessService: fileAccessService
            )
        }
        .sheet(isPresented: $showLogs) {
            LogsView()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        Color.accentColor.opacity(0.18)
                    )
                    .frame(width: 78, height: 78)

                Image(systemName: "gearshape.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            Text("Aurora Player")
                .font(
                    .system(
                        size: 25,
                        weight: .bold
                    )
                )

            Text("Personaliza tu experiencia musical")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .opaqueGlass(
            cornerRadius: 26,
            tint: .accentColor
        )
    }

    // MARK: - Playback

    private var playbackSection: some View {
        settingsSection(
            title: "Reproducción",
            icon: "play.circle.fill"
        ) {
            VStack(spacing: 0) {
                settingRow(
                    icon: "shuffle",
                    title: "Aleatorio",
                    subtitle: audioEngine.isShuffleEnabled
                        ? "Activado"
                        : "Desactivado"
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: {
                                audioEngine.isShuffleEnabled
                            },
                            set: { value in
                                if value != audioEngine.isShuffleEnabled {
                                    audioEngine.toggleShuffle()
                                }
                            }
                        )
                    )
                    .labelsHidden()
                    .tint(.accentColor)
                }

                Divider()
                    .opacity(0.12)
                    .padding(.leading, 54)

                settingRow(
                    icon: repeatIcon,
                    title: "Repetición",
                    subtitle: repeatDescription
                ) {
                    Button {
                        audioEngine.cycleRepeatMode()
                    } label: {
                        Text(repeatDescription)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }

                Divider()
                    .opacity(0.12)
                    .padding(.leading, 54)

                settingRow(
                    icon: "speaker.wave.2.fill",
                    title: "Salida de audio",
                    subtitle: audioEngine.currentRouteName
                ) {
                    Image(
                        systemName: "chevron.right"
                    )
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Library

    private var librarySection: some View {
        settingsSection(
            title: "Biblioteca",
            icon: "music.note.list"
        ) {
            VStack(spacing: 0) {
                Button {
                    showFolderPicker = true
                } label: {
                    settingRowContent(
                        icon: "folder.fill",
                        title: "Carpetas de música",
                        subtitle: "Selecciona dónde buscar tus canciones"
                    ) {
                        Image(
                            systemName: "chevron.right"
                        )
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                Divider()
                    .opacity(0.12)
                    .padding(.leading, 54)

                Button {
                    audioEngine.saveState()
                } label: {
                    settingRowContent(
                        icon: "arrow.clockwise",
                        title: "Actualizar biblioteca",
                        subtitle: "Volver a cargar el estado de reproducción"
                    ) {
                        Image(
                            systemName: "chevron.right"
                        )
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Audio

    private var audioSection: some View {
        settingsSection(
            title: "Audio",
            icon: "waveform"
        ) {
            VStack(spacing: 0) {
                settingRow(
                    icon: "waveform",
                    title: "Motor de audio",
                    subtitle: "AVAudioEngine / AVAudioPlayer"
                ) {
                    Image(
                        systemName: "checkmark.circle.fill"
                    )
                    .foregroundStyle(.green)
                }

                Divider()
                    .opacity(0.12)
                    .padding(.leading, 54)

                settingRow(
                    icon: "headphones",
                    title: "Dispositivo",
                    subtitle: audioEngine.currentRouteName
                ) {
                    EmptyView()
                }
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        settingsSection(
            title: "Aurora Player",
            icon: "sparkles"
        ) {
            VStack(spacing: 0) {
                settingRow(
                    icon: "info.circle.fill",
                    title: "Versión",
                    subtitle: "1.0"
                ) {
                    EmptyView()
                }

                Divider()
                    .opacity(0.12)
                    .padding(.leading, 54)

                Button {
                    showLogs = true
                } label: {
                    settingRowContent(
                        icon: "doc.text.magnifyingglass",
                        title: "Registros",
                        subtitle: "Información de diagnóstico"
                    ) {
                        Image(
                            systemName: "chevron.right"
                        )
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                Divider()
                    .opacity(0.12)
                    .padding(.leading, 54)

                settingRow(
                    icon: "music.note",
                    title: "Aurora Player",
                    subtitle: "Tu música, a tu manera."
                ) {
                    EmptyView()
                }
            }
        }
    }

    // MARK: - Section

    private func settingsSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(Color.accentColor)

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

    // MARK: - Setting Row

    private func settingRow<Trailing: View>(
        icon: String,
        title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        settingRowContent(
            icon: icon,
            title: title,
            subtitle: subtitle,
            trailing: trailing
        )
    }

    private func settingRowContent<Trailing: View>(
        icon: String,
        title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(
                    cornerRadius: 11,
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
            .frame(width: 38, height: 38)

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(title)
                    .font(
                        .subheadline.weight(
                            .semibold
                        )
                    )
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            trailing()
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    // MARK: - Repeat

    private var repeatIcon: String {
        switch audioEngine.repeatMode {
        case .off:
            return "repeat"
        case .all:
            return "repeat.circle.fill"
        case .one:
            return "repeat.1.circle.fill"
        }
    }

    private var repeatDescription: String {
        switch audioEngine.repeatMode {
        case .off:
            return "Desactivado"
        case .all:
            return "Todas"
        case .one:
            return "Una canción"
        }
    }
}

