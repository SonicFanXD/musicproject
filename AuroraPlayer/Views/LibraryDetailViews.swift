import SwiftUI
import UIKit

struct AlbumDetailView: View {
    let album: String
    let songs: [Song]
    @ObservedObject var audioEngine: AudioEngine

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    artwork(for: songs.first).frame(width: 100, height: 100).clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(album).font(.title3.bold())
                        Text(songs.first?.albumArtist ?? "Artista desconocido").foregroundStyle(.secondary)
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
                ForEach(albumNames, id: \.self) { album in
                    let albumSongs = songs.filter { ($0.album.isEmpty ? "Sin álbum" : $0.album) == album }
                    NavigationLink { AlbumDetailView(album: album, songs: albumSongs, audioEngine: audioEngine) } label: {
                        HStack(spacing: 12) {
                            artwork(for: albumSongs.first).frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading) { Text(album); Text("\(albumSongs.count) canciones").font(.caption).foregroundStyle(.secondary) }
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

    private var albumNames: [String] { Array(Set(songs.map { $0.album.isEmpty ? "Sin álbum" : $0.album })).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending } }
    @ViewBuilder private func artwork(for song: Song?) -> some View {
        if let data = song?.artworkData, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFill() }
        else { Image(systemName: "music.note").frame(width: 44, height: 44).background(.quaternary, in: RoundedRectangle(cornerRadius: 6)) }
    }
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
