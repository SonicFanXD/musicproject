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
    // ✅ DEBOUNCE de búsqueda: el campo escribe en `searchText` (fluido),
    // pero el filtrado usa `debouncedSearchText`, que se actualiza 250ms
    // después de la última tecla. Antes cada carácter re-filtraba y
    // re-ordenaba toda la librería → lag al escribir.
    @State private var debouncedSearchText = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    
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
    // ✅ Orden propio de la categoría Artistas (independiente de canciones/álbumes).
    @AppStorage("com.aurora.artistSort") private var artistSortRaw = ArtistSortOption.name.rawValue
    private var artistSort: ArtistSortOption {
        ArtistSortOption(rawValue: artistSortRaw) ?? .name
    }
    @AppStorage("com.aurora.artistSortAscending") private var artistSortAscending = true
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
                        // ✅ BÚSQUEDA: mantener el índice sincronizado con la
                        // librería (solo se reconstruye cuando cambian las
                        // canciones/álbumes/artistas, nunca por tecla).
                        .onReceive(fileAccessService.$songs) { songs in
                            LibrarySearchIndex.shared.update(
                                songs: songs,
                                albums: fileAccessService.albums,
                                artists: fileAccessService.artists
                            )
                        }
                        // ✅ DEBOUNCE: filtrar 250ms después de la última tecla.
                        .onChange(of: searchText) { newValue in
                            // ✅ Resincronizar el índice al empezar a buscar
                            // (barato: se salta si nada cambió desde la última vez).
                            LibrarySearchIndex.shared.update(
                                songs: fileAccessService.songs,
                                albums: fileAccessService.albums,
                                artists: fileAccessService.artists
                            )
                            searchDebounceTask?.cancel()
                            searchDebounceTask = Task {
                                try? await Task.sleep(nanoseconds: 250_000_000)
                                guard !Task.isCancelled else { return }
                                debouncedSearchText = newValue
                            }
                        }
                        // ✅ Sincronizar el índice también al cambiar de categoría
                        // (álbumes/artistas pueden haberse reconstruido).
                        .onChange(of: selectedCategoryRaw) { _ in
                            LibrarySearchIndex.shared.update(
                                songs: fileAccessService.songs,
                                albums: fileAccessService.albums,
                                artists: fileAccessService.artists
                            )
                        }
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
                    // ✅ INDEXACIÓN: decidir tarjeta grande vs indicador compacto.
                    syncFirstTimeIndexing()
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
                    // ✅ Indicador compacto flotante: SOLO en re-escaneos con
                    // biblioteca ya cargada (no en la primera indexación, donde
                    // ya está la tarjeta grande en la lista).
                    if fileAccessService.isScanning && !fileAccessService.songs.isEmpty && !firstTimeIndexing {
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
        .onChange(of: fileAccessService.isScanning) { scanning in
            withAnimation(.easeInOut(duration: 0.3)) {
                compactIndexingVisible = scanning
            }
            // ✅ INDEXACIÓN: sincronizar tarjeta grande / indicador compacto.
            syncFirstTimeIndexing()
        }
    }

    @AppStorage("com.aurora.keepScreenOn") private var keepScreenOnUserDefaults = false
    @AppStorage("com.aurora.autoPlayOnStart") private var autoPlayOnStart = false
    // ✅ Visibilidad de la fila compacta de indexación, animada por opacidad.
    // La fila se mantiene SIEMPRE en la lista (colapsada a ~0px cuando está
    // oculta) para que aparezca/desaparezca con un fade suave en vez de
    // insertarse/eliminarse como fila (lo que desplazaba la lista bruscamente).
    @State private var compactIndexingVisible = false

    // ✅ TARJETA GRANDE solo en la PRIMERA indexación (biblioteca aún vacía):
    // - Primera vez: tarjeta grande en TODAS las categorías mientras escanea,
    //   con el contenido apareciendo debajo a medida que se indexa; al
    //   terminar, la tarjeta se desvanece (opacidad, sin blur = barato).
    // - Aperturas siguientes: el escaneo corre en segundo plano buscando
    //   canciones nuevas y SOLO se muestra el indicador compacto mientras
    //   dura; desaparece al terminar.
    @State private var firstTimeIndexing = false

    private func syncFirstTimeIndexing() {
        let scanning = fileAccessService.isScanning
        let libraryEmpty = fileAccessService.songs.isEmpty && fileAccessService.pendingSongsCount == 0
        // ✅ Solo mostrar tarjeta grande en la PRIMERA carga (nunca se han cargado canciones)
        // En cargas posteriores, aunque `libraryEmpty` sea true (porque rescanAllFolders
        // limpia songs), NO se muestra la tarjeta grande.
        let isVeryFirstLoad = scanning && libraryEmpty && fileAccessService.isFirstLibraryLoad
        if isVeryFirstLoad {
            if !firstTimeIndexing {
                withAnimation(.easeOut(duration: 0.3)) { firstTimeIndexing = true }
            }
        } else if !scanning && firstTimeIndexing {
            // ✅ Fade-out optimizado: solo opacidad (GPU), sin blur ni layout costoso.
            withAnimation(.easeOut(duration: 0.45)) { firstTimeIndexing = false }
        }
    }

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
        // ✅ FIX scroll: reservar espacio al pie para la PlayerBar flotante.
        // Sin esto, la última fila (canción/álbum/artista) quedaba oculta
        // detrás de la barra al llegar al final de la lista. safeAreaInset
        // reduce el área scrolleable — funciona igual en todas las categorías.
        // Condicional: la PlayerBar se oculta (altura 0) sin canción activa,
        // así que el inset solo existe cuando la barra es visible.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: audioEngine.currentSong != nil ? 96 : 0)
                .allowsHitTesting(false)
        }
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

        // ✅ PRIMERA INDEXACIÓN: tarjeta grande arriba y el contenido
        // apareciendo debajo a medida que se indexa.
        if firstTimeIndexing {
            indexingProgressCard
                .transition(.opacity)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            if !currentFilteredSongs.isEmpty {
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
        } else if currentFilteredSongs.isEmpty {
            if fileAccessService.isScanning && fileAccessService.scanTotal > 0 {
                indexingProgressCard
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else if debouncedSearchText.isEmpty {
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
            // ✅ ESCANEO CON CANCIONES EXISTENTES: mostrar indicador compacto
            // SOLO cuando se están agregando canciones nuevas (escaneo incremental)
            if fileAccessService.isScanning && fileAccessService.scanTotal > 0 {
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
        CategorySortMenu(
            options: SortOption.allCases,
            current: sortOption,
            optionTitle: { $0.title },
            optionIcon: { $0.icon },
            currentSelection: { sortOptionRaw = $0.rawValue },
            ascending: songSortAscending,
            onAscendingChange: { songSortAscending = $0 }
        )
    }

    private var albumSortButtonRow: some View {
        CategorySortMenu(
            options: AlbumSortOption.allCases,
            current: albumSort,
            optionTitle: { $0.title },
            optionIcon: { $0.icon },
            currentSelection: { albumSortRaw = $0.rawValue },
            ascending: albumSortAscending,
            onAscendingChange: { albumSortAscending = $0 }
        )
    }

    private var artistSortButtonRow: some View {
        CategorySortMenu(
            options: ArtistSortOption.allCases,
            current: artistSort,
            optionTitle: { $0.title },
            optionIcon: { $0.icon },
            currentSelection: { artistSortRaw = $0.rawValue },
            ascending: artistSortAscending,
            onAscendingChange: { artistSortAscending = $0 }
        )
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
                        .frame(width: max(0, geo.size.width * indexingProgress))
                        .animation(.easeInOut(duration: 0.25), value: indexingProgress)
                }
            }
            .frame(width: 70, height: 5)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background {
            Capsule()
                .fill(Color(UIColor.secondarySystemBackground))
                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        }
        .padding(.horizontal, 12)
        .opacity(compactIndexingVisible ? 1 : 0)
        // ✅ Colapsar la altura cuando está oculta (con fade animado) para no
        // dejar una fila vacía persistente ni desplazar la lista al aparecer.
        .frame(height: compactIndexingVisible ? nil : CGFloat(1))
        .clipped()
    }

    private var indexingProgress: Double {
        guard fileAccessService.scanTotal > 0 else { return 0 }
        return min(1.0, Double(fileAccessService.scanProcessed) / Double(fileAccessService.scanTotal))
    }

    @ViewBuilder
    private var albumsSection: some View {
        let albums = filteredAlbums
        // ✅ PRIMERA INDEXACIÓN: tarjeta grande también en álbumes.
        if firstTimeIndexing {
            indexingProgressCard
                .transition(.opacity)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        if albums.isEmpty {
            if !firstTimeIndexing {
                ContentUnavailableLibraryView(
                    icon: "square.stack",
                    title: Localization.localized("library.noAlbums.title"),
                    message: debouncedSearchText.isEmpty
                        ? Localization.localized("library.noAlbums.empty")
                        : Localization.localized("library.noAlbums.search")
                )
                .listRowSeparator(.hidden).listRowBackground(Color.clear)
            }
        } else {
            // ✅ ESCANEO CON ÁLBUMES EXISTENTES: mostrar indicador compacto
            if fileAccessService.isScanning && fileAccessService.scanTotal > 0 {
                compactIndexingRow
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
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
        // ✅ PRIMERA INDEXACIÓN: tarjeta grande también en artistas.
        if firstTimeIndexing {
            indexingProgressCard
                .transition(.opacity)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        if artists.isEmpty {
            if !firstTimeIndexing {
                ContentUnavailableLibraryView(
                    icon: "person.2",
                    title: Localization.localized("library.noArtists.title"),
                    message: debouncedSearchText.isEmpty
                        ? Localization.localized("library.noArtists.empty")
                        : Localization.localized("library.noArtists.search")
                )
                .listRowSeparator(.hidden).listRowBackground(Color.clear)
            }
        } else {
            // ✅ ESCANEO CON ARTISTAS EXISTENTES: mostrar indicador compacto
            if fileAccessService.isScanning && fileAccessService.scanTotal > 0 {
                compactIndexingRow
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            artistSortButtonRow
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
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
                audioEngine.play(song: song, from: filteredSongs)
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
        debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // ✅ BÚSQUEDA optimizada: el índice ya tiene las cadenas normalizadas
    // (sin acentos/mayúsculas) y el matching es por palabras con ranking de
    // relevancia. Con consulta vacía se respeta el orden del usuario.
    private var filteredSongs: [Song] {
        let songs = fileAccessService.songs
        let query = normalizedQuery
        guard !query.isEmpty else { return sortSongs(songs) }
        return LibrarySearchIndex.shared.searchSongs(songs, query: query)
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
        guard !query.isEmpty else { return sortAlbums(albums) }
        return LibrarySearchIndex.shared.searchAlbums(albums, query: query)
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
            let year = { (album: Album) -> Int? in
                album.releaseDate.map { Calendar.current.component(.year, from: $0) }
            }
            // Los álbumes sin fecha se ordenan al final (año nil = los últimos)
            return ascending
                ? albums.sorted { a, b in
                    let ya = year(a), yb = year(b)
                    if ya == nil && yb == nil { return false }
                    if ya == nil { return false }   // nil va al final en ascendente
                    if yb == nil { return true }    // a tiene año, b no → a va primero
                    return ya! < yb!
                }
                : albums.sorted { a, b in
                    let ya = year(a), yb = year(b)
                    if ya == nil && yb == nil { return false }
                    if yb == nil { return false }   // nil va al final en descendente
                    if ya == nil { return true }    // a no tiene año, b sí → b va primero
                    return ya! > yb!
                }
        }
    }

    private var filteredArtists: [Artist] {
        let artists = fileAccessService.artists
        let query = normalizedQuery
        guard !query.isEmpty else { return sortArtists(artists) }
        return LibrarySearchIndex.shared.searchArtists(artists, query: query)
    }

    // ✅ Orden de artistas con opciones propias de la categoría.
    // albumCount y duración se calculan UNA vez por artista (diccionario) antes
    // de ordenar: artist.albums agrupa discos y es caro llamarlo en cada
    // comparación del sort.
    private func sortArtists(_ artists: [Artist]) -> [Artist] {
        let ascending = artistSortAscending
        switch artistSort {
        case .name:
            return artists.sorted {
                let r = $0.name.localizedStandardCompare($1.name)
                return ascending ? r == .orderedAscending : r == .orderedDescending
            }
        case .songCount:
            return ascending ? artists.sorted { $0.songs.count < $1.songs.count }
                             : artists.sorted { $0.songs.count > $1.songs.count }
        case .albumCount:
            let counts = Dictionary(uniqueKeysWithValues: artists.map { ($0.id, $0.albums.count) })
            return ascending ? artists.sorted { counts[$0.id, default: 0] < counts[$1.id, default: 0] }
                             : artists.sorted { counts[$0.id, default: 0] > counts[$1.id, default: 0] }
        case .duration:
            let durations = Dictionary(uniqueKeysWithValues: artists.map { ($0.id, $0.songs.reduce(0) { $0 + $1.duration }) })
            return ascending ? artists.sorted { durations[$0.id, default: 0] < durations[$1.id, default: 0] }
                             : artists.sorted { durations[$0.id, default: 0] > durations[$1.id, default: 0] }
        }
    }

    private func playSong(_ song: Song) {
        Haptics.light()
        audioEngine.play(song: song, from: fileAccessService.songs)
    }

    private func restoreLibraryIfNeeded() {
        guard !hasRestored else { return }
        hasRestored = true
        audioEngine.restoreState(with: fileAccessService.songs)
        // ✅ Escaneo en segundo plano para detectar canciones nuevas
        // Solo se ejecuta si ya se cargaron canciones previamente (no es primera vez)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            fileAccessService.backgroundScanForNewSongs()
        }
    }
}

struct SplashView: View {
    @State private var logoScale: CGFloat = 0.8
    @State private var logoOpacity: Double = 0
    @State private var titleOffset: CGFloat = 20
    @State private var titleOpacity: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            // ✅ Fondo sólido que respeta el esquema de color
            (colorScheme == .dark ? Color.black : Color(UIColor.systemBackground))
                .ignoresSafeArea()
            
            // ✅ Efecto de resplandor sutil (sin AngularGradient problemático)
            RadialGradient(
                colors: [
                    AppTheme.accent.opacity(colorScheme == .dark ? 0.08 : 0.04),
                    Color.clear
                ],
                center: .center,
                startRadius: 50,
                endRadius: 250
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                // ✅ Logo con animación de escala y opacidad suave
                ZStack {
                    // Halo pulsante exterior
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    AppTheme.accent.opacity(0.15),
                                    AppTheme.accent.opacity(0.05),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 30,
                                endRadius: 80
                            )
                        )
                        .frame(width: 160, height: 160)
                        .scaleEffect(pulseScale)
                        .opacity(pulseOpacity)
                    
                    // Círculo del logo
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppTheme.accent.opacity(0.12),
                                    AppTheme.accent.opacity(0.04)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 110, height: 110)
                        .overlay {
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            AppTheme.accent.opacity(0.4),
                                            AppTheme.accent.opacity(0.1)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                        }
                    
                    // Icono principal
                    Image(systemName: "music.note")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [AppTheme.accent, AppTheme.accent.opacity(0.7)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: AppTheme.accent.opacity(0.3), radius: 8, y: 4)
                }
                .scaleEffect(logoScale)
                .opacity(logoOpacity)
                
                Spacer().frame(height: 32)
                
                // ✅ Título con animación de slide hacia arriba
                VStack(spacing: 12) {
                    Text("Aurora Player")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    colorScheme == .dark ? .white : Color(UIColor.label),
                                    AppTheme.accent
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    
                    // ✅ Indicador de progreso personalizado
                    LoadingDots()
                }
                .opacity(titleOpacity)
                .offset(y: titleOffset)
                
                Spacer()
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            // ✅ Animación del logo
            withAnimation(.easeOut(duration: 0.6)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
            
            // ✅ Animación del título (con delay)
            withAnimation(.easeOut(duration: 0.5).delay(0.25)) {
                titleOffset = 0
                titleOpacity = 1.0
            }
            
            // ✅ Animación de pulso del halo
            withAnimation(.easeInOut(duration: 1.2).delay(0.4)) {
                pulseScale = 1.15
                pulseOpacity = 1.0
            }
        }
    }
}

// ✅ Indicador de carga personalizado (puntos animados)
struct LoadingDots: View {
    @State private var animating = false
    
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(AppTheme.accent.opacity(0.7))
                    .frame(width: 6, height: 6)
                    .scaleEffect(animating ? 1.0 : 0.5)
                    .opacity(animating ? 1.0 : 0.4)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.15),
                        value: animating
                    )
            }
        }
        .onAppear {
            animating = true
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
        case .songCount: return Localization.localized("sort.option.songCount")
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

// ✅ Orden propio de ARTISTAS: opciones únicas de esta categoría (no reutiliza
// las de canciones ni álbumes). albumCount/duración se computan una vez por
// artista antes de ordenar (artist.albums es costoso: agrupa todos sus discos).
enum ArtistSortOption: String, CaseIterable {
    case name, songCount, albumCount, duration

    var title: String {
        switch self {
        case .name: return Localization.localized("sort.option.name")
        case .songCount: return Localization.localized("sort.option.songCount")
        case .albumCount: return Localization.localized("sort.option.albumCount")
        case .duration: return Localization.localized("sort.option.duration")
        }
    }

    var icon: String {
        switch self {
        case .name: return "textformat.abc"
        case .songCount: return "music.note.list"
        case .albumCount: return "square.stack"
        case .duration: return "clock"
        }
    }
}

// MARK: - Menú de ordenación UNIFICADO para todas las categorías
// ✅ Antes había tres copias casi idénticas del menú (canciones/álbumes/
// artistas) con estilos y textos ligeramente distintos. Ahora una sola vista
// genérica garantiza: mismo diseño, mismo orden de opciones, checkmark,
// dirección asc/desc y textos sin cortes raros (lineLimit + layoutPriority).
struct CategorySortMenu<Option: RawRepresentable & Hashable & CaseIterable>: View where Option.RawValue == String {
    let options: [Option]
    let current: Option
    let optionTitle: (Option) -> String
    let optionIcon: (Option) -> String
    let currentSelection: (Option) -> Void
    let ascending: Bool
    let onAscendingChange: (Bool) -> Void

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    currentSelection(option)
                } label: {
                    HStack {
                        Label(optionTitle(option), systemImage: optionIcon(option))
                        if current == option {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Divider()
            Button {
                onAscendingChange(true)
            } label: {
                Label(Localization.localized("library.sortAscending"), systemImage: "arrow.up")
                    .opacity(ascending ? 1 : 0.4)
            }
            Button {
                onAscendingChange(false)
            } label: {
                Label(Localization.localized("library.sortDescending"), systemImage: "arrow.down")
                    .opacity(ascending ? 0.4 : 1)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: optionIcon(current))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                Text("\(Localization.localized("sort.sortBy")): \(optionTitle(current))")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
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
}

/// ✅ Texto de cantidad con SINGULAR correcto: antes "1 canciones"/"1 álbumes".
func localizedSongCount(_ count: Int) -> String {
    let unit = Localization.localized(count == 1 ? "library.songCountSingular" : "library.songCount")
    return "\(count) \(unit)"
}

func localizedAlbumCount(_ count: Int) -> String {
    let unit = Localization.localized(count == 1 ? "library.albumCountSingular" : "library.albumCount")
    return "\(count) \(unit)"
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
            Text(localizedSongCount(album.songs.count))
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
            // ✅ Solo canciones: artist.albums agrupa discos y es caro de calcular
            // por fila en cada render (el detalle del artista sí muestra álbumes).
            Text(localizedSongCount(artist.songs.count))
                .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
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
                Text(localizedSongCount(playlist.songIDs.count))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 140).padding(.vertical, 8)
    }
}