import SwiftUI

struct SettingsView: View {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var fileAccessService: FileAccessService

    @State private var showFolderPicker = false
    @State private var showLogs = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Aleatorio", isOn: Binding(
                        get: { audioEngine.isShuffleEnabled },
                        set: { _ in audioEngine.toggleShuffle() }
                    ))

                    Button {
                        audioEngine.cycleRepeatMode()
                    } label: {
                        HStack {
                            Text("Repetición")
                            Spacer()
                            Text(repeatDescription)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Reproducción")
                }

                Section {
                    Button {
                        showFolderPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "folder.fill")
                            Text("Carpetas de música")
                        }
                    }

                    Button {
                        fileAccessService.refreshAllFolders()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Actualizar biblioteca")
                            if fileAccessService.isScanning {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .disabled(fileAccessService.isScanning)
                } header: {
                    Text("Biblioteca")
                }

                Section {
                    HStack {
                        Text("Canciones")
                        Spacer()
                        Text("\(fileAccessService.songs.count)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Álbumes")
                        Spacer()
                        Text("\(fileAccessService.albums.count)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Artistas")
                        Spacer()
                        Text("\(fileAccessService.artists.count)")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Tu biblioteca")
                }

                Section {
                    Button {
                        showLogs = true
                    } label: {
                        HStack {
                            Image(systemName: "doc.text.magnifyingglass")
                            Text("Registros")
                        }
                    }

                    HStack {
                        Text("Versión")
                        Spacer()
                        Text("1.0")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Acerca de")
                }
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showFolderPicker) {
                FolderPickerView(fileAccessService: fileAccessService)
            }
            .sheet(isPresented: $showLogs) {
                LogsView()
            }
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
