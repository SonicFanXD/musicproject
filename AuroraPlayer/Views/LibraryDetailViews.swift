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
        ZStack {
            albumBackground

            List {
                Section {
                    albumHeader
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                }

                Section {
                    if songs.isEmpty {
                        emptyView
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(songs) { song in
                            DetailSongRow(
                                song: song,
                                isCurrent: audioEngine.currentSong?.id == song.id,
                                isPlaying: audioEngine.isPlaying
                            ) {
                                audioEngine.play(song: song, from: songs)
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
                            .transition(.opacity)
                        }
                    }
                } header: {
                    Text("Canciones")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .textCase(nil)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(album.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    // MARK: - Background

    @ViewBuilder
    private var albumBackground: some View {
        if let artwork = album.artwork {
            GeometryReader { geometry in
                ZStack {
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .blur(radius: 55)
                        .opacity(0.28)
                        .scaleEffect(1.2)

                    LinearGradient(
                        colors: [
                            Color(uiColor: .systemBackground).opacity(0.30),
                            Color(uiColor: .systemBackground).opacity(0.82),
                            Color(uiColor: .systemBackground).opacity(0.98)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .ignoresSafeArea()
            }
        } else {
            AppBackground()
        }
    }

    // MARK: - Header

    private var albumHeader: some View {
        VStack(spacing: 18) {
            artworkView

            VStack(spacing: 6) {
                Text(album.name)
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text(album.artist)
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text("\(songs.count) canciones")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Button {
                guard let firstSong = songs.first else { return }
                audioEngine.play(song: firstSong, from: songs)
            } label: {
                Label("Reproducir álbum", systemImage: "play.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.plain)
            .opaqueGlass(cornerRadius: 16, tint: .accentColor)
            .scaleEffect(0.98)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .opaqueGlass(cornerRadius: 24, tint: .white)
    }

    // MARK: - Artwork

    private var artworkView: some View {
        Group {
            if let artwork = album.artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 230, height: 230)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(.white.opacity(0.22), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.30), radius: 20, y: 10)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.thinMaterial)

                    Image(systemName: "square.stack")
                        .font(.system(size: 55))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 230, height: 230)
            }
        }
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            Text("No hay canciones")
                .font(.headline)

            Text("Este álbum no contiene canciones reproducibles.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .opaqueGlass(cornerRadius: 18, tint: .white)
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
        ZStack {
            artistBackground

            List {
                Section {
                    artistHeader
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                }

                if !albums.isEmpty {
                    Section {
                        ForEach(albums) { album in
                            NavigationLink {
                                AlbumDetailView(album: album, audioEngine: audioEngine)
                            } label: {
                                HStack(spacing: 12) {
                                    albumArtwork(album)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(album.name)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)

                                        Text("\(album.songs.count) canciones")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 8)
                                .opaqueGlass(cornerRadius: 16, tint: .white)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
                            .transition(.opacity)
                        }
                    } header: {
                        Text("Álbumes")
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .textCase(nil)
                    }
                }

                Section {
                    if songs.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 32))
                                .foregroundStyle(.secondary)

                            Text("No hay canciones")
                                .font(.headline)

                            Text("No se encontraron canciones para este artista.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                        .opaqueGlass(cornerRadius: 18, tint: .white)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } else {
                        ForEach(songs) { song in
                            DetailSongRow(
                                song: song,
                                isCurrent: audioEngine.currentSong?.id == song.id,
                                isPlaying: audioEngine.isPlaying
                            ) {
                                audioEngine.play(song: song, from: songs)
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
                            .transition(.opacity)
                        }
                    }
                } header: {
                    Text("Canciones")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .textCase(nil)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    // MARK: - Background

    @ViewBuilder
    private var artistBackground: some View {
        if let artwork = artist.artwork {
            GeometryReader { geometry in
                ZStack {
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .blur(radius: 60)
                        .opacity(0.25)
                        .scaleEffect(1.25)

                    LinearGradient(
                        colors: [
                            Color(uiColor: .systemBackground).opacity(0.25),
                            Color(uiColor: .systemBackground).opacity(0.84),
                            Color(uiColor: .systemBackground).opacity(0.98)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .ignoresSafeArea()
            }
        } else {
            AppBackground()
        }
    }

    // MARK: - Header

    private var artistHeader: some View {
        VStack(spacing: 16) {
            if let artwork = artist.artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 150, height: 150)
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.22), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
            } else {
                ZStack {
                    Circle()
                        .fill(.thinMaterial)

                    Image(systemName: "person.fill")
                        .font(.system(size: 55))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 150, height: 150)
            }

            VStack(spacing: 5) {
                Text(artist.name)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.primary)
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
                    Label("Reproducir", systemImage: "play.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .buttonStyle(.plain)
                .opaqueGlass(cornerRadius: 16, tint: .accentColor)
                .scaleEffect(0.98)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .opaqueGlass(cornerRadius: 24, tint: .white)
    }

    // MARK: - Album Artwork

    @ViewBuilder
    private func albumArtwork(_ album: Album) -> some View {
        if let artwork = album.artwork {
            Image(uiImage: artwork)
                .resizable()
                .scaledToFill()
                .frame(width: 55, height: 55)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(.thinMaterial)

                Image(systemName: "square.stack")
                    .foregroundStyle(.secondary)
            }
            .frame(width: 55, height: 55)
        }
    }
}

// MARK: - Detail Song Row
struct DetailSongRow: View {
    let song: Song
    let isCurrent: Bool
    let isPlaying: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                artwork

                VStack(alignment: .leading, spacing: 4) {
                    Text(song.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isCurrent ? Color.accentColor : .primary)
                        .lineLimit(1)

                    if !song.album.isEmpty {
                        Text(song.album)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if isCurrent && isPlaying {
                    Group {
                        if #available(iOS 17.0, *) {
                            Image(systemName: "waveform")
                                .font(.headline)
                                .foregroundStyle(Color.accentColor)
                                .symbolEffect(.variableColor.iterative, options: .repeating)
                        } else {
                            Image(systemName: "waveform")
                                .font(.headline)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                } else if isCurrent {
                    Image(systemName: "pause.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                } else {
                    Image(systemName: "play.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .opaqueGlass(cornerRadius: 15, tint: isCurrent ? .accentColor : .white)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Artwork

    @ViewBuilder
    private var artwork: some View {
        if let image = song.artwork {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.thinMaterial)

                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
            }
            .frame(width: 52, height: 52)
        }
    }
}