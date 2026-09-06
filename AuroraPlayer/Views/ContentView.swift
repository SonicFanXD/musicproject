import SwiftUI

struct ContentView: View {
    @StateObject private var audioEngine = AudioEngine()
    @StateObject private var fileAccessService = FileAccessService()
    @ObservedObject private var localization = Localization.shared

    @State private var hasRestored = false
    @State private var isInitialLoad = true
    @State private var showSettings = false
    @State private var showPlaylists = false
    @State private var showFolderPicker = false

    @AppStorage("com.aurora.selectedCategory") private var selectedCategoryRaw = LibraryCategory.songs.rawValue
    private var selectedCategory: LibraryCategory {
        LibraryCategory(rawValue: selectedCategoryRaw) ?? .songs
    }
    @State private var searchText = ""
    
    @AppStorage("com.aurora.songSort") private var sortOptionRaw = SortOption.title.rawValue
    private var sortOption: SortOption {
        SortOption(rawValue: sortOptionRaw) ?? .title
    }
    @AppStorage("com.aurora.songSortAscending") private var songSortAscending = true
    @AppStorage("com.aurora.albumSort") private var albumSortRaw = AlbumSortOption.title.rawValue
    private var albumSort: AlbumSortOption {
        AlbumSortOption(rawValue: albumSortRaw) ?? .title
    }
    @AppStorage("com.aurora.albumSortAscending") private var albumSortAscending = true
    @State private var showSortMenu = false

    var body: some View {
        ZStack {
            NavigationStack {
                ZStack {
                    AppBackground()

                    VStack(spacing: 0) {
                        categoryPicker

                        Group {
                            switch selectedCategory {
                            case .songs:
                                libraryList(id: "songs") { songsSection }
                            case .albums:
                                libraryList(id: "albums") { albumsSection }
                            case .artists:
                                libraryList(id: "artists") { artistsSection }
                            case .playlists:
                                libraryList(id: "playlists") { playlistsSection }
                            }
                        }
                        .animation(nil, value: selectedCategory)
                        .refreshable {
                            fileAccessService.refreshAllFolders()
                            try? await Task.sleep(nanoseconds: 600_000_000)
                        }
                        .searchable(
                            text: $searchText,
                            prompt: Localization.localized("search.prompt")
                        )
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Color(UIColor.systemBackground).opacity(0.92), for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text(Localization.localized("app.name"))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.accentColor, Color.accentColor.opacity(0.75)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .accessibilityLabel(Localization.localized("app.name"))
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 6) {
                            Button {
                                showPlaylists = true
                            } label: {
                                Image(systemName: "music.note.list")
                                    .font(.system(size: 16, weight: .medium))
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }

                            Button {
                                showSettings = true
                            } label: {
                                Image(systemName: "gearshape.fill")
                                    .font(.system(size: 16, weight: .medium))
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                        }
                    }
                }
                .sheet(isPresented: $showSettings) {
                    SettingsView(audioEngine: audioEngine, fileAccessService: fileAccessService)
                }
                .sheet(isPresented: $showPlaylists) {
                    PlaylistsView(fileAccessService: fileAccessService, audioEngine: audioEngine)
                }
                .onAppear {
                    restoreLibraryIfNeeded()
                    audioEngine.isKeepScreenOnEnabled = keepScreenOnUserDefaults
                    fileAccessService.ensureLikedPlaylistExists()
                    if autoPlayOnStart,
                       audioEngine.currentSong != nil,
                       !audioEngine.isPlaying {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if audioEngine.currentSong != nil, !audioEngine.isPlaying {
                                audioEngine.resume()
                            }
                        }
                    }
                    if fileAccessService.isInitialLibraryLoaded {
                        withAnimation(.easeOut(duration: 0.3)) { isInitialLoad = false }
                    }
                }
                .task {
                    try? await Task.sleep(nanoseconds: 8_000_000_000)
                    if isInitialLoad {
                        withAnimation(.easeOut(duration: 0.3)) { isInitialLoad = false }
                    }
                }
                .sheet(isPresented: $showFolderPicker) {
                    FolderPickerView(fileAccessService: fileAccessService)
                }
                .onChange(of: fileAccessService.isInitialLibraryLoaded) { loaded in
                    if loaded {
                        hasRestored = false
                        restoreLibraryIfNeeded()
                        withAnimation(.easeOut(duration: 0.3)) {
                            isInitialLoad = false
                        }
                    }
                }
                .overlay {
                    if fileAccessService.isScanning && !fileAccessService.songs.isEmpty {
                        VStack {
                            Spacer()
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text(Localization.localized("indexing.updating"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background {
                                Capsule().fill(.regularMaterial)
                            }
                            .padding(.bottom, 80)
                        }
                        .transition(.opacity)
                    }
                }
            }

            if isInitialLoad {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PlayerBar(audioEngine: audioEngine, fileAccessService: fileAccessService, clock: audioEngine.clock)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
        }
        .animation(.easeInOut(duration: 0.35), value: fileAccessService.isScanning)
    }

    @AppStorage("com.aurora.keepScreenOn") private var keepScreenOnUserDefaults = false
    @AppStorage("com.aurora.autoPlayOnStart") private var autoPlayOnStart = false

    @ViewBuilder
    private func emptyLibraryView(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 18) {
            ContentUnavailableLibraryView(icon: icon, title: title, message: message)
            if fileAccessService.folders.isEmpty && fileAccessService.files.isEmpty {
                Button {
                    Haptics.light()
                    showFolderPicker = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                        Text(Localization.localized("actions.addFolder"))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background {
                        Capsule().fill(Color.accentColor)
                    }
                    .shadow(color: Color.accentColor.opacity(0.35), radius: 10, x: 0, y: 5)
                }
                .buttonStyle(PressableButtonStyle(scale: 0.96))
            }
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func libraryList<Content: View>(
        id: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        List {
            content()
                .id(id)
        }
        .id(id)
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(LibraryCategory.allCases, id: \.self) { category in
                    Button {
                        selectedCategoryRaw = category.rawValue
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: categoryIcon(for: category))
                                .font(.system(size: 13, weight: .semibold))
                            Text(category.title)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(selectedCategory == category ? .white : .secondary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background {
                            if selectedCategory == category {
                                ZStack {
                                    Capsule().fill(
                                        LinearGradient(
                                            colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    Capsule().fill(
                                        LinearGradient(
                                            colors: [.white.opacity(0.2), .clear],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                }
                                .shadow(color: Color.accentColor.opacity(0.35), radius: 8, x: 0, y: 4)
                            } else {
                                Capsule().fill(.regularMaterial)
                                Capsule().strokeBorder(Color.secondary.opacity(0.1), lineWidth: 0.5)
                            }
                        }
                    }
                    .buttonStyle(PressableButtonStyle(scale: 0.95))
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 10)
    }

    private func categoryIcon(for category: LibraryCategory) -> String {
        switch category {
        case .songs: return "music.note"
        case .albums: return "square.stack"
        case .artists: return "person.2"
        case .playlists: return "music.note.list"
        }
    }

    @ViewBuilder
    private var songsSection: some View {
        let currentFilteredSongs = filteredSongs

        if currentFilteredSongs.isEmpty {
            if fileAccessService.isScanning && fileAccessService.scanTotal > 0 {
                indexingProgressCard
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else if searchText.isEmpty {
                emptyLibraryView(
                    icon: "music.note.list",
                    title: Localization.localized("library.empty.title"),
                    message: Localization.localized("library.empty.message")
                )
            } else {
                ContentUnavailableLibraryView(
                    icon: "music.note.list",
                    title: Localization.localized("library.noSongsFound.title"),
                    message: Localization.localized("library.noSongsFound.message")
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        } else {
            if fileAccessService.isScanning {
                compactIndexingRow
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            sortButtonRow
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            ForEach(currentFilteredSongs) { song in
                songRow(song)
            }
        }
    }
    
    private var sortButtonRow: some View {
        Menu {
            ForEach(SortOption.allCases, id: \.self) { option in
                Button {
                    sortOptionRaw = option.rawValue
                } label: {
                    HStack {
                        Label(option.title, systemImage: option.icon)
                        if sortOption == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Divider()
            Button {
                songSortAscending = true
            } label: {
                Label(Localization.localized("library.sortAscending"), systemImage: "arrow.up")
                    .opacity(songSortAscending ? 1 : 0.4)
            }
            Button {
                songSortAscending = false
            } label: {
                Label(Localization.localized("library.sortDescending"), systemImage: "arrow.down")
                    .opacity(songSortAscending ? 0.4 : 1)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: sortOption.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text("\(Localization.localized("sort.sortBy")): \(sortOption.title)")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                Capsule().fill(Color.secondary.opacity(0.1))
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }

    private var albumSortButtonRow: some View {
        Menu {
            ForEach(AlbumSortOption.allCases, id: \.self) { option in
                Button {
                    albumSortRaw = option.rawValue
                } label: {
                    HStack {
                        Label(option.title, systemImage: option.icon)
                        if albumSort == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Divider()
            Button {
                albumSortAscending = true
            } label: {
                Label(Localization.localized("library.sortAscending"), systemImage: "arrow.up")
                    .opacity(albumSortAscending ? 1 : 0.4)
            }
            Button {
                albumSortAscending = false
            } label: {
                Label(Localization.localized("library.sortDescending"), systemImage: "arrow.down")
                    .opacity(albumSortAscending ? 0.4 : 1)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: albumSort.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text("\(Localization.localized("sort.sortBy")): \(albumSort.title)")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                Capsule().fill(Color.secondary.opacity(0.1))
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }

    private var indexingProgressCard: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.12)).frame(width: 70, height: 70)
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            Text(Localization.localized("indexing.indexingLibrary"))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            VStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.15))
                        Capsule().fill(Color.accentColor)
                            .frame(width: geo.size.width * indexingProgress)
                            .animation(.easeInOut(duration: 0.3), value: indexingProgress)
                    }
                }
                .frame(height: 8)

                HStack {
                    Text("\(fileAccessService.scanProcessed) \(Localization.localized("indexing.progress")) \(fileAccessService.scanTotal)")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(indexingProgress * 100))%")
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 8)

            Text(Localization.localized("indexing.preparing"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 16)
        .enhancedGlass(cornerRadius: 24)
    }

    private var compactIndexingRow: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("\(Localization.localized("indexing.processed")) \(fileAccessService.scanProcessed)/\(fileAccessService.scanTotal)")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule().fill(Color.accentColor)
                        .frame(width: geo.size.width * indexingProgress)
                        .animation(.easeInOut(duration: 0.3), value: indexingProgress)
                }
            }
            .frame(width: 60, height: 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background {
            Capsule().fill(Color.secondary.opacity(0.06))
        }
        .padding(.horizontal, 12)
    }

    private var indexingProgress: Double {
        guard fileAccessService.scanTotal > 0 else { return 0 }
        return min(1.0, Double(fileAccessService.scanProcessed) / Double(fileAccessService.scanTotal))
    }

    @ViewBuilder
    private var albumsSection: some View {
        let albums = filteredAlbums
        if albums.isEmpty {
            ContentUnavailableLibraryView(
                icon: "square.stack",
                title: Localization.localized("library.noAlbums.title"),
                message: searchText.isEmpty
                    ? Localization.localized("library.noAlbums.empty")
                    : Localization.localized("library.noAlbums.search")
            )
            .listRowSeparator(.hidden).listRowBackground(Color.clear)
        } else {
            albumSortButtonRow
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            ForEach(albums) { album in
                NavigationLink {
                    AlbumDetailView(album: album, audioEngine: audioEngine)
                } label: {
                    albumListRow(album)
                }
                .buttonStyle(.plain).listRowSeparator(.hidden).listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            }
        }
    }

    @ViewBuilder
    private var artistsSection: some View {
        let artists = filteredArtists
        if artists.isEmpty {
            ContentUnavailableLibraryView(
                icon: "person.2",
                title: Localization.localized("library.noArtists.title"),
                message: searchText.isEmpty
                    ? Localization.localized("library.noArtists.empty")
                    : Localization.localized("library.noArtists.search")
            )
            .listRowSeparator(.hidden).listRowBackground(Color.clear)
        } else {
            ForEach(artists) { artist in
                NavigationLink {
                    ArtistDetailView(artist: artist, audioEngine: audioEngine)
                } label: {
                    artistListRow(artist)
                }
                .buttonStyle(.plain).listRowSeparator(.hidden).listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            }
        }
    }

    @ViewBuilder
    private var playlistsSection: some View {
        let playlists = fileAccessService.playlists
        if playlists.isEmpty {
            ContentUnavailableLibraryView(
                icon: "music.note.list",
                title: Localization.localized("library.noPlaylists.title"),
                message: Localization.localized("library.noPlaylists.message")
            )
            .listRowSeparator(.hidden).listRowBackground(Color.clear)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(playlists) { playlist in
                        NavigationLink {
                            PlaylistDetailView(playlist: playlist, fileAccessService: fileAccessService, audioEngine: audioEngine)
                        } label: {
                            playlistLibraryCard(playlist: playlist)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
            .listRowSeparator(.hidden).listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 16, leading: 0, bottom: 16, trailing: 0))
        }
    }

    @ViewBuilder
    private func songRow(_ song: Song) -> some View {
        let isCurrent = audioEngine.currentSong?.id == song.id
        let isLiked = fileAccessService.isLiked(song)
        
        HStack(spacing: 14) {
            Button {
                playSong(song)
            } label: {
                HStack(spacing: 14) {
                    artworkView(for: song)
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(song.displayName)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(isCurrent ? Color.accentColor : .primary)
                            .lineLimit(1)
                        
                        Text(song.displaySubtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        
                        if !song.album.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "opticaldisc")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                                Text(song.album)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    
                    Spacer(minLength: 10)
                    
                    if isCurrent {
                        // ✅ 60fps: drawingGroup rasteriza las barras animadas
                        HStack(spacing: 2.5) {
                            ForEach(0..<3, id: \.self) { bar in
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.accentColor)
                                    .frame(width: 2.5, height: bar % 2 == 0 ? 12 : 7)
                                    .animation(
                                        .easeInOut(duration: 0.4 + Double(bar) * 0.1).repeatForever(autoreverses: true),
                                        value: isCurrent
                                    )
                            }
                        }
                        .drawingGroup()
                    } else {
                        Text(formatDuration(song.duration))
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            
            Button {
                Haptics.light()
                fileAccessService.toggleLike(song)
            } label: {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isLiked ? Color.red : Color.secondary.opacity(0.4))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            Menu {
                if fileAccessService.playlists.isEmpty {
                    Text(Localization.localized("library.noPlaylists"))
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
                    .font(.system(size: 15))
                    .foregroundStyle(.tertiary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            if isCurrent {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.accentColor.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.15), lineWidth: 0.5)
                    )
            }
        }
        .contextMenu {
            Button {
                playSong(song)
            } label: {
                Label(Localization.localized("actions.play"), systemImage: "play.fill")
            }

            Button {
                Haptics.light()
                fileAccessService.toggleLike(song)
            } label: {
                Label(isLiked ? Localization.localized("actions.unlike") : Localization.localized("actions.like"), systemImage: isLiked ? "heart.slash" : "heart")
            }
            
            Menu {
                if fileAccessService.playlists.isEmpty {
                    Text(Localization.localized("library.noPlaylists"))
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
                Label(Localization.localized("context.addToPlaylist"), systemImage: "plus.circle")
            }
            
            Button {
                if let nextIndex = fileAccessService.songs.firstIndex(where: { $0.id == song.id }) {
                    let playNextSongs = Array(fileAccessService.songs.suffix(from: min(nextIndex + 1, fileAccessService.songs.count)))
                    if let nextSong = playNextSongs.first {
                        audioEngine.play(song: nextSong, from: fileAccessService.songs)
                    }
                }
            } label: {
                Label(Localization.localized("context.playNext"), systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            
            Button {
                audioEngine.play(song: song, from: fileAccessService.songs)
            } label: {
                Label(Localization.localized("context.playNow"), systemImage: "play.circle.fill")
            }
        }
        .listRowInsets(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
        .listRowBackground(Color.clear)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    @ViewBuilder
    private func artworkView(for song: Song) -> some View {
        if let artwork = song.artwork {
            Image(uiImage: artwork)
                .resizable()
                .interpolation(.medium)
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.15), Color.accentColor.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 48, height: 48)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.accentColor.opacity(0.6))
                }
        }
    }

    private var normalizedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var filteredSongs: [Song] {
        let songs = fileAccessService.songs
        let query = normalizedQuery
        let filtered: [Song]
        if query.isEmpty {
            filtered = songs
        } else {
            filtered = songs.filter {
                $0.title.lowercased().contains(query) ||
                $0.artist.lowercased().contains(query) ||
                $0.album.lowercased().contains(query)
            }
        }
        return sortSongs(filtered)
    }
    
    private func sortSongs(_ songs: [Song]) -> [Song] {
        let ascending = songSortAscending
        switch sortOption {
        case .title:
            return songs.sorted {
                let r = $0.title.localizedStandardCompare($1.title)
                return ascending ? r == .orderedAscending : r == .orderedDescending
            }
        case .artist:
            return songs.sorted {
                let r = $0.artist.localizedStandardCompare($1.artist)
                return ascending ? r == .orderedAscending : r == .orderedDescending
            }
        case .album:
            return songs.sorted {
                let r = $0.album.localizedStandardCompare($1.album)
                return ascending ? r == .orderedAscending : r == .orderedDescending
            }
        case .duration:
            return ascending ? songs.sorted { $0.duration < $1.duration }
                             : songs.sorted { $0.duration > $1.duration }
        case .year:
            return ascending ? songs.sorted { ($0.releaseDate ?? Date.distantPast) < ($1.releaseDate ?? Date.distantPast) }
                             : songs.sorted { ($0.releaseDate ?? Date.distantPast) > ($1.releaseDate ?? Date.distantPast) }
        case .recentlyAdded:
            return ascending ? songs : Array(songs.reversed())
        }
    }

    private var filteredAlbums: [Album] {
        let albums = fileAccessService.albums
        let query = normalizedQuery
        let filtered: [Album]
        if query.isEmpty {
            filtered = albums
        } else {
            filtered = albums.filter {
                $0.name.lowercased().contains(query) ||
                $0.artist.lowercased().contains(query)
            }
        }
        return sortAlbums(filtered)
    }

    private func sortAlbums(_ albums: [Album]) -> [Album] {
        let ascending = albumSortAscending
        switch albumSort {
        case .title:
            return albums.sorted {
                let r = $0.name.localizedStandardCompare($1.name)
                return ascending ? r == .orderedAscending : r == .orderedDescending
            }
        case .artist:
            return albums.sorted {
                let r = $0.artist.localizedStandardCompare($1.artist)
                return ascending ? r == .orderedAscending : r == .orderedDescending
            }
        case .songCount:
            return ascending ? albums.sorted { $0.songs.count < $1.songs.count }
                             : albums.sorted { $0.songs.count > $1.songs.count }
        case .year:
            let year = { (album: Album) -> Date in
                album.songs.compactMap(\.releaseDate).min() ?? Date.distantPast
            }
            return ascending ? albums.sorted { year($0) < year($1) }
                             : albums.sorted { year($0) > year($1) }
        }
    }

    private var filteredArtists: [Artist] {
        let artists = fileAccessService.artists
        let query = normalizedQuery
        guard !query.isEmpty else { return artists }
        return artists.filter { $0.name.lowercased().contains(query) }
    }

    private func playSong(_ song: Song) {
        Haptics.light()
        audioEngine.play(song: song, from: fileAccessService.songs)
    }

    private func restoreLibraryIfNeeded() {
        guard !hasRestored else { return }
        hasRestored = true
        audioEngine.restoreState(with: fileAccessService.songs)
    }
}

struct SplashView: View {
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "music.note")
                    .font(.system(size: 60, weight: .light))
                    .foregroundStyle(Color.accentColor)
                    .scaleEffect(isAnimating ? 1.1 : 0.95)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isAnimating)
                Text("Aurora Player")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                ProgressView().controlSize(.small).tint(Color.accentColor)
            }
        }
        .onAppear { isAnimating = true }
    }
}

enum LibraryCategory: String, CaseIterable {
    case songs, albums, artists, playlists

    var title: String {
        switch self {
        case .songs: return Localization.localized("library.songs")
        case .albums: return Localization.localized("library.albums")
        case .artists: return Localization.localized("library.artists")
        case .playlists: return Localization.localized("library.playlists")
        }
    }
}

enum SortOption: String, CaseIterable {
    case title, artist, album, duration, year, recentlyAdded
    
    var title: String {
        switch self {
        case .title: return Localization.localized("sort.option.title")
        case .artist: return Localization.localized("sort.option.artist")
        case .album: return Localization.localized("sort.option.album")
        case .duration: return Localization.localized("sort.option.duration")
        case .year: return Localization.localized("sort.option.year")
        case .recentlyAdded: return Localization.localized("sort.option.recentlyAdded")
        }
    }
    
    var icon: String {
        switch self {
        case .title: return "textformat.abc"
        case .artist: return "person.fill"
        case .album: return "square.stack"
        case .duration: return "clock"
        case .year: return "calendar"
        case .recentlyAdded: return "clock.arrow.circlepath"
        }
    }
}

enum AlbumSortOption: String, CaseIterable {
    case title, artist, songCount, year

    var title: String {
        switch self {
        case .title: return Localization.localized("sort.option.title")
        case .artist: return Localization.localized("sort.option.artist")
        case .songCount: return Localization.localized("library.songCount")
        case .year: return Localization.localized("sort.option.year")
        }
    }

    var icon: String {
        switch self {
        case .title: return "textformat.abc"
        case .artist: return "person.fill"
        case .songCount: return "music.note.list"
        case .year: return "calendar"
        }
    }
}

private func albumListRow(_ album: Album) -> some View {
    HStack(spacing: 14) {
        Group {
            if let artwork = album.artwork {
                Image(uiImage: artwork)
                    .resizable().interpolation(.medium).scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 52, height: 52)
                    .overlay {
                        Image(systemName: "square.stack")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary.opacity(0.6))
                    }
            }
        }

        VStack(alignment: .leading, spacing: 3) {
            Text(album.name)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary).lineLimit(1)
            Text(album.artist)
                .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            Text("\(album.songs.count) \(Localization.localized("library.songCount"))")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
        }

        Spacer()
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.tertiary)
    }
    .padding(.horizontal, 14).padding(.vertical, 12)
    .background {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.regularMaterial)
    }
}

private func artistListRow(_ artist: Artist) -> some View {
    HStack(spacing: 14) {
        Group {
            if let artwork = artist.artwork {
                Image(uiImage: artwork)
                    .resizable().interpolation(.medium).scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(Circle())
            } else {
                Circle().fill(Color.secondary.opacity(0.12))
                    .frame(width: 52, height: 52)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary.opacity(0.6))
                    }
            }
        }

        VStack(alignment: .leading, spacing: 3) {
            Text(artist.name)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary).lineLimit(1)
            Text("\(artist.songs.count) \(Localization.localized("library.songCount"))")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }

        Spacer()
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.tertiary)
    }
    .padding(.horizontal, 14).padding(.vertical, 12)
    .background {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.regularMaterial)
    }
}

struct ContentUnavailableLibraryView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.1)).frame(width: 80, height: 80)
                Image(systemName: icon)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
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

struct playlistLibraryCard: View {
    let playlist: Playlist

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if let artwork = playlist.artwork {
                    Image(uiImage: artwork)
                        .resizable().scaledToFill()
                        .frame(width: 140, height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.accentColor.opacity(0.25), Color.accentColor.opacity(0.1)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 140, height: 140)
                        Image(systemName: "music.note.list")
                            .font(.system(size: 35))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(playlist.name)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary).lineLimit(1)
                Text("\(playlist.songIDs.count) \(Localization.localized("library.songCount"))")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 140).padding(.vertical, 8)
    }
}