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

                        // ✅ Transición animada entre categorías: el contenido
                        // entra con fade + slide suave, sale con fade + micro-escala.
                        // Solo transform/opacity → renderizado por GPU, 60fps estables.
                        ZStack {
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
                        .animation(.spring(response: 0.32, dampingFraction: 0.88), value: selectedCategory)
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
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text(Localization.localized("app.name"))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [AppTheme.accent, AppTheme.accent.opacity(0.75)],
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
                                    .foregroundStyle(AppTheme.accent)
                                    .font(.system(size: 16, weight: .medium))
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }

                            Button {
                                showSettings = true
                            } label: {
                                Image(systemName: "gearshape.fill")
                                    .foregroundStyle(AppTheme.accent)
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
                            HStack(spacing: 10) {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(AppTheme.accent)
                                Text(Localization.localized("indexing.updating"))
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background {
                                Capsule()
                                    .fill(AnyShapeStyle(.ultraThinMaterial))
                                    .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
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
                        Capsule().fill(AppTheme.accent)
                    }
                    .shadow(color: AppTheme.accent.opacity(0.35), radius: 10, x: 0, y: 5)
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
                                            colors: [AppTheme.accent, AppTheme.accent.opacity(0.8)],
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
                                .shadow(color: AppTheme.accent.opacity(0.35), radius: 8, x: 0, y: 4)
                            } else {
                                // ✅ 60fps: color OPACO (sin blur) para los chips
                                // no seleccionados (se re-renderizan al scrollear)
                                Capsule().fill(Color(UIColor.secondarySystemBackground))
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
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
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
        VStack(spacing: 18) {
            ZStack {
                // ✅ SIN BLUR: durante la indexación esta vista se re-renderiza en
                // cada lote (scanProcessed cambia constantemente). Un material blur
                // re-computado decenas de veces por segundo es la principal fuente
                // de calor/BCM del dispositivo. Fondo opaco = mismo look, cero
                // re-computo de blur.
                Circle()
                    .fill(Color(UIColor.secondarySystemBackground))
                    .frame(width: 80, height: 80)
                    .overlay {
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [AppTheme.accent.opacity(0.4), AppTheme.accent.opacity(0.1)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    }
                    .shadow(color: AppTheme.accent.opacity(0.15), radius: 10, y: 5)

                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppTheme.accent, AppTheme.accent.opacity(0.7)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            }

            Text(Localization.localized("indexing.indexingLibrary"))
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            VStack(spacing: 10) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.18))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [AppTheme.accent.opacity(0.8), AppTheme.accent],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * indexingProgress)
                            .animation(.easeInOut(duration: 0.3), value: indexingProgress)
                            .shadow(color: AppTheme.accent.opacity(0.3), radius: 4, y: 0)
                    }
                }
                .frame(height: 10)

                HStack {
                    Text("\(fileAccessService.scanProcessed) \(Localization.localized("indexing.progress")) \(fileAccessService.scanTotal)")
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(indexingProgress * 100))%")
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundStyle(AppTheme.accent)
                }
            }
            .padding(.horizontal, 8)

            Text(Localization.localized("indexing.preparing"))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 18)
        // ✅ SIN BLUR (era enhancedGlass/.ultraThinMaterial): esta tarjeta se
        // re-renderiza en cada lote de indexación → blur re-computado constante
        // = calor. Fondo opaco + borde sutil = mismo look premium, cero costo.
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.06), radius: 12, y: 5)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        }
    }

    private var compactIndexingRow: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
                .tint(AppTheme.accent)
            Text("\(Localization.localized("indexing.processed")) \(fileAccessService.scanProcessed)/\(fileAccessService.scanTotal)")
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.18))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.accent.opacity(0.8), AppTheme.accent],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * indexingProgress)
                        .animation(.easeInOut(duration: 0.3), value: indexingProgress)
                }
            }
            .frame(width: 70, height: 5)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background {
            // ✅ SIN BLUR: se re-renderiza en cada lote → blur constante = calor.
            Capsule()
                .fill(Color(UIColor.secondarySystemBackground))
                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
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
                            .foregroundStyle(isCurrent ? AppTheme.accent : .primary)
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
                                    .fill(AppTheme.accent)
                                    .frame(width: 2.5, height: bar % 2 == 0 ? 12 : 7)
                                    .animation(
                                        .easeInOut(duration: 0.4 + Double(bar) * 0.1).repeatForever(autoreverses: true),
                                        value: audioEngine.isPlaying
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
                // ✅ Brillo aumentado: el corazón sin like ahora usa secondary
                // a 0.7 (antes 0.4, casi invisible) + resalta con accent cuando
                // la canción está sonando para mantenerse legible en cualquier fondo.
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isLiked ? Color.red : (isCurrent ? AppTheme.accent : Color.secondary.opacity(0.7)))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppTheme.accent.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(AppTheme.accent.opacity(0.2), lineWidth: 0.5)
                        )
                } else {
                    // ✅ 60fps: color OPACO (no material blur) — en listas largas
                    // iOS degrada con muchos blurs simultáneos. IDÉNTICO look,
                    // pero sin re-render de blur por fila.
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(UIColor.secondarySystemBackground).opacity(0.6))
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
            
            // ✅ "Añadir a playlist" en context menu — solo si hay playlists
            if !fileAccessService.playlists.isEmpty {
                Menu {
                    ForEach(fileAccessService.playlists) { playlist in
                        Button {
                            Haptics.light()
                            fileAccessService.addSongToPlaylist(song, playlist: playlist)
                        } label: {
                            Label(playlist.name, systemImage: "music.note.list")
                        }
                    }
                } label: {
                    Label(Localization.localized("context.addToPlaylist"), systemImage: "plus")
                }
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
                .interpolation(.high)
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [AppTheme.accent.opacity(0.15), AppTheme.accent.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 48, height: 48)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppTheme.accent.opacity(0.6))
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
    @State private var appear = false
    @State private var spin = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // ✅ Fondo que respeta el esquema de color: evita el flash
            // negro→blanco cuando la app abre en modo claro
            (colorScheme == .dark
                ? Color.black
                : Color(UIColor.systemBackground))
            .ignoresSafeArea()

            // ✅ Aurora rotatoria: el gradiente es ESTÁTICO y se rota con
            // rotationEffect (transform puro de GPU). Se rasteriza UNA vez
            // en lugar de re-rasterizar 600px por frame.
            AngularGradient(
                colors: [
                    AppTheme.accent.opacity(0.0),
                    AppTheme.accent.opacity(0.25),
                    Color(red: 0.25, green: 0.55, blue: 1.0).opacity(0.2),
                    Color(red: 0.95, green: 0.35, blue: 0.65).opacity(0.15),
                    AppTheme.accent.opacity(0.0)
                ],
                center: .center,
                startAngle: .degrees(0),
                endAngle: .degrees(200)
            )
            .frame(width: 480, height: 480)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .animation(.linear(duration: 12).repeatForever(autoreverses: false), value: spin)
            .opacity(colorScheme == .dark ? 0.6 : 0.4)

            VStack(spacing: 32) {
                // ✅ Logo con pulse sutil (una sola animación)
                ZStack {
                    // Halo exterior que pulsa
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [AppTheme.accent.opacity(0.3), AppTheme.accent.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                        .frame(width: 140, height: 140)
                        .scaleEffect(appear ? 1.0 : 0.85)

                    // Icono principal
                    Image(systemName: "music.note")
                        .font(.system(size: 52, weight: .light))
                        .foregroundStyle(AppTheme.accent)
                        .shadow(color: AppTheme.accent.opacity(0.5), radius: 12)
                }
                .opacity(appear ? 1 : 0)
                .animation(.easeOut(duration: 0.5).delay(0.1), value: appear)

                VStack(spacing: 14) {
                    Text("Aurora Player")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            // En modo claro el blanco puro sería invisible
                            // sobre el fondo claro: usamos el color primario
                            LinearGradient(
                                colors: [colorScheme == .dark ? .white : Color(UIColor.label), AppTheme.accent],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    // ✅ Indicador de progreso minimalista (sin GeometryReader costoso)
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.accent))
                        .scaleEffect(0.8)
                        .opacity(0.7)
                }
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 12)
                .animation(.easeOut(duration: 0.6).delay(0.25), value: appear)
            }
        }
        .allowsHitTesting(false) // No bloquea toques durante la transición
        .onAppear {
            appear = true
            // ✅ Rotación por transform (GPU): sin re-render del gradiente
            spin = true
        }
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
                    .resizable().interpolation(.high).scaledToFill()
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
        // ✅ FIX: sin flecha manual — NavigationLink ya muestra su propio chevron
        // (antes se veía una flecha DUPLICADA en cada fila de álbumes)
    }
    .padding(.horizontal, 14).padding(.vertical, 12)
    .background {
        // ✅ 60fps: color OPACO (no material blur) para listas largas
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(UIColor.secondarySystemBackground).opacity(0.6))
    }
}

private func artistListRow(_ artist: Artist) -> some View {
    HStack(spacing: 14) {
        Group {
            if let artwork = artist.artwork {
                Image(uiImage: artwork)
                    .resizable().interpolation(.high).scaledToFill()
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
        // ✅ FIX: sin flecha manual — NavigationLink ya muestra su propio chevron
        // (antes se veía una flecha DUPLICADA en cada fila de artistas)
    }
    .padding(.horizontal, 14).padding(.vertical, 12)
    .background {
        // ✅ 60fps: color OPACO (no material blur) para listas largas
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(UIColor.secondarySystemBackground).opacity(0.6))
    }
}

struct ContentUnavailableLibraryView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(AppTheme.accent.opacity(0.1)).frame(width: 80, height: 80)
                Image(systemName: icon)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
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
                                    colors: [AppTheme.accent.opacity(0.25), AppTheme.accent.opacity(0.1)],
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