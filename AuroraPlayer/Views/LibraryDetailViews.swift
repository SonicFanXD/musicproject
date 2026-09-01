import SwiftUI
import UIKit

struct AlbumDetailView: View {
    let album: String
    let albumArtist: String
    let songs: [Song]
    @ObservedObject var audioEngine: AudioEngine

    var body: some View {
        ZStack {
            albumBackground
        List {
            Section {
                HStack(spacing: 16) {
                    artwork(for: songs.first).frame(width: 100, height: 100).clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(album).font(.title3.bold())
                        Text(albumArtist).foregroundStyle(.secondary)
                        Text("\(songs.count) canciones").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 6)
            }
            if hasDiscNumbers {
                ForEach(discs, id: \.self) { disc in
                    Section("Disco \(disc)") {
                        ForEach(songs.filter { $0.discNumber == disc }.sorted(by: trackOrder)) { song in
                            DetailSongRow(song: song, audioEngine: audioEngine, queue: songs)
                        }
                    }
                }
                if !songsWithoutDiscNumber.isEmpty {
                    Section("Canciones") {
                        ForEach(songsWithoutDiscNumber.sorted(by: trackOrder)) { song in
                            DetailSongRow(song: song, audioEngine: audioEngine, queue: songs)
                        }
                    }
                }
            } else {
                Section("Canciones") {
                    ForEach(songs.sorted(by: trackOrder)) { song in
                        DetailSongRow(song: song, audioEngine: audioEngine, queue: songs)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
        }
        .navigationTitle(album)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var discs: [Int] { Array(Set(songs.compactMap(\.discNumber))).sorted() }
    private var hasDiscNumbers: Bool { !discs.isEmpty }
    private var songsWithoutDiscNumber: [Song] { songs.filter { $0.discNumber == nil } }
    private func trackOrder(_ lhs: Song, _ rhs: Song) -> Bool {
        let leftTrack = lhs.trackNumber > 0 ? lhs.trackNumber : .max
        let rightTrack = rhs.trackNumber > 0 ? rhs.trackNumber : .max
        if leftTrack != rightTrack { return leftTrack < rightTrack }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
    @ViewBuilder private func artwork(for song: Song?) -> some View {
        if let data = song?.artworkData, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill()
        } else { Image(systemName: "music.note").foregroundStyle(.secondary) }
    }

    @ViewBuilder private var albumBackground: some View {
        if let data = songs.first?.artworkData, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill().blur(radius: 24).scaleEffect(1.12).opacity(0.32).ignoresSafeArea()
        } else { Color(uiColor: .systemBackground).ignoresSafeArea() }
        LinearGradient(colors: [.black.opacity(0.20), .black.opacity(0.72)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
    }
}

struct ArtistDetailView: View {
    let artist: String
    let songs: [Song]
    @ObservedObject var audioEngine: AudioEngine

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    artwork(for: songs.first).frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(artist).font(.title3.bold())
                        Text("\(songs.count) canciones").foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 6)
            }
            Section("Álbumes") {
                ForEach(artistAlbums) { album in
                    let albumSongs = album.songs
                    NavigationLink { AlbumDetailView(album: album.title, albumArtist: artist, songs: albumSongs, audioEngine: audioEngine) } label: {
                        HStack(spacing: 12) {
                            artwork(for: albumSongs.first).frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading) { Text(album.title); Text("\(albumSongs.count) canciones").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            Section("Todas las canciones") {
                ForEach(songs) { song in DetailSongRow(song: song, audioEngine: audioEngine, queue: songs) }
            }
        }
        .navigationTitle(artist)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var artistAlbums: [ArtistAlbumGroup] {
        Dictionary(grouping: songs) { song in
            let title = song.album.isEmpty ? "Sin álbum" : song.album
            return title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        }
        .map { _, songs in
            ArtistAlbumGroup(title: songs.first?.album.nilIfEmpty ?? "Sin álbum", songs: songs, releaseDate: songs.compactMap(\.releaseDate).min())
        }
        .sorted {
            let left = $0.releaseDate ?? .distantPast
            let right = $1.releaseDate ?? .distantPast
            if left != right { return left > right }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }
    @ViewBuilder private func artwork(for song: Song?) -> some View {
        if let data = song?.artworkData, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFill() }
        else { Image(systemName: "music.note").frame(width: 44, height: 44).background(.quaternary, in: RoundedRectangle(cornerRadius: 6)) }
    }
}

private struct ArtistAlbumGroup: Identifiable {
    let title: String
    let songs: [Song]
    let releaseDate: Date?
    var id: String { title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
}

private struct DetailSongRow: View {
    let song: Song
    @ObservedObject var audioEngine: AudioEngine
    let queue: [Song]

    var body: some View {
        Button { audioEngine.play(song: song, from: queue) } label: {
            HStack {
                if song.trackNumber > 0 {
                    Text("\(song.trackNumber)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary).frame(width: 24, alignment: .trailing)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(song.title).foregroundStyle(.primary).lineLimit(1)
                    Text(song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(time(song.duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Image(systemName: audioEngine.currentSong?.id == song.id && audioEngine.isPlaying ? "speaker.wave.2.fill" : "music.note")
                    .foregroundStyle(audioEngine.currentSong?.id == song.id ? Color.accentColor : .secondary)
            }
        }.buttonStyle(.plain)
    }

    private func time(_ value: TimeInterval) -> String { String(format: "%d:%02d", Int(value) / 60, Int(value) % 60) }
}
