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

    // MARK: - Category Picker (Enhanced with smooth animations)

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(LibraryCategory.allCases, id: \.self) { category in
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            selectedCategory = category
                        }
                    } label: {
                        Text(category.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selectedCategory == category ? .white : .secondary)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background {
                                if selectedCategory == category {
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color.accentColor,
                                                    Color.accentColor.opacity(0.8)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .shadow(color: Color.accentColor.opacity(0.3), radius: 4, x: 0, y: 2)
                                } else {
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .fill(Color.secondary.opacity(0.12))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 10)
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
        }
    }

    // MARK: - Songs

    @ViewBuilder
    private var songsSection: some View {
        let filteredSongs = filteredSongs

        if filteredSongs.isEmpty {
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
            ForEach(filteredSongs) { song in
                songRow(song)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Albums

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
            // Grid layout for albums
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(albums) { album in
                        NavigationLink {
                            AlbumDetailView(album: album, audioEngine: audioEngine)
                        } label: {
                            AlbumLibraryRow(album: album)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 16, leading: 0, bottom: 16, trailing: 0))
        }
    }

    // MARK: - Artists

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
            // Grid layout for artists
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(artists) { artist in
                        NavigationLink {
                            ArtistDetailView(artist: artist, audioEngine: audioEngine)
                        } label: {
                            ArtistLibraryRow(artist: artist)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 16, leading: 0, bottom: 16, trailing: 0))
        }
    }

    // MARK: - Song Row (Modern Design)
    @ViewBuilder
    private func songRow(_ song: Song) -> some View {
        let isCurrent = audioEngine.currentSong?.id == song.id

        Button {
            playSong(song)
        } label: {
            HStack(spacing: 16) {
                // Modern artwork
                artworkView(for: song)

                // Song info with better typography
                VStack(alignment: .leading, spacing: 6) {
                    Text(song.title)
                        .font(.system(size: 17, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? Color.accentColor : .primary)
                        .lineLimit(1)

                    Text(song.artist)
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if !song.album.isEmpty {
                        Text(song.album)
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
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
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.accentColor.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
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

    // MARK: - Artwork (Modern Design)
    @ViewBuilder
    private func artworkView(for song: Song) -> some View {
        if let artwork = song.artwork {
            ZStack {
                // Glow effect
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .blur(radius: 10)
                    .opacity(0.4)
                
                // Main artwork
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
            }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.secondary.opacity(0.25),
                                Color.secondary.opacity(0.15)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                    .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 3)

                Image(systemName: "music.note")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary.opacity(0.7))
            }
        }
    }

    // MARK: - Filtering

    private var filteredSongs: [Song] {
        let songs = fileAccessService.songs

        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return songs
        }

        let query = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return songs.filter { song in
            song.title.lowercased().contains(query) ||
            song.artist.lowercased().contains(query) ||
            song.album.lowercased().contains(query)
        }
    }

    private var filteredAlbums: [Album] {
        let albums = fileAccessService.albums

        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return albums
        }

        let query = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return albums.filter { album in
            album.name.lowercased().contains(query) ||
            album.artist.lowercased().contains(query)
        }
    }

    private var filteredArtists: [Artist] {
        let artists = fileAccessService.artists

        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return artists
        }

        let query = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return artists.filter {
            $0.name.lowercased().contains(query)
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

    var title: String {
        switch self {
        case .songs:
            return "Canciones"
        case .albums:
            return "Álbumes"
        case .artists:
            return "Artistas"
        }
    }
}

// MARK: - Album Row (Modern Design)
struct AlbumLibraryRow: View {
    let album: Album

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Album artwork with modern design
            Group {
                if let artwork = album.artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 140, height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 6)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.secondary.opacity(0.25),
                                        Color.secondary.opacity(0.15)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 140, height: 140)
                            .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)

                        Image(systemName: "square.stack")
                            .font(.system(size: 35))
                            .foregroundStyle(.secondary.opacity(0.7))
                    }
                }
            }

            // Album info
            VStack(alignment: .leading, spacing: 4) {
                Text(album.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(album.artist)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text("\(album.songs.count) canciones")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 140)
        .padding(.vertical, 8)
    }
}

// MARK: - Artist Row (Enhanced)
struct ArtistLibraryRow: View {
    let artist: Artist

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Artist artwork with circular design
            Group {
                if let artwork = artist.artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 140, height: 140)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 6)
                } else {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.secondary.opacity(0.25),
                                        Color.secondary.opacity(0.15)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 140, height: 140)
                            .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)

                        Image(systemName: "person.fill")
                            .font(.system(size: 35))
                            .foregroundStyle(.secondary.opacity(0.7))
                    }
                }
            }

            // Artist info
            VStack(alignment: .leading, spacing: 4) {
                Text(artist.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("\(artist.songs.count) canciones")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 140)
        .padding(.vertical, 8)
    }
}

// MARK: - Empty Library
struct ContentUnavailableLibraryView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 34))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .opaqueGlass(cornerRadius: 20, tint: .white)
    }
}