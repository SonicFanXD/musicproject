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
                    statsSection
                    audioSection
                    audioQualitySection
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
            FolderPickerView(fileAccessService: fileAccessService)
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
                    .fill(Color.accentColor.opacity(0.18))
                    .frame(width: 78, height: 78)

                Image(systemName: "gearshape.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            Text("Aurora Player")
                .font(.system(size: 25, weight: .bold))

            Text("Personaliza tu experiencia musical")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .opaqueGlass(cornerRadius: 26, tint: .accentColor)
    }

    // MARK: - Playback

    private var playbackSection: some View {
        settingsSection(title: "Reproducción", icon: "play.circle.fill") {
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
                            get: { audioEngine.isShuffleEnabled },
                            set: { value in
                                if value != audioEngine.isShuffleEnabled {
                                    audioEngine.toggleShuffle()
                                }
                            }
                        )
                    )
                    .labelsHidden()
                    .tint(.accentColor)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: audioEngine.isShuffleEnabled)
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
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: audioEngine.repeatMode)
                }

                Divider()
                    .opacity(0.12)
                    .padding(.leading, 54)

                settingRow(
                    icon: "speaker.wave.2.fill",
                    title: "Salida de audio",
                    subtitle: audioEngine.currentRouteName
                ) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Library

    private var librarySection: some View {
        settingsSection(title: "Biblioteca", icon: "music.note.list") {
            VStack(spacing: 0) {
                Button {
                    showFolderPicker = true
                } label: {
                    settingRowContent(
                        icon: "folder.fill",
                        title: "Carpetas de música",
                        subtitle: "Selecciona dónde buscar tus canciones"
                    ) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                Divider()
                    .opacity(0.12)
                    .padding(.leading, 54)

                Button {
                    fileAccessService.refreshAllFolders()
                } label: {
                    settingRowContent(
                        icon: "arrow.clockwise",
                        title: "Actualizar biblioteca",
                        subtitle: fileAccessService.isScanning
                            ? "Escaneando…"
                            : "Volver a buscar canciones en tus carpetas"
                    ) {
                        if fileAccessService.isScanning {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(fileAccessService.isScanning)
            }
        }
    }

    // MARK: - Library Stats

    private var statsSection: some View {
        settingsSection(title: "Tu biblioteca", icon: "chart.bar.fill") {
            VStack(spacing: 0) {
                settingRow(
                    icon: "music.note",
                    title: "Canciones",
                    subtitle: "\(fileAccessService.songs.count) en total"
                ) { EmptyView() }

                Divider().opacity(0.12).padding(.leading, 54)

                settingRow(
                    icon: "square.stack",
                    title: "Álbumes",
                    subtitle: "\(fileAccessService.albums.count) álbumes"
                ) { EmptyView() }

                Divider().opacity(0.12).padding(.leading, 54)

                settingRow(
                    icon: "person.2",
                    title: "Artistas",
                    subtitle: "\(fileAccessService.artists.count) artistas"
                ) { EmptyView() }

                Divider().opacity(0.12).padding(.leading, 54)

                settingRow(
                    icon: "clock",
                    title: "Duración total",
                    subtitle: totalDurationText
                ) { EmptyView() }
            }
        }
    }

    private var totalDurationText: String {
        let totalSeconds = fileAccessService.songs.reduce(0) { $0 + $1.duration }
        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        if hours > 0 { return "\(hours) h \(minutes) min" }
        if minutes > 0 { return "\(minutes) min" }
        return "—"
    }

    // MARK: - Audio

    private var audioSection: some View {
        settingsSection(title: "Audio", icon: "waveform") {
            VStack(spacing: 0) {
                settingRow(
                    icon: "waveform",
                    title: "Motor de audio",
                    subtitle: "AVAudioEngine / AVAudioPlayer"
                ) {
                    Image(systemName: "checkmark.circle.fill")
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

    // MARK: - Audio Quality

    private var audioQualitySection: some View {
        settingsSection(title: "Calidad de audio", icon: "hifispeaker.fill") {
            VStack(spacing: 0) {
                if let song = audioEngine.currentSong {
                    settingRow(
                        icon: "music.note",
                        title: "Formato de la pista",
                        subtitle: song.formatDescription.isEmpty
                            ? "Desconocido"
                            : song.formatDescription
                    ) { EmptyView() }

                    Divider().opacity(0.12).padding(.leading, 54)

                    settingRow(
                        icon: "arrow.up.arrow.down",
                        title: "Frecuencia de salida",
                        subtitle: audioEngine.outputSampleRate > 0
                            ? "\(Int(audioEngine.outputSampleRate)) Hz · \(audioEngine.outputChannelCount) canales"
                            : "—"
                    ) {
                        Image(systemName: isBitPerfect
                            ? "checkmark.seal.fill"
                            : "arrow.triangle.2.circlepath")
                        .foregroundStyle(isBitPerfect ? .green : .orange)
                    }

                    Divider().opacity(0.12).padding(.leading, 54)

                    settingRow(
                        icon: isBitPerfect ? "checkmark.seal.fill" : "info.circle",
                        title: isBitPerfect ? "Bit perfecto" : "Con remuestreo",
                        subtitle: isBitPerfect
                            ? "El dispositivo reproduce a la frecuencia nativa del archivo"
                            : "El sistema está ajustando la frecuencia de la pista a la salida"
                    ) { EmptyView() }
                } else {
                    settingRow(
                        icon: "waveform",
                        title: "Sin reproducción activa",
                        subtitle: "Reproduce una canción para ver sus detalles técnicos"
                    ) { EmptyView() }
                }
            }
        }
    }

    private var isBitPerfect: Bool {
        audioEngine.sourceSampleRate > 0 && audioEngine.outputSampleRate > 0 &&
        abs(audioEngine.sourceSampleRate - audioEngine.outputSampleRate) < 1
    }

    // MARK: - About

    private var aboutSection: some View {
        settingsSection(title: "Aurora Player", icon: "sparkles") {
            VStack(spacing: 0) {
                settingRow(
                    icon: "info.circle.fill",
                    title: "Versión",
                    subtitle: "1.0"
                ) { EmptyView() }

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
                        Image(systemName: "chevron.right")
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
                ) { EmptyView() }
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
            .opaqueGlass(cornerRadius: 22)
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
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))

                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
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