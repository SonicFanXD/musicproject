import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var audioEngine = AudioEngine()
    @StateObject private var library = FileAccessService()
    @State private var showSettings = false
    @State private var hasRestored = false
    @State private var searchText = ""
    @State private var category = LibraryCategory.songs

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                LibraryCategorySelector(selection: $category)
                    .padding(.horizontal).padding(.top, 8)
                List {
                    if library.isScanning {
                        Section("Cargando biblioteca") {
                            ProgressView(value: Double(library.scanProcessed), total: Double(max(library.scanTotal, 1)))
                            Text(progressDescription).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Section(category.title) {
                        if filteredSongs.isEmpty {
                            ContentUnavailableLibraryView(isScanning: library.isScanning)
                        } else {
                            libraryRows
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .searchable(text: $searchText, prompt: "Buscar canción, álbum o artista")

                if let song = audioEngine.currentSong { PlayerBar(audioEngine: audioEngine, song: song) }
            }
            .navigationTitle("Aurora Player")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "ellipsis.circle") }
                        .accessibilityLabel("Configuración")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView(library: library) }
        }
        .onChange(of: library.songs) { songs in
            guard !hasRestored, !songs.isEmpty else { return }
            audioEngine.restoreState(with: songs)
            hasRestored = true
        }
    }

    @ViewBuilder private var libraryRows: some View {
        switch category {
        case .songs:
            ForEach(filteredSongs) { song in songRow(song, queue: filteredSongs) }
        case .albums:
            ForEach(albums) { album in
                NavigationLink { AlbumDetailView(album: album.title, songs: album.songs, audioEngine: audioEngine) } label: {
                    HStack(spacing: 12) {
                        artwork(for: album.songs.first).frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 7))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(album.title).lineLimit(1)
                            Text(album.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }
        case .artists:
            ForEach(albumArtists, id: \.self) { artist in
                let artistSongs = filteredSongs.filter { $0.albumArtist == artist }
                NavigationLink { ArtistDetailView(artist: artist, songs: artistSongs, audioEngine: audioEngine) } label: {
                    HStack(spacing: 12) {
                        artwork(for: artistSongs.first).frame(width: 48, height: 48).clipShape(Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(artist).lineLimit(1)
                            Text("\(artistSongs.count) canciones").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var filteredSongs: [Song] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return library.songs }
        return library.songs.filter { [$0.title, $0.artist, $0.album, $0.albumArtist].contains { $0.localizedCaseInsensitiveContains(query) } }
    }

    private var albums: [AlbumGroup] {
        Dictionary(grouping: filteredSongs) { "\($0.albumArtist)\u{001F}\($0.album.isEmpty ? "Sin álbum" : $0.album)" }
            .map { key, songs in
                let sample = songs[0]
                return AlbumGroup(id: key, title: sample.album.isEmpty ? "Sin álbum" : sample.album, artist: sample.albumArtist.isEmpty ? "Artista de álbum no disponible" : sample.albumArtist, songs: songs)
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    // Solo se agrupa por el tag Album Artist; las colaboraciones no crean artistas extra.
    private var albumArtists: [String] {
        Array(Set(filteredSongs.compactMap { $0.albumArtist.isEmpty ? nil : $0.albumArtist }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var progressDescription: String {
        library.scanTotal == 0 ? "Buscando canciones…" : "\(library.scanProcessed) de \(library.scanTotal) canciones procesadas · faltan \(max(0, library.scanTotal - library.scanProcessed))"
    }

    private func songRow(_ song: Song, queue: [Song]) -> some View {
        Button { audioEngine.play(song: song, from: queue) } label: {
            HStack(spacing: 12) {
                artwork(for: song)
                VStack(alignment: .leading, spacing: 3) {
                    Text(song.title).foregroundStyle(.primary).lineLimit(1)
                    Text([song.artist, song.album].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(durationText(song.duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Image(systemName: audioEngine.currentSong?.id == song.id && audioEngine.isPlaying ? "speaker.wave.2.fill" : "music.note").foregroundStyle(audioEngine.currentSong?.id == song.id ? Color.accentColor : .secondary)
            }
        }.buttonStyle(.plain)
    }

    @ViewBuilder private func artwork(for song: Song?) -> some View {
        if let data = song?.artworkData, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill().frame(width: 48, height: 48).clipped()
        } else { Image(systemName: "music.note").frame(width: 48, height: 48).background(.quaternary, in: RoundedRectangle(cornerRadius: 7)) }
    }

    private func durationText(_ value: TimeInterval) -> String { String(format: "%d:%02d", Int(value) / 60, Int(value) % 60) }
}

private struct AlbumGroup: Identifiable {
    let id: String
    let title: String
    let artist: String
    let songs: [Song]
}

private enum LibraryCategory: String, CaseIterable, Identifiable {
    case songs, albums, artists
    var id: String { rawValue }
    var title: String { switch self { case .songs: return "Canciones"; case .albums: return "Álbumes"; case .artists: return "Artistas" } }
}

private struct LibraryCategorySelector: View {
    @Binding var selection: LibraryCategory
    var body: some View {
        HStack(spacing: 5) {
            ForEach(LibraryCategory.allCases) { item in
                Button { withAnimation(.easeInOut(duration: 0.18)) { selection = item } } label: {
                    Text(item.title).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 9)
                        .foregroundStyle(selection == item ? .primary : .secondary)
                        .background(selection == item ? Color.accentColor.opacity(0.16) : .clear, in: Capsule())
                }.buttonStyle(.plain)
            }
        }.padding(4).background(.quaternary, in: Capsule())
    }
}

private struct ContentUnavailableLibraryView: View {
    let isScanning: Bool
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: isScanning ? "music.note.list" : "music.note")
            Text(isScanning ? "Preparando tu música" : "Agrega música desde Configuración")
        }.foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 36)
    }
}
