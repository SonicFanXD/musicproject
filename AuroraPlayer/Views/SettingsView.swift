import SwiftUI

struct SettingsView: View {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var fileAccessService: FileAccessService

    @State private var showFolderPicker = false
    @State private var showLogs = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: 28) {
                        // Playback Section
                        VStack(spacing: 16) {
                            HStack {
                                Image(systemName: "play.circle.fill")
                                    .foregroundStyle(Color.accentColor)

                                Text("Reproducción")
                                    .font(.system(size: 18, weight: .semibold))
                            }
                            .padding(.horizontal, 4)

                            VStack(spacing: 0) {
                                settingsToggleRow(
                                    title: "Aleatorio",
                                    isOn: Binding(
                                        get: { audioEngine.isShuffleEnabled },
                                        set: { _ in audioEngine.toggleShuffle() }
                                    )
                                )
                                divider
                                settingsButtonRow(
                                    title: "Repetición",
                                    value: repeatDescription,
                                    action: { audioEngine.cycleRepeatMode() }
                                )
                            }
                            .background {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(.ultraThinMaterial)
                            }
                        }

                        // Library Section
                        VStack(spacing: 16) {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(Color.accentColor)

                                Text("Biblioteca")
                                    .font(.system(size: 18, weight: .semibold))
                            }
                            .padding(.horizontal, 4)

                            VStack(spacing: 0) {
                                settingsButtonRow(
                                    title: "Carpetas de música",
                                    icon: "folder.fill",
                                    action: { showFolderPicker = true }
                                )
                                divider
                                settingsButtonRow(
                                    title: "Actualizar biblioteca",
                                    icon: "arrow.clockwise",
                                    action: { fileAccessService.refreshAllFolders() },
                                    isDisabled: fileAccessService.isScanning,
                                    trailing: fileAccessService.isScanning ? AnyView(ProgressView().controlSize(.small)) : nil
                                )
                            }
                            .background {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(.ultraThinMaterial)
                            }
                        }

                        // Library Stats Section
                        VStack(spacing: 16) {
                            HStack {
                                Image(systemName: "chart.bar.fill")
                                    .foregroundStyle(Color.accentColor)

                                Text("Tu biblioteca")
                                    .font(.system(size: 18, weight: .semibold))
                            }
                            .padding(.horizontal, 4)

                            VStack(spacing: 0) {
                                infoRow(title: "Canciones", value: "\(fileAccessService.songs.count)")
                                divider
                                infoRow(title: "Álbumes", value: "\(fileAccessService.albums.count)")
                                divider
                                infoRow(title: "Artistas", value: "\(fileAccessService.artists.count)")
                            }
                            .background {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(.ultraThinMaterial)
                            }
                        }

                        // About Section
                        VStack(spacing: 16) {
                            HStack {
                                Image(systemName: "info.circle.fill")
                                    .foregroundStyle(Color.accentColor)

                                Text("Acerca de")
                                    .font(.system(size: 18, weight: .semibold))
                            }
                            .padding(.horizontal, 4)

                            VStack(spacing: 0) {
                                settingsButtonRow(
                                    title: "Registros",
                                    icon: "doc.text.magnifyingglass",
                                    action: { showLogs = true }
                                )
                                divider
                                infoRow(title: "Versión", value: "1.0")
                            }
                            .background {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(.ultraThinMaterial)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
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
    }

    private func settingsToggleRow(title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
    }

    private func settingsButtonRow(title: String, icon: String? = nil, value: String? = nil, action: @escaping () -> Void, isDisabled: Bool = false, trailing: AnyView? = nil) -> some View {
        Button(action: action) {
            HStack {
                if let icon = icon {
                    Image(systemName: icon)
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                }

                Text(title)
                    .foregroundStyle(.primary)

                Spacer()

                if let value = value {
                    Text(value)
                        .foregroundStyle(.secondary)
                }

                if let trailing = trailing {
                    trailing
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .disabled(isDisabled)
        .buttonStyle(.plain)
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private var divider: some View {
        Divider()
            .opacity(0.12)
            .padding(.leading, 18)
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
