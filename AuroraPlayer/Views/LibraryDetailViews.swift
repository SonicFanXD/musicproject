import SwiftUI

// MARK: - Album Detail
struct AlbumDetailView: View {
    let album: Album
    @ObservedObject var audioEngine: AudioEngine
    @Environment(\.dismiss) private var dismiss

    private var songs: [Song] {
        album.songs
    }

    var body: some View {
        List {
            Section {
                albumHeader
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                ForEach(songs) { song in
                    Button {
                        audioEngine.play(song: song, from: songs)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(song.title)
                                    .font(.body)
                                Text(song.artist)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if audioEngine.currentSong?.id == song.id {
                                Image(systemName: "speaker.wave.2.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            } header: {
                Text("Canciones")
            }
        }
        .navigationTitle(album.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var albumHeader: some View {
        VStack(spacing: 16) {
            if let artwork = album.artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 200, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 200, height: 200)

                    Image(systemName: "square.stack")
                        .font(.system(size: 50))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 8) {
                Text(album.name)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(album.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("\(songs.count) canciones")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Button {
                if let firstSong = songs.first {
                    audioEngine.play(song: firstSong, from: songs)
                }
            } label: {
                Text("Reproducir todo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

// MARK: - Artist Detail
struct ArtistDetailView: View {
    let artist: Artist
    @ObservedObject var audioEngine: AudioEngine

    private var songs: [Song] {
        artist.songs
    }

    private var albums: [Album] {
        artist.albums
    }

    var body: some View {
        List {
            Section {
                artistHeader
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            if !albums.isEmpty {
                Section {
                    ForEach(albums) { album in
                        NavigationLink {
                            AlbumDetailView(album: album, audioEngine: audioEngine)
                        } label: {
                            HStack {
                                if let artwork = album.artwork {
                                    Image(uiImage: artwork)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 50, height: 50)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                } else {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.secondary.opacity(0.2))
                                            .frame(width: 50, height: 50)

                                        Image(systemName: "square.stack")
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(album.name)
                                        .font(.body)
                                    Text("\(album.songs.count) canciones")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }
                        }
                    }
                } header: {
                    Text("Álbumes")
                }
            }

            Section {
                ForEach(songs) { song in
                    Button {
                        audioEngine.play(song: song, from: songs)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(song.title)
                                    .font(.body)
                                Text(song.album)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if audioEngine.currentSong?.id == song.id {
                                Image(systemName: "speaker.wave.2.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            } header: {
                Text("Canciones")
            }
        }
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var artistHeader: some View {
        VStack(spacing: 16) {
            if let artwork = artist.artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 150, height: 150)
                    .clipShape(Circle())
            } else {
                ZStack {
                    Circle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 150, height: 150)

                    Image(systemName: "person.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 8) {
                Text(artist.name)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text("\(songs.count) canciones")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if !albums.isEmpty {
                    Text("\(albums.count) álbumes")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            if let firstSong = songs.first {
                Button {
                    audioEngine.play(song: firstSong, from: songs)
                } label: {
                    Text("Reproducir")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}