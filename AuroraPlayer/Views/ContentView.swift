import SwiftUI

struct ContentView: View {
    @StateObject private var audioEngine = AudioEngine()
    @StateObject private var fileAccessService = FileAccessService()

    @State private var hasRestored = false
    @State private var isInitialLoad = true
    @State private var showSettings = false
    @State private var showPlaylists = false
    @State private var showFolderPicker = false

    // ✅ Categoría persistida: recordar la última pestaña usada
    @AppStorage("com.aurora.selectedCategory") private var selectedCategoryRaw = LibraryCategory.songs.rawValue
    private var selectedCategory: LibraryCategory {
        LibraryCategory(rawValue: selectedCategoryRaw) ?? .songs
    }
    @State private var searchText = ""
    
    // ✅ Opciones de ordenamiento para categorías
    @State private var sortOption: SortOption = .title
    @State private var showSortMenu = false

    var body: some View {
        ZStack {
            NavigationStack {
                ZStack {
                    AppBackground()

                    VStack(spacing: 0) {
                        categoryPicker

                        // ✅ Cada categoría tiene su propio List, así el scroll
                        // es independiente: scrollear en Canciones no afecta
                        // a Álbumes, Artistas ni Listas.
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
                        // ✅ FIX: cambio de categoría instantáneo y limpio.
                        // Sin esto, la animación spring heredada hacía que las
                        // tarjetas/material (vacío o indexando) aparecieran con
                        // un efecto feo al alternar secciones.
                        .animation(nil, value: selectedCategory)
                        // ✅ Pull-to-refresh para re-escanear la biblioteca
                        .refreshable {
                            fileAccessService.refreshAllFolders()
                            // mantener el indicador visible un momento
                            try? await Task.sleep(nanoseconds: 600_000_000)
                        }
                        .searchable(
                            text: $searchText,
                            prompt: "Buscar en tu biblioteca"
                        )
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Color(UIColor.systemBackground).opacity(0.92), for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text("Aurora Player")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.accentColor, Color.accentColor.opacity(0.75)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .accessibilityLabel("Aurora Player")
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
                    // ✅ Sincronizar "Mantener pantalla encendida" con el engine
                    audioEngine.isKeepScreenOnEnabled = keepScreenOnUserDefaults
                    // ✅ Crear playlist "Me Gusta" si no existe
                    fileAccessService.ensureLikedPlaylistExists()
                    // ✅ Si el caché ya cargó antes de este onAppear, cerrar splash ya
                    if fileAccessService.isInitialLibraryLoaded {
                        withAnimation(.easeOut(duration: 0.3)) { isInitialLoad = false }
                    }
                }
                // ✅ Respaldo del splash con Task (antes dependía de una
                // notificación que podía no llegar si la app ya estaba activa)
                .task {
                    try? await Task.sleep(nanoseconds: 8_000_000_000)
                    if isInitialLoad {
                        withAnimation(.easeOut(duration: 0.3)) { isInitialLoad = false }
                    }
                }
                .sheet(isPresented: $showFolderPicker) {
                    FolderPickerView(fileAccessService: fileAccessService)
                }
                // ✅ Splash inteligente: permanece hasta que el caché de la
                // biblioteca termine de cargar, así la app muestra las canciones
                // desde el primer frame en vez de una interfaz vacía.
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
                                Text("Actualizando...")
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
            PlayerBar(audioEngine: audioEngine, fileAccessService: fileAccessService)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
        }
        .animation(.easeInOut(duration: 0.35), value: fileAccessService.isScanning)
    }

    // Acceso al ajuste de pantalla encendida para sincronizar con el engine
    @AppStorage("com.aurora.keepScreenOn") private var keepScreenOnUserDefaults = false

    // MARK: - Empty State con acción directa
    @ViewBuilder
    private func emptyLibraryView(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 18) {
            ContentUnavailableLibraryView(icon: icon, title: title, message: message)
            // ✅ Acción directa: agregar carpeta sin ir a Ajustes
            if fileAccessService.folders.isEmpty && fileAccessService.files.isEmpty {
                Button {
                    Haptics.light()
                    showFolderPicker = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Agregar carpeta de música")
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

    // MARK: - Library List (uno por categoría → scroll independiente)
    private func libraryList<Content: View>(
        id: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        List {
            content()
                .id(id)
        }
        .id(id) // recrea el List al cambiar de categoría → scroll desde arriba
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Category Picker (cápsulas premium con material)
    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(LibraryCategory.allCases, id: \.self) { category in
                    Button {
                        // ✅ Cambio directo sin animación: la nueva sección
                        // aparece limpia, sin tarjetas "volando" al entrar.
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

    // MARK: - Library Content
    @ViewBuilder
    private var libraryContent: some View {
        switch selectedCategory {
        case .songs: songsSection
        case .albums: albumsSection
        case .artists: artistsSection
        case .playlists: playlistsSection
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
                    title: "Tu biblioteca está vacía",
                    message: "Agrega una carpeta con tu música para comenzar."
                )
            } else {
                ContentUnavailableLibraryView(
                    icon: "music.note.list",
                    title: "No se encontraron canciones",
                    message: "Prueba con otro término de búsqueda."
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
            // ✅ Botón de ordenamiento
            sortButtonRow
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            ForEach(currentFilteredSongs) { song in
                songRow(song)
            }
        }
    }
    
    // ✅ Botón de ordenamiento para canciones
    private var sortButtonRow: some View {
        Menu {
            ForEach(SortOption.allCases, id: \.self) { option in
                Button {
                    sortOption = option
                } label: {
                    HStack {
                        Label(option.title, systemImage: option.icon)
                        if sortOption == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: sortOption.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text("Ordenar: \(sortOption.title)")
                    .font(.system(size: 12, weight: .medium))
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

    // MARK: - Indexing Progress Cards
    private var indexingProgressCard: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.12)).frame(width: 70, height: 70)
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            Text("Indexando tu biblioteca")
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
                    Text("\(fileAccessService.scanProcessed) de \(fileAccessService.scanTotal)")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(indexingProgress * 100))%")
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 8)

            Text("Preparando tu música…")
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
            Text("Indexando… \(fileAccessService.scanProcessed)/\(fileAccessService.scanTotal)")
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
                icon: "square.stack", title: "No hay álbumes",
                message: searchText.isEmpty ? "Tus álbumes aparecerán aquí." : "No se encontraron álbumes."
            )
            .listRowSeparator(.hidden).listRowBackground(Color.clear)
        } else {
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
                icon: "person.2", title: "No hay artistas",
                message: searchText.isEmpty ? "Tus artistas aparecerán aquí." : "No se encontraron artistas."
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
                icon: "music.note.list", title: "Sin listas",
                message: "Crea tu primera lista de reproducción para organizar tu música."
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
            // Botón de artwork que reproduce la canción
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
                    } else {
                        Text(formatDuration(song.duration))
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            
            // ✅ Botón de me gusta (separado del botón de reproducción)
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
            
            // ✅ Menú de agregar a playlist (separado del botón de reproducción)
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
        // ✅ Menú contextual al mantener presionada una canción
        .contextMenu {
            Button {
                playSong(song)
            } label: {
                Label("Reproducir", systemImage: "play.fill")
            }
            
            Button {
                Haptics.light()
                fileAccessService.toggleLike(song)
            } label: {
                Label(isLiked ? "Quitar de Me Gusta" : "Me Gusta", systemImage: isLiked ? "heart.slash" : "heart")
            }
            
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
                Label("Agregar a playlist", systemImage: "plus.circle")
            }
            
            Button {
                if let nextIndex = fileAccessService.songs.firstIndex(where: { $0.id == song.id }) {
                    let playNextSongs = Array(fileAccessService.songs.suffix(from: min(nextIndex + 1, fileAccessService.songs.count)))
                    if let nextSong = playNextSongs.first {
                        audioEngine.play(song: nextSong, from: fileAccessService.songs)
                    }
                }
            } label: {
                Label("Reproducir siguiente", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            
            Button {
                audioEngine.play(song: song, from: fileAccessService.songs)
            } label: {
                Label("Reproducir ahora", systemImage: "play.circle.fill")
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
                .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 1.5)
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

    // MARK: - Filtering & Sorting
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
        // ✅ Aplicar ordenamiento seleccionado
        return sortSongs(filtered)
    }
    
    /// ✅ Ordenar canciones según la opción seleccionada
    private func sortSongs(_ songs: [Song]) -> [Song] {
        switch sortOption {
        case .title:
            return songs.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .artist:
            return songs.sorted { $0.artist.localizedCaseInsensitiveCompare($1.artist) == .orderedAscending }
        case .album:
            return songs.sorted { $0.album.localizedCaseInsensitiveCompare($1.album) == .orderedAscending }
        case .duration:
            return songs.sorted { $0.duration < $1.duration }
        case .year:
            return songs.sorted { ($0.releaseDate ?? Date.distantPast) > ($1.releaseDate ?? Date.distantPast) }
        case .recentlyAdded:
            return songs // Ya están en orden de indexación
        }
    }

    private var filteredAlbums: [Album] {
        let albums = fileAccessService.albums
        let query = normalizedQuery
        guard !query.isEmpty else { return albums }
        return albums.filter {
            $0.name.lowercased().contains(query) ||
            $0.artist.lowercased().contains(query)
        }
    }

    private var filteredArtists: [Artist] {
        let artists = fileAccessService.artists
        let query = normalizedQuery
        guard !query.isEmpty else { return artists }
        return artists.filter { $0.name.lowercased().contains(query) }
    }

    private func playSong(_ song: Song) {
        Haptics.soft()
        audioEngine.play(song: song, from: fileAccessService.songs)
    }

    private func restoreLibraryIfNeeded() {
        guard !hasRestored else { return }
        hasRestored = true
        audioEngine.restoreState(with: fileAccessService.songs)
    }
}

// MARK: - Splash View
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

// MARK: - Library Category
enum LibraryCategory: String, CaseIterable {
    case songs, albums, artists, playlists

    var title: String {
        switch self {
        case .songs: return "Canciones"
        case .albums: return "Álbums"
        case .artists: return "Artistas"
        case .playlists: return "Listas"
        }
    }
}

// ✅ Opciones de ordenamiento para canciones
enum SortOption: String, CaseIterable {
    case title, artist, album, duration, year, recentlyAdded
    
    var title: String {
        switch self {
        case .title: return "Título"
        case .artist: return "Artista"
        case .album: return "Álbum"
        case .duration: return "Duración"
        case .year: return "Año"
        case .recentlyAdded: return "Agregado recientemente"
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

// MARK: - Album List Row
private func albumListRow(_ album: Album) -> some View {
    HStack(spacing: 14) {
        Group {
            if let artwork = album.artwork {
                Image(uiImage: artwork)
                    .resizable().interpolation(.medium).scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 1.5)
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
            Text("\(album.songs.count) canciones")
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

// MARK: - Artist List Row
private func artistListRow(_ artist: Artist) -> some View {
    HStack(spacing: 14) {
        Group {
            if let artwork = artist.artwork {
                Image(uiImage: artwork)
                    .resizable().interpolation(.medium).scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 1.5)
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
            Text("\(artist.songs.count) canciones")
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

// MARK: - Empty Library
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

// MARK: - Playlist Library Card
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
                        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
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
                Text("\(playlist.songIDs.count) canciones")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 140).padding(.vertical, 8)
    }
}

// MARK: - Album Library Row
struct AlbumLibraryRow: View {
    let album: Album

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if let artwork = album.artwork {
                    Image(uiImage: artwork)
                        .resizable().scaledToFill()
                        .frame(width: 140, height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: 140, height: 140)
                        .overlay {
                            Image(systemName: "square.stack")
                                .font(.system(size: 35))
                                .foregroundStyle(.secondary)
                        }
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(album.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary).lineLimit(1)
                Text(album.artist)
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                Text("\(album.songs.count) canciones")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
        .frame(width: 140).padding(.vertical, 8)
    }
}

// MARK: - Artist Library Row
struct ArtistLibraryRow: View {
    let artist: Artist

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if let artwork = artist.artwork {
                    Image(uiImage: artwork)
                        .resizable().scaledToFill()
                        .frame(width: 140, height: 140)
                        .clipShape(Circle())
                } else {
                    Circle().fill(Color.secondary.opacity(0.15))
                        .frame(width: 140, height: 140)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 35))
                                .foregroundStyle(.secondary)
                        }
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(artist.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary).lineLimit(1)
                Text("\(artist.songs.count) canciones")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 140).padding(.vertical, 8)
    }
}