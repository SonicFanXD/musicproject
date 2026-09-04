import SwiftUI

struct ContentView: View {
    @StateObject private var audioEngine = AudioEngine()
    @StateObject private var fileAccessService = FileAccessService()

    @State private var showFolderPicker = false
    @State private var hasRestored = false

    @State private var selectedCategory: LibraryCategory = .songs
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                // Fondo principal de Aurora Player
                AppBackground()

                VStack(spacing: 0) {
                    // Selector de biblioteca
                    LibraryCategorySelector(
                        selectedCategory: $selectedCategory
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 8)

                    // Biblioteca
                    List {
                        libraryContent
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .searchable(
                        text: $searchText,
                        placement: .navigationBarDrawer(
                            displayMode: .automatic
                        ),
                        prompt: "Buscar en tu biblioteca"
                    )
                }
            }
            .navigationTitle("Aurora Player")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showFolderPicker = true
                        } label: {
                            Label(
                                "Agregar carpeta",
                                systemImage: "folder.badge.plus"
                            )
                        }

                        Button {
                            fileAccessService.refreshAllFolders()
                        } label: {
                            Label(
                                "Actualizar biblioteca",
                                systemImage: "arrow.clockwise"
                            )
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                    }
                }
            }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showFolderPicker) {
                FolderPickerView(fileAccessService: fileAccessService)
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

    private var songsSection: some View {
        Section {
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
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(filteredSongs) { song in
                    songRow(song)
                }
            }
        } header: {
            HStack {
                Text("Canciones")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(filteredSongs.count)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .textCase(nil)
    }

    // MARK: - Albums

    private var albumsSection: some View {
        Section {
            let albums = filteredAlbums

            if albums.isEmpty {
                ContentUnavailableLibraryView(
                    icon: "square.stack",
                    title: "No hay álbumes",
                    message: searchText.isEmpty
                        ? "Tus álbumes aparecerán aquí."
                        : "No se encontraron álbumes."
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(albums) { album in
                    NavigationLink {
                        AlbumDetailView(
                            album: album,
                            audioEngine: audioEngine
                        )
                    } label: {
                        AlbumLibraryRow(album: album)
                            .padding(.vertical, 5)
                            .padding(.horizontal, 4)
                            .opaqueGlass(
                                cornerRadius: 16,
                                tint: .white
                            )
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(
                        EdgeInsets(
                            top: 5,
                            leading: 12,
                            bottom: 5,
                            trailing: 12
                        )
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
        } header: {
            HStack {
                Text("Álbumes")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(filteredAlbums.count)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .textCase(nil)
    }

    // MARK: - Artists

    private var artistsSection: some View {
        Section {
            let artists = filteredArtists

            if artists.isEmpty {
                ContentUnavailableLibraryView(
                    icon: "person.2",
                    title: "No hay artistas",
                    message: searchText.isEmpty
                        ? "Tus artistas aparecerán aquí."
                        : "No se encontraron artistas."
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(artists) { artist in
                    NavigationLink {
                        ArtistDetailView(
                            artist: artist,
                            audioEngine: audioEngine
                        )
                    } label: {
                        ArtistLibraryRow(artist: artist)
                            .padding(.vertical, 5)
                            .padding(.horizontal, 4)
                            .opaqueGlass(
                                cornerRadius: 16,
                                tint: .white
                            )
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(
                        EdgeInsets(
                            top: 5,
                            leading: 12,
                            bottom: 5,
                            trailing: 12
                        )
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
        } header: {
            HStack {
                Text("Artistas")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(filteredArtists.count)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .textCase(nil)
    }

    // MARK: - Song Row

    @ViewBuilder
    private func songRow(_ song: Song) -> some View {
        Button {
            playSong(song)
        } label: {
            HStack(spacing: 12) {
                artworkView(for: song)

                VStack(alignment: .leading, spacing: 4) {
                    Text(song.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(song.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if !song.album.isEmpty {
                        Text(song.album)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if audioEngine.currentSong?.id == song.id {
                    Group {
                        if #available(iOS 17.0, *) {
                            Image(systemName: "waveform")
                                .font(.headline)
                                .foregroundStyle(.tint)
                                .symbolEffect(
                                    .variableColor.iterative,
                                    options: .repeating
                                )
                        } else {
                            Image(systemName: "waveform")
                                .font(.headline)
                                .foregroundStyle(.tint)
                        }
                    }
                } else {
                    Image(systemName: "play.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .opaqueGlass(
                cornerRadius: 16,
                tint: audioEngine.currentSong?.id == song.id
                    ? .accentColor
                    : .white
            )
        }
        .buttonStyle(.plain)
        .listRowInsets(
            EdgeInsets(
                top: 5,
                leading: 12,
                bottom: 5,
                trailing: 12
            )
        )
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: - Artwork

    @ViewBuilder
    private func artworkView(for song: Song) -> some View {
        if let artwork = song.artwork {
            Image(uiImage: artwork)
                .resizable()
                .scaledToFill()
                .frame(width: 58, height: 58)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
                )
        } else {
            ZStack {
                RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
                .fill(.thinMaterial)

                Image(systemName: "music.note")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 58, height: 58)
        }
    }

    // MARK: - Filtering

    private var filteredSongs: [Song] {
        let songs = fileAccessService.songs

        guard !searchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
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

        guard !searchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
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

        guard !searchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
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

    var icon: String {
        switch self {
        case .songs:
            return "music.note.list"

        case .albums:
            return "square.stack"

        case .artists:
            return "person.2"
        }
    }
}

// MARK: - Category Selector
struct LibraryCategorySelector: View {
    @Binding var selectedCategory: LibraryCategory

    var body: some View {
        HStack(spacing: 8) {
            ForEach(LibraryCategory.allCases, id: \.self) { category in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedCategory = category
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: category.icon)

                        Text(category.title)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(
                        selectedCategory == category
                            ? .primary
                            : .secondary
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background {
                        Capsule()
                            .fill(
                                selectedCategory == category
                                    ? Color.accentColor.opacity(0.18)
                                    : Color.clear
                            )
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .opaqueGlassCapsule(
            tint: .white
        )
    }
}

// MARK: - Album Row
struct AlbumLibraryRow: View {
    let album: Album

    var body: some View {
        HStack(spacing: 12) {
            if let artwork = album.artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 12,
                            style: .continuous
                        )
                    )
            } else {
                placeholderArtwork
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(album.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(album.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text("\(album.songs.count) canciones")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }

    private var placeholderArtwork: some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: 12,
                style: .continuous
            )
            .fill(.thinMaterial)

            Image(systemName: "square.stack")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 60, height: 60)
    }
}

// MARK: - Artist Row
struct ArtistLibraryRow: View {
    let artist: Artist

    var body: some View {
        HStack(spacing: 12) {
            if let artwork = artist.artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(Circle())
            } else {
                ZStack {
                    Circle()
                        .fill(.thinMaterial)

                    Image(systemName: "person.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 60, height: 60)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(artist.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("\(artist.songs.count) canciones")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
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
        .opaqueGlass(
            cornerRadius: 20,
            tint: .white
        )
    }
}