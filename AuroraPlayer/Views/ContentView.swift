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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let song = audioEngine.currentSong { PlayerBar(audioEngine: audioEngine, song: song) }
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
                NavigationLink { AlbumDetailView(album: album.title, albumArtist: album.artist, songs: album.songs, audioEngine: audioEngine) } label: {
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
            ForEach(artists) { artist in
                NavigationLink { ArtistDetailView(artist: artist.name, songs: artist.songs, audioEngine: audioEngine) } label: {
                    HStack(spacing: 12) {
                        artwork(for: artist.songs.first).frame(width: 48, height: 48).clipShape(Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(artist.name).lineLimit(1)
                            Text("\(artist.songs.count) canciones · \(artist.albumCount) álbumes").font(.caption).foregroundStyle(.secondary)
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
        Dictionary(grouping: filteredSongs) { song in
            song.album.isEmpty ? "\u{001F}\(song.url.absoluteString)" : song.album.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        }
            .map { key, songs in
                let sample = songs[0]
                return AlbumGroup(id: key, title: sample.album.isEmpty ? sample.title : sample.album, artist: canonicalAlbumArtist(for: songs), songs: songs, releaseDate: songs.compactMap(\.releaseDate).min())
            }
            .sorted {
                let left = $0.releaseDate ?? .distantPast
                let right = $1.releaseDate ?? .distantPast
                if left != right { return left > right }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }

    // Si falta Album Artist, se usa el artista predominante del álbum completo,
    // nunca el de una pista de colaboración aislada.
    private var artists: [ArtistGroup] {
        Dictionary(grouping: albums, by: \.artist).map { name, albums in
            ArtistGroup(id: name, name: name, songs: albums.flatMap(\.songs), albumCount: albums.count)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func canonicalAlbumArtist(for songs: [Song]) -> String {
        let explicit = songs.compactMap { $0.albumArtist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0.albumArtist }
        if let artist = mostFrequent(explicit) { return artist }
        let inferred = songs.compactMap { song -> String? in
            let name = song.artist.replacingOccurrences(of: "(?i)\\s*(feat\\.?|ft\\.?).*$", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : name
        }
        return mostFrequent(inferred) ?? "Artista desconocido"
    }

    private func mostFrequent(_ values: [String]) -> String? {
        guard !values.isEmpty else { return nil }
        let counts = Dictionary(grouping: values, by: { $0 }).mapValues(\.count)
        return values.max { counts[$0, default: 0] < counts[$1, default: 0] }
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
    let releaseDate: Date?
}

private struct ArtistGroup: Identifiable {
    let id: String
    let name: String
    let songs: [Song]
    let albumCount: Int
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
