import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var audioEngine = AudioEngine()
    @StateObject private var fileAccessService = FileAccessService()
    @State private var showFolderPicker = false
    @State private var showFilePicker = false
    @State private var showNowPlaying = false
    @State private var showLogs = false
    @State private var hasRestored = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    Section("Carpetas") {
                        ForEach(fileAccessService.folders) { folder in
                            Label(folder.displayName, systemImage: "folder")
                        }
                        .onDelete(perform: deleteFolders)

                        Button {
                            showFolderPicker = true
                        } label: {
                            Label("Agregar carpeta", systemImage: "folder.badge.plus")
                        }
                    }

                    Section("Archivos añadidos") {
                        ForEach(fileAccessService.files) { file in
                            Label(file.displayName, systemImage: "music.note")
                        }
                        .onDelete(perform: deleteFiles)
                        Button { showFilePicker = true } label: {
                            Label("Agregar canciones", systemImage: "music.note.list")
                        }
                    }

                    Section("Canciones (\(fileAccessService.songs.count))") {
                        if fileAccessService.songs.isEmpty {
                            Text("Agrega una carpeta para ver tus canciones aquí")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(fileAccessService.songs) { song in
                                songRow(song)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)

                if let currentSong = audioEngine.currentSong {
                    PlayerBar(audioEngine: audioEngine, song: currentSong)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Aurora Player")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showLogs = true } label: { Image(systemName: "text.alignleft") }
                        .accessibilityLabel("Ver registros")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        fileAccessService.refreshAllFolders()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .sheet(isPresented: $showFolderPicker) {
                FolderPickerView(isPresented: $showFolderPicker) { url in
                    fileAccessService.addFolder(url: url)
                }
            }
            .sheet(isPresented: $showFilePicker) {
                MusicFilePickerView(isPresented: $showFilePicker) { urls in fileAccessService.addFiles(urls: urls) }
            }
            .sheet(isPresented: $showNowPlaying) {
                NowPlayingView(audioEngine: audioEngine)
            }
            .sheet(isPresented: $showLogs) { LogsView() }
        }
        .onChange(of: fileAccessService.songs) { newSongs in
            guard !hasRestored, !newSongs.isEmpty else { return }
            audioEngine.restoreState(with: newSongs)
            hasRestored = true
        }
    }

    private func songRow(_ song: Song) -> some View {
        Button {
            AppLog.debug(.interface, "Selección de canción: \(song.title)")
            audioEngine.play(song: song, from: fileAccessService.songs)
        } label: {
            HStack(spacing: 12) {
                artwork(for: song)
                VStack(alignment: .leading, spacing: 3) {
                    Text(song.title).foregroundColor(.primary).lineLimit(1)
                    Text([song.artist, song.album].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if song.duration > 0 {
                    Text(durationText(song.duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Image(systemName: iconFor(song)).foregroundColor(audioEngine.currentSong?.id == song.id ? .accentColor : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func iconFor(_ song: Song) -> String {
        guard audioEngine.currentSong?.id == song.id else { return "music.note" }
        return audioEngine.isPlaying ? "speaker.wave.2.fill" : "play.fill"
    }

    private func durationText(_ value: TimeInterval) -> String {
        String(format: "%d:%02d", Int(value) / 60, Int(value) % 60)
    }

    @ViewBuilder private func artwork(for song: Song) -> some View {
        if let data = song.artworkData, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill().frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            Image(systemName: "music.note").frame(width: 44, height: 44).background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func deleteFolders(at offsets: IndexSet) {
        for index in offsets {
            fileAccessService.removeFolder(fileAccessService.folders[index])
        }
    }

    private func deleteFiles(at offsets: IndexSet) {
        for index in offsets { fileAccessService.removeFile(fileAccessService.files[index]) }
    }
}

#Preview {
    ContentView()
}
