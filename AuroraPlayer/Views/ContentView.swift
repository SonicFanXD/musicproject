import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var audioEngine = AudioEngine()
    @StateObject private var fileAccessService = FileAccessService()

    @State private var showFolderPicker = false
    @State private var hasRestored = false

    @State private var selectedCategory: LibraryCategory = .songs
    @State private var searchText = ""
    @State private var showLogs = false
    @State private var showPlaylists = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                VStack(spacing: 0) {
                    // Modern category selector
                    categoryPicker

                    List {
                        libraryContent
                            .id(selectedCategory)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .searchable(
                        text: $searchText,
                        prompt: "Buscar en tu biblioteca"
                    )
                }
            }
            .navigationTitle("Aurora Player")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            showPlaylists = true
                        } label: {
                            Image(systemName: "music.note.list")
                        }

                        Button {
                            showLogs = true
                        } label: {
                            Image(systemName: "doc.text.magnifyingglass")
                        }

                        Button {
                            showFolderPicker = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showFolderPicker) {
                FolderPickerView(fileAccessService: fileAccessService)
            }
            .sheet(isPresented: $showLogs) {
                LogsView()
            }
            .sheet(isPresented: $showPlaylists) {
                PlaylistsView(fileAccessService: fileAccessService, audioEngine: audioEngine)
            }
            .onAppear {
                restoreLibraryIfNeeded()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PlayerBar(audioEngine: audioEngine)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
        }
    }

    // MARK: - Category Picker (iOS 16 native picker with enhanced design)

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(LibraryCategory.allCases, id: \.self) { category in
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            selectedCategory = category
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: categoryIcon(for: category))
                                .font(.system(size: 14, weight: .semibold))

                            Text(category.title)
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(selectedCategory == category ? .white : .secondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background {
                            if selectedCategory == category {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .fill(Color.accentColor)

                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    .white.opacity(0.15),
                                                    .white.opacity(0.05),
                                                    .clear
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                }
                                .shadow(color: Color.accentColor.opacity(0.4), radius: 8, x: 0, y: 4)
                            } else {
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .fill(Color.secondary.opacity(0.12))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
    }

    private func categoryIcon(for category: LibraryCategory) -> String {
        switch category {
        case .songs: return "music.note"
        case .albums: return "square.stack"
        case .artists: return "person.2"
        case .playlists: return "music.note.list"
        }
    }

    // MARK: - Library Content

    @ViewBuilder
    private var libraryContent: some View {
        switch selectedCategory {
        case .songs:
            songsSection
        case .albums:
            albumsSection
        case .artists:
            artistsSection
        case .playlists:
            playlistsSection
        }
    }

    // MARK: - Songs

    @ViewBuilder
    private var songsSection: some View {
        let currentFilteredSongs = filteredSongs

        if currentFilteredSongs.isEmpty {
            ContentUnavailableLibraryView(
                icon: "music.note.list",
                title: searchText.isEmpty
                    ? "Tu biblioteca está vacía"
                    : "No se encontraron canciones",
                message: searchText.isEmpty
                    ? "Agrega una carpeta con tu música para comenzar."
                    : "Prueba con otro término de búsqueda."
            )
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } else {
            ForEach(currentFilteredSongs) { song in
                songRow(song)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Albums (Vertical list - each row is a proper List row)

    @ViewBuilder
    private var albumsSection: some View {
        let albums = filteredAlbums

        if albums.isEmpty {
            ContentUnavailableLibraryView(
                icon: "square.stack",
                title: "No hay álbumes",
                message: searchText.isEmpty
                    ? "Tus álbumes aparecerán aquí."
                    : "No se encontraron álbumes."
            )
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } else {
            ForEach(albums) { album in
                NavigationLink {
                    AlbumDetailView(album: album, audioEngine: audioEngine)
                } label: {
                    albumListRow(album)
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            }
        }
    }

    // MARK: - Artists (Vertical list - each row is a proper List row)

    @ViewBuilder
    private var artistsSection: some View {
        let artists = filteredArtists

        if artists.isEmpty {
            ContentUnavailableLibraryView(
                icon: "person.2",
                title: "No hay artistas",
                message: searchText.isEmpty
                    ? "Tus artistas aparecerán aquí."
                    : "No se encontraron artistas."
            )
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } else {
            ForEach(artists) { artist in
                NavigationLink {
                    ArtistDetailView(artist: artist, audioEngine: audioEngine)
                } label: {
                    artistListRow(artist)
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            }
        }
    }

    // MARK: - Playlists

    @ViewBuilder
    private var playlistsSection: some View {
        let playlists = fileAccessService.playlists

        if playlists.isEmpty {
            ContentUnavailableLibraryView(
                icon: "music.note.list",
                title: "Sin listas",
                message: "Crea tu primera lista de reproducción para organizar tu música."
            )
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } else {
            // Grid layout for playlists
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(playlists) { playlist in
                        NavigationLink {
                            PlaylistDetailView(
                                playlist: playlist,
                                fileAccessService: fileAccessService,
                                audioEngine: audioEngine
                            )
                        } label: {
                            playlistLibraryCard(playlist: playlist)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 16, leading: 0, bottom: 16, trailing: 0))
        }
    }

    // MARK: - Song Row (iOS 16 native design)
    @ViewBuilder
    private func songRow(_ song: Song) -> some View {
        let isCurrent = audioEngine.currentSong?.id == song.id

        Button {
            playSong(song)
        } label: {
            HStack(spacing: 16) {
                // Artwork
                artworkView(for: song)

                // Song info with enhanced typography
                VStack(alignment: .leading, spacing: 6) {
                    Text(song.displayName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(isCurrent ? Color.accentColor : .primary)
                        .lineLimit(1)

                    Text(song.displaySubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if !song.album.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "opticaldisc")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)

                            Text(song.album)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 12)

                // Playing indicator or duration
                if isCurrent {
                    HStack(spacing: 4) {
                        ForEach(0..<3) { _ in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.accentColor)
                                .frame(width: 3, height: 16)
                                .offset(y: CGFloat.random(in: -3...3))
                                .animation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true), value: isCurrent)
                        }
                    }
                } else {
                    Text(formatDuration(song.duration))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }

                // Add to playlist button
                Menu {
                    if fileAccessService.playlists.isEmpty {
                        Text("No hay listas disponibles")
                    } else {
                        ForEach(fileAccessService.playlists) { playlist in
                            Button {
                                fileAccessService.addSongToPlaylist(song, playlist: playlist)
                            } label: {
                                Label(playlist.name, systemImage: "music.note.list")
                            }
                        }
                    }
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentColor.opacity(0.1))
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.secondary.opacity(0.05))
                }
            }
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
        .listRowBackground(Color.clear)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    // MARK: - Artwork (iOS 16 native design)
    @ViewBuilder
    private func artworkView(for song: Song) -> some View {
        if let artwork = song.artwork {
            Image(uiImage: artwork)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
        }
    }

    // MARK: - Filtering (optimized with cached query)

    private var normalizedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var filteredSongs: [Song] {
        let songs = fileAccessService.songs
        let query = normalizedQuery
        guard !query.isEmpty else { return songs }

        return songs.filter { song in
            song.title.lowercased().contains(query) ||
            song.artist.lowercased().contains(query) ||
            song.album.lowercased().contains(query)
        }
    }

    private var filteredAlbums: [Album] {
        let albums = fileAccessService.albums
        let query = normalizedQuery
        guard !query.isEmpty else { return albums }

        return albums.filter { album in
            album.name.lowercased().contains(query) ||
            album.artist.lowercased().contains(query)
        }
    }

    private var filteredArtists: [Artist] {
        let artists = fileAccessService.artists
        let query = normalizedQuery
        guard !query.isEmpty else { return artists }

        return artists.filter {
            $0.name.lowercased().contains(query)
        }
    }

    private var filteredPlaylists: [Playlist] {
        let playlists = fileAccessService.playlists

        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return playlists
        }

        let query = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return playlists.filter {
            $0.name.lowercased().contains(query) ||
            $0.description.lowercased().contains(query)
        }
    }

    // MARK: - Playback

    private func playSong(_ song: Song) {
        // Feedback háptico suave al iniciar reproducción: detalle pequeño
        // pero es justo lo que hace sentir "premium" a un reproductor.
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        audioEngine.play(song: song, from: fileAccessService.songs)
    }

    // MARK: - Restore

    private func restoreLibraryIfNeeded() {
        guard !hasRestored else { return }
        hasRestored = true
        audioEngine.restoreState(with: fileAccessService.songs)
    }
}

// MARK: - Library Category
enum LibraryCategory: String, CaseIterable {
    case songs
    case albums
    case artists
    case playlists

    var title: String {
        switch self {
        case .songs:
            return "Canciones"
        case .albums:
            return "Álbumes"
        case .artists:
            return "Artistas"
        case .playlists:
            return "Listas"
        }
    }
}

// MARK: - Album Row (iOS 16 native design)
struct AlbumLibraryRow: View {
    let album: Album

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Album artwork with native design
            Group {
                if let artwork = album.artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 140, height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 140, height: 140)
                        .overlay {
                            Image(systemName: "square.stack")
                                .font(.system(size: 35))
                                .foregroundStyle(.secondary)
                        }
                }
            }

            // Album info with native typography
            VStack(alignment: .leading, spacing: 4) {
                Text(album.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(album.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text("\(album.songs.count) canciones")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 140)
        .padding(.vertical, 8)
    }
}

// MARK: - Artist Row (iOS 16 native design)
struct ArtistLibraryRow: View {
    let artist: Artist

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Artist artwork with native circular design
            Group {
                if let artwork = artist.artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 140, height: 140)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 140, height: 140)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 35))
                                .foregroundStyle(.secondary)
                        }
                }
            }

            // Artist info with native typography
            VStack(alignment: .leading, spacing: 4) {
                Text(artist.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("\(artist.songs.count) canciones")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 140)
        .padding(.vertical, 8)
    }
}

// MARK: - Playlist Library Card (iOS 16 native design)
struct playlistLibraryCard: View {
    let playlist: Playlist

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Playlist artwork with native design
            Group {
                if let artwork = playlist.artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 140, height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.accentColor.opacity(0.3),
                                        Color.accentColor.opacity(0.15)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 140, height: 140)

                        Image(systemName: "music.note.list")
                            .font(.system(size: 35))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }

            // Playlist info with native typography
            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("\(playlist.songIDs.count) canciones")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 140)
        .padding(.vertical, 8)
    }
}

// MARK: - Album List Row (Vertical list - optimized for iPhone 8 Plus)
private func albumListRow(_ album: Album) -> some View {
    HStack(spacing: 16) {
        // Album artwork (square aspect ratio preserved)
        Group {
            if let artwork = album.artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: "square.stack")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                    }
            }
        }

        // Album info
        VStack(alignment: .leading, spacing: 4) {
            Text(album.name)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(album.artist)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text("\(album.songs.count) canciones")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }

        Spacer()

        Image(systemName: "chevron.right")
            .font(.caption)
            .foregroundStyle(.tertiary)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.secondary.opacity(0.05))
    }
}

// MARK: - Artist List Row (Vertical list - optimized for iPhone 8 Plus)
private func artistListRow(_ artist: Artist) -> some View {
    HStack(spacing: 16) {
        // Artist artwork (circular aspect ratio preserved)
        Group {
            if let artwork = artist.artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                    }
            }
        }

        // Artist info
        VStack(alignment: .leading, spacing: 4) {
            Text(artist.name)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text("\(artist.songs.count) canciones")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Spacer()

        Image(systemName: "chevron.right")
            .font(.caption)
            .foregroundStyle(.tertiary)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.secondary.opacity(0.05))
    }
}

// MARK: - Empty Library (Enhanced iOS 16 design)
struct ContentUnavailableLibraryView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 80, height: 80)

                Image(systemName: icon)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.primary)

            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .enhancedGlass(cornerRadius: 24)
    }
}