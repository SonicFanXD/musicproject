import SwiftUI

// ✅ FIX header: ContentView ya no usa NavigationStack. El header float
// con el nombre de la app se renderiza como parte del layout. La navegación
// (songs → artista/detalle) se maneja con sheets, eliminando la barra
// de navegación y su división visual con el fondo.
struct ContentView: View {
    @StateObject private var audioEngine = AudioEngine()
    @StateObject private var fileAccessService = FileAccessService()
    @ObservedObject private var localization = Localization.shared

    @State private var hasRestored = false
    @State private var isInitialLoad = true
    // ✅ FIX splash invisible: la caché de biblioteca se decodifica en background
    // y puede terminar ANTES del primer frame → el splash se retiraba en el mismo
    // ciclo de layout en el que nacía. Este flag garantiza un tiempo MÍNIMO
    // visible, en paralelo a `isInitialLibraryLoaded`.
    @State private var splashMinimumElapsed = false
    @State private var showSettings = false
    @State private var showPlaylists = false
    @State private var showFolderPicker = false

    @AppStorage("com.aurora.selectedCategory") private var selectedCategoryRaw = LibraryCategory.songs.rawValue
    private var selectedCategory: LibraryCategory {
        LibraryCategory(rawValue: selectedCategoryRaw) ?? .songs
    }
    @State private var searchText = ""
    // ✅ FASE E (lag del buscador): "texto del campo" ≠ "consulta aplicada".
    // El campo solo escribe `searchText` (coste 0); el filtrado reacciona a
    // `appliedSearchQuery`, que avanza tras un debounce de 250 ms: una ráfaga
    // de teclas ya no ejecuta el matching N veces en el main.
    @State private var appliedSearchQuery = ""
    /// Último resultado PUBLICADO por el search de background. `nil` = todavía
    /// no hay resultado para la consulta vigente (se muestra la lista completa,
    /// no un "sin resultados" prematuro). Al cambiar de consulta se CONSERVA el
    /// anterior hasta que llega el nuevo → sin parpadeo.
    @State private var searchResults: [Song]?
    /// Token generacional: descarta respuestas de consultas ya reemplazadas.
    @State private var searchGeneration = 0
    /// Debounce cancelable del campo (mismo patrón que `sortWorkItem` de
    /// FileAccessService: una tecla nueva cancela el trabajo pendiente).
    @State private var searchDebounceWorkItem: DispatchWorkItem?
    // ✅ FASE D (auditoría 60 fps): orden de la biblioteca CACHEADO.
    // `filteredSongs` es O(n log n) con `localizedStandardCompare` (ICU): con
    // ~1.000 canciones son ~10-20 ms en el A11, y se ejecutaba en CADA
    // evaluación del body — cualquier @Published del motor (play/pausa, cambio
    // de pista, cambio de ruta de audio, cola) provocaba ese trabajo y 1-2
    // frames perdidos. Ahora solo se recalcula cuando cambia una ENTRADA real:
    // la biblioteca (Combine `$songs` emite en cada asignación), el texto de
    // búsqueda, el criterio de orden o su dirección.
    @State private var orderedSongsCache: [Song] = []
    /// Sucio = la caché no refleja las entradas actuales (se recalculó fuera de
    /// la pestaña de Canciones). En cuanto Canciones vuelve a la vista, el
    /// onChange de categoría la recalcula.
    @State private var orderedSongsCacheDirty = true
    // ✅ FIX SCROLL ÁLBUMES/ARTISTAS: mismo patrón que Canciones para las otras
    // dos listas ordenadas. `filteredAlbums`/`filteredArtists` llamaban a
    // `sortAlbums`/`sortArtists` (O(n log n) con `localizedStandardCompare`)
    // en CADA evaluación del body: con el motor y el escaneo publicando
    // cambios, scrollear pagaba ese orden una y otra vez aunque no hubiera
    // cambiado ninguna entrada. Canciones ya tenía caché — por eso solo esas
    // dos pestañas daban tirones.
    @State private var orderedAlbumsCache: [Album] = []
    @State private var orderedAlbumsCacheDirty = true
    @State private var orderedArtistsCache: [Artist] = []
    @State private var orderedArtistsCacheDirty = true
    @FocusState private var searchFieldFocused: Bool
    // ✅ Manejo de ciclo de vida para detectar cambios en segundo plano
    @Environment(\.scenePhase) private var scenePhase
    
    // ✅ Manejo de shortcuts de la app (3D Touch / Haptic Touch)
    @State private var shouldShowSearch = false
    
    // ✅ FIX ordenamiento: @AppStorage leído vía computed property no siempre
    // invalida la vista al cambiar la opción. Se usa @State (reactivo) sincronizado
    // bidireccionalmente con @AppStorage (persistente) para garantizar el re-render.
    @AppStorage("com.aurora.songSort") private var songSortRawStorage = SortOption.title.rawValue
    @AppStorage("com.aurora.songSortAscending") private var songSortAscendingStorage = true
    @AppStorage("com.aurora.albumSort") private var albumSortRawStorage = AlbumSortOption.title.rawValue
    @AppStorage("com.aurora.albumSortAscending") private var albumSortAscendingStorage = true
    // ✅ Orden propio de la categoría Artistas (independiente de canciones/álbumes).
    @AppStorage("com.aurora.artistSort") private var artistSortRawStorage = ArtistSortOption.name.rawValue
    @AppStorage("com.aurora.artistSortAscending") private var artistSortAscendingStorage = true

    @State private var sortOptionRaw: String = SortOption.title.rawValue
    @State private var songSortAscending: Bool = true
    @State private var albumSortRaw: String = AlbumSortOption.title.rawValue
    @State private var albumSortAscending: Bool = true
    @State private var artistSortRaw: String = ArtistSortOption.name.rawValue
    @State private var artistSortAscending: Bool = true

    private var sortOption: SortOption { SortOption(rawValue: sortOptionRaw) ?? .title }
    private var albumSort: AlbumSortOption { AlbumSortOption(rawValue: albumSortRaw) ?? .title }
    private var artistSort: ArtistSortOption { ArtistSortOption(rawValue: artistSortRaw) ?? .name }
    @State private var showSortMenu = false

    var body: some View {
        ZStack {
            AppBackground()
                .onAppear {
                    // ✅ Sincronizar @State con @AppStorage al aparecer para garantizar
                    // que los valores persistidos se carguen correctamente
                    sortOptionRaw = songSortRawStorage
                    songSortAscending = songSortAscendingStorage
                    albumSortRaw = albumSortRawStorage
                    albumSortAscending = albumSortAscendingStorage
                    artistSortRaw = artistSortRawStorage
                    artistSortAscending = artistSortAscendingStorage
                }
            NavigationStack {
                VStack(spacing: 0) {
                    // ✅ Header flotante con nombre de app integrado al fondo (sin NavigationBar separada)
                    headerView

                    // ✅ FIX orden: buscador PRIMERO, luego los chips de
                    // categorías. Antes los chips quedaban arriba del buscador
                    // y se veía invertido (los filtros encima del campo de
                    // búsqueda).
                    searchFieldInline
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                    categoryPicker

                    // ✅ Transición animada entre categorías: el contenido
                    // entra con fade + micro-escala, sale con fade. Solo
                    // transform/opacity → renderizado por GPU, 60fps estables.
                    // ✅ G: cada rama declara su transición. Antes solo existía el
                    // `.animation` de abajo, así que el cambio de categoría cruzaba
                    // en duro (el comentario describía una transición que no estaba).
                    ZStack {
                        switch selectedCategory {
                        case .songs:
                            libraryScroll(id: "songs") { songsSection }
                                .transition(categoryTransition)
                        case .albums:
                            libraryScroll(id: "albums") { albumsSection }
                                .transition(categoryTransition)
                        case .artists:
                            libraryScroll(id: "artists") { artistsSection }
                                .transition(categoryTransition)
                        case .playlists:
                            libraryScroll(id: "playlists") { playlistsSection }
                                .transition(categoryTransition)
                        }
                    }
                    .animation(.spring(response: 0.32, dampingFraction: 0.88), value: selectedCategory)
                    .refreshable {
                        fileAccessService.refreshAllFolders()
                        try? await Task.sleep(nanoseconds: 600_000_000)
                    }
                }
                // ✅ BÚSQUEDA: mantener el índice sincronizado con la
                // librería (solo se reconstruye cuando cambian las
                // canciones/álbumes/artistas, nunca por tecla).
                .onReceive(fileAccessService.$songs) { songs in
                    LibrarySearchIndex.shared.update(
                        songs: songs,
                        albums: fileAccessService.albums,
                        artists: fileAccessService.artists
                    )
                    // ✅ FASE D: la biblioteca cambió → invalidar el orden cacheado.
                    // `$songs` emite en CADA asignación (aunque los valores sean
                    // iguales), así que también cubre re-lecturas de metadata.
                    // ⚠️ D-1: la emisión ocurre DENTRO del willSet de @Published
                    // (documentado por Apple), así que en este punto
                    // `fileAccessService.songs` TODAVÍA devuelve el array anterior:
                    // invalidar aquí cacheaba la biblioteca vieja y la marcaba como
                    // válida (dirty = false) → la lista no se refrescaba hasta el
                    // siguiente invalidante. Un turno de main deja que la asignación
                    // termine y `recomputeOrderedSongs()` ya lee el array nuevo.
                    // ✅ FASE E: con búsqueda aplicada la lista visible es el
                    // resultado del índice, así que además hay que repetir la
                    // consulta contra la biblioteca nueva (libraryDidChange()).
                    DispatchQueue.main.async { libraryDidChange() }
                }
                // ✅ Sincronización bidireccional: mantener @AppStorage actualizado
                // cuando cambian las variables @State de ordenamiento
                .onChange(of: sortOptionRaw) { songSortRawStorage = $0 }
                .onChange(of: songSortAscending) { songSortAscendingStorage = $0 }
                // ✅ FASE D: invalidadores reales del orden cacheado (las entradas
                // de las que depende `computeFilteredSongs()`). Ojo con el teclado:
                // si la lista de Canciones no está a la vista, `invalidateOrderedSongs()`
                // solo marca sucio — no ordena 1.000 canciones por tecla.
                // ✅ FASE E: el campo solo agenda el debounce; el coste real
                // (y la invalidación del orden) ocurre al aplicar la consulta.
                .onChange(of: searchText) { newValue in scheduleSearch(for: newValue) }
                .onChange(of: sortOptionRaw) { _ in invalidateOrderedSongs() }
                .onChange(of: songSortAscending) { _ in invalidateOrderedSongs() }
                // ✅ FIX SCROLL ÁLBUMES/ARTISTAS: el criterio de orden es una
                // entrada de la caché de cada lista → invalidar al cambiar,
                // igual que sortOptionRaw/songSortAscending arriba.
                .onChange(of: albumSortRaw) { albumSortRawStorage = $0; invalidateOrderedAlbums() }
                .onChange(of: albumSortAscending) { albumSortAscendingStorage = $0; invalidateOrderedAlbums() }
                .onChange(of: artistSortRaw) { artistSortRawStorage = $0; invalidateOrderedArtists() }
                .onChange(of: artistSortAscending) { artistSortAscendingStorage = $0; invalidateOrderedArtists() }
                // ✅ FIX LAG DE TECLADO: antes había aquí un .onChange(of: searchText)
                // que llamaba a LibrarySearchIndex.shared.update(...) en CADA tecla.
                // update() ignora por completo `searchText` (solo sincroniza el índice
                // con la librería), así que ese bloque no aportaba nada a la búsqueda:
                // solo recorría toda la biblioteca (map de IDs de canciones/álbumes/
                // artistas) en cada pulsación, de forma síncrona en el hilo principal,
                // congelando el teclado en bibliotecas grandes. El índice ya se
                // mantiene sincronizado por sí solo vía .onReceive(fileAccessService.$songs)
                // y por el .onChange(of: selectedCategoryRaw) de abajo — filtrar por
                // `searchText` ya lo hacen filteredSongs/filteredAlbums/filteredArtists
                // al recomputarse en cada render, sin necesidad de este bloque.
                // Sincronizar el índice también al cambiar de categoría
                // (álbumes/artistas pueden haberse reconstruido).
                .onChange(of: selectedCategoryRaw) { _ in
                    LibrarySearchIndex.shared.update(
                        songs: fileAccessService.songs,
                        albums: fileAccessService.albums,
                        artists: fileAccessService.artists
                    )
                    // ✅ FASE D: al volver a Canciones se recalcula el orden si
                    // quedó sucio mientras se veía otra categoría.
                    recomputeOrderedSongs()
                    // ✅ FIX SCROLL ÁLBUMES/ARTISTAS: mismo contrato para sus
                    // cachés — solo se recalcula la pestaña que entra a la vista.
                    invalidateOrderedAlbums()
                    invalidateOrderedArtists()
                }
                // ✅ DETECCIÓN EN SEGUNDO PLANO: cuando la app vuelve a activa,
                // verificar si hay canciones nuevas SILENCIOSAMENTE (sin tarjeta
                // compacta ni re-indexado visible). Antes aquí se lanzaba un
                // rescan completo (refreshAllFolders) en CADA activación,
                // incluida la primera apertura → era la causa de que al abrir
                // la app arrancara "a indexar todo" con la animación compacta.
                .onChange(of: scenePhase) { newPhase in
                    // ✅ OPT BG: el acento desde carátula (decode + clustering del
                    // artwork + tint global de UIKit) no se ejecuta con la app en
                    // segundo plano: se pospone y se aplica al volver.
                    ThemeManager.shared.setAppInBackground(newPhase == .background)
                    if newPhase == .active {
                        AppLog.info(.lifecycle, "App volvió a activo, detección silenciosa de canciones nuevas...")
                        fileAccessService.backgroundScanForNewSongs()
                    }
                }
                // ✅ Manejar shortcuts de la app (3D Touch / Haptic Touch)
                .onReceive(NotificationCenter.default.publisher(for: .playbackResume)) { _ in
                    audioEngine.resume()
                }
                .onReceive(NotificationCenter.default.publisher(for: .playbackPause)) { _ in
                    audioEngine.pause()
                }
                .onReceive(NotificationCenter.default.publisher(for: .playbackShuffle)) { _ in
                    audioEngine.toggleShuffle()
                }
                .onReceive(NotificationCenter.default.publisher(for: .openSearch)) { _ in
                    shouldShowSearch = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        searchFieldFocused = true
                    }
                }
                .onChange(of: shouldShowSearch) { _ in
                    if shouldShowSearch {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            searchFieldFocused = true
                        }
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack(spacing: 6) {
                            Button {
                                showPlaylists = true
                            } label: {
                                Image(systemName: "music.note.list")
                                    .foregroundStyle(AppTheme.accentGradient)
                                    .font(.system(size: 16, weight: .medium))
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }

                            Button {
                                showSettings = true
                            } label: {
                                Image(systemName: "gearshape.fill")
                                    .foregroundStyle(AppTheme.accentGradient)
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
                    // ✅ FASE D: primera carga del orden cacheado (el fallback de
                    // `filteredSongs` ya garantiza que nunca se vea vacío, pero
                    // así el primer render tras el splash ya viene ordenado).
                    recomputeOrderedSongs()
                    // ✅ FIX SCROLL ÁLBUMES/ARTISTAS: poblar también sus cachés
                    // (mismo motivo: dejar de ordenar dentro del body).
                    recomputeOrderedAlbums()
                    recomputeOrderedArtists()
                    // ✅ FASE B2: el motor no conoce la biblioteca, así que la app
                    // le inyecta aquí el conteo de pistas/discos del álbum (para
                    // MPMediaItemPropertyAlbumTrackCount/DiscCount). El closure
                    // captura la biblioteca en WEAK y NO captura self, para no
                    // crear un ciclo ContentView → audioEngine → closure → ContentView.
                    let library = fileAccessService
                    audioEngine.albumCountsProvider = { [weak library] song in
                        guard let library else { return nil }
                        return ContentView.albumCounts(for: song, in: library)
                    }
                    // ✅ INDEXACIÓN: decidir tarjeta grande vs indicador compacto.
                    syncFirstTimeIndexing()
                    maybeAutoResume()
                    // ✅ FIX splash invisible: con la caché ya cargada (ruta rápida)
                    // el splash sólo sale si además ha pasado el tiempo mínimo.
                    dismissSplashIfReady()
                }
                .task {
                    // ✅ FIX splash invisible: tiempo mínimo visible (1,2 s) antes
                    // de poder retirarlo. La entrada del SplashView (spring 0,7 s
                    // con delays 0,25/0,4) ya ha asentado al llegar aquí, así que
                    // la salida no pilla la animación a medias.
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    splashMinimumElapsed = true
                    dismissSplashIfReady()
                    // Red de seguridad (mismos 8 s desde el arranque): si la
                    // biblioteca aún no está lista, el splash sale igual y el
                    // escaneo continúa en background.
                    try? await Task.sleep(nanoseconds: 6_800_000_000)
                    dismissSplashIfReady(force: true)
                }
                .sheet(isPresented: $showFolderPicker) {
                    FolderPickerView(fileAccessService: fileAccessService)
                }
                .onChange(of: fileAccessService.isInitialLibraryLoaded) { loaded in
                    if loaded {
                        hasRestored = false
                        restoreLibraryIfNeeded()
                        // ✅ FIX "Reproducir al iniciar" con escaneo lento: si la
                        // biblioteca terminó de cargar DESPUÉS del onAppear, el
                        // restore recién ocurrió aquí — reintentar el auto-resume.
                        maybeAutoResume()
                        dismissSplashIfReady()
                    }
                }
                .onChange(of: audioEngine.currentSong?.id) { _ in
                    // ✅ FIX "Reproducir al iniciar": el restore puede completarse
                    // en cualquier momento (escaneo asíncrono) — cuando la canción
                    // aparezca, re-evaluar el auto-resume una vez.
                    maybeAutoResume()
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
                                // ✅ M3E: cápsula SÓLIDA (SurfaceContainer) sobre la
                                // lista. Mismo tamaño y misma sombra; sin muestreo de
                                // material encima de las filas que se desplazan.
                                Capsule()
                                    .fill(Color(UIColor.secondarySystemBackground))
                                    .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                            }
                            .padding(.bottom, 80)
                        }
                        .transition(.opacity)
                    }
                }
            }
            // ✅ FIX POST-G (PlayerBar aparece antes que el resto): la barra se
            // ancla al NavigationStack DENTRO del ZStack. Antes colgaba de un
            // `.safeAreaInset` del ZStack RAÍZ: el inset es hermano de los hijos
            // del ZStack, así que se componía POR ENCIMA del Splash (su zIndex(1)
            // no ordena contra el inset). Aquí el splash vuelve a tapar la barra
            // mientras dura.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                PlayerBar(audioEngine: audioEngine, fileAccessService: fileAccessService, clock: audioEngine.clock)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
            }
        }
        // ✅ FIX ORDEN SPLASH: el splash sale del ZStack raíz y pasa a ser un
        // `.overlay` del ZStack COMPLETO. Como hermano del NavigationStack, ni
        // su posición (último hijo) ni el `.zIndex(1)` ganaban el orden de
        // composición: el contenido de la pila (chips, buscador, biblioteca) se
        // pintaba POR ENCIMA del badge y del título. El `.overlay` compone su
        // contenido DESPUÉS del ZStack entero, así que tapa siempre header,
        // buscador, chips, listas y la PlayerBar (que cuelga del
        // `.safeAreaInset` del NavigationStack, DENTRO del ZStack). El
        // `.zIndex(1)` se elimina: en el overlay el splash es hijo único, no
        // ordena contra nadie.
        .overlay {
            if isInitialLoad {
                SplashView()
                    // ✅ Salida premium: la escala mínima acompaña al fundido (la
                    // duración la marca el withAnimation del llamador, que no se
                    // toca para no alterar la duración total del splash).
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.35), value: fileAccessService.isScanning)
        // ✅ FIX BACK ACCENT: sobreescribe el AccentColor del asset para TODO el
        // stack: el back button de Álbum/Artista (push) toma el acento vivo y
        // respeta el toggle "acento desde carátula" (AppTheme.accent delega en
        // ThemeManager). También cubre alerts y sliders de este stack.
        .tint(AppTheme.accent)
        .onChange(of: fileAccessService.isScanning) { scanning in
            withAnimation(AuroraMotion.normal) {
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
    // ✅ FLAG PERSISTENTE: la tarjeta grande SOLO se muestra en la PRIMERA
    // indexación real de la instalación (sin caché previo). Cualquier
    // re-escaneo posterior (manual o detección en segundo plano) usa la fila
    // compacta, tal como decidió el usuario.
    @AppStorage("com.aurora.firstIndexingDone") private var firstIndexingDone = false

    private func syncFirstTimeIndexing() {
        let scanning = fileAccessService.isScanning
        if firstTimeIndexing {
            // ✅ FIX "tarjeta inservible": el modo tarjeta grande SE MANTIENE
            // aunque `songs` ya no esté vacío (antes, en cuanto llegaba el
            // primer lote el criterio `libraryEmpty` pasaba a false y saltaba
            // a la compacta). Solo se apaga al FINALIZAR el escaneo.
            if !scanning {
                firstIndexingDone = true
                withAnimation(AuroraMotion.slow) { firstTimeIndexing = false }
            }
            return
        }
        // ✅ Solo se ACTIVA la primera vez de la instalación: escaneando,
        // sin flag guardado y sin biblioteca (caché vacío → primera indexación).
        let isFirstScanOfInstall = scanning
            && !firstIndexingDone
            && fileAccessService.songs.isEmpty
            && fileAccessService.pendingSongsCount == 0
        if isFirstScanOfInstall {
            withAnimation(AuroraMotion.slow) { firstTimeIndexing = true }
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
                        Capsule().fill(AppTheme.accentGradient)
                    }
                    .shadow(color: AppTheme.accent.opacity(0.35), radius: 10, x: 0, y: 5)
                }
                // ✅ AURORA DESIGN: escala de presión unificada del sistema.
                .buttonStyle(PressableButtonStyle(scale: AuroraPressScale.button))
            }
        }
    }

    // ✅ Contenedor de biblioteca con ScrollView + LazyVStack (NO List).
    // List + .searchable + toolbar ultraThinMaterial = barra de búsqueda
    // cortada/fantasma y rectángulo negro debajo (celda de scope bar vacía).
    // ScrollView + LazyVStack no toca la navigationBar: el buscador inline
    // de arriba siempre se ve bien y el scroll rinde igual (lazy).
    // Se conserva el inset inferior para la PlayerBar flotante (sin él, la
    // última fila quedaba oculta detrás de la barra).
    /// ✅ G: transición compartida por las 4 categorías de la biblioteca (una
    /// definición en vez de cuatro copias idénticas). Solo `transform`/`opacity`,
    /// así que el cambio lo compone la GPU (nada de blur ni material nuevos).
    /// ✅ FIX POST-G (delay entre categorías): fuera el `.move(edge: .trailing)`.
    /// Desplazar la lista entera (hasta ~1.000 filas del LazyVStack) por pantalla
    /// cuesta un frame caro por paso en el A11 y se percibía como retardo. Ahora
    /// entra con fundido + micro-escala y sale con fundido: mismo gesto visual,
    /// solo opacidad.
    private var categoryTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.98)),
            removal: .opacity
        )
    }

    private func libraryScroll<Content: View>(
        id: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                content()
            }
            .id(id)
            // ✅ Espacio al pie para la PlayerBar flotante (96pt solo con
            // canción activa; 24pt de respiro base sin canción).
            .padding(.bottom, audioEngine.currentSong != nil ? 96 : 24)
        }
        .id(id)
        .scrollIndicators(.hidden)
    }

    // ✅ Buscador INLINE con look nativo (lupa + fondo secondarySystemBackground).
    // Sustituye a .searchable del NavigationStack sin pelear con la navBar.
    // ✅ M3E (Bloque 2): el buscador es el componente base `AuroraM3TextField`
    // (píldora, contenedor sólido, outline que cambia con el foco). Se le pasa el
    // `@FocusState` de esta vista para no perder ni el foco programático ni el
    // comportamiento de la búsqueda; `onClear` mantiene el clear instantáneo
    // (antes saltaba el debounce y la lista tardaba en volver).
    private var searchFieldInline: some View {
        AuroraM3TextField(
            placeholder: Localization.localized("search.prompt"),
            text: $searchText,
            clearAccessibilityLabel: Localization.localized("actions.cancel"),
            onClear: { scheduleSearch(for: "") },
            focus: $searchFieldFocused
        )
    }

    // ✅ M3E (Bloque 2): chips con MORPH de forma. El radio se interpola con
    // `AuroraMorphChipShape` (animatableData) entre rectángulo M3E y cápsula
    // perfecta al seleccionar. Se descartó `matchedGeometryEffect`: con 4 chips
    // en un ScrollView horizontal exige namespace y muestra el cross-fade entre
    // el chip viejo y el nuevo; aquí cada chip interpola SU forma y el layout
    // no se mueve (la shape conserva el ancho del rect).
    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(LibraryCategory.allCases, id: \.self) { category in
                    let isSelected = selectedCategory == category
                    Button {
                        Haptics.selection()
                        selectedCategoryRaw = category.rawValue
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: categoryIcon(for: category))
                                .font(.system(size: 13, weight: .semibold))
                            Text(category.title)
                                // ✅ M3E label-large enfatizado: 14pt medium, tracking 0.1
                                .font(M3ETypography.labelLargeEmphasized)
                                .tracking(0.1)
                        }
                        .foregroundStyle(isSelected ? .white : .secondary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background {
                            // ✅ Contenedor SÓLIDO (SurfaceContainer) con dos capas:
                            // base del sistema + acento que se funde al seleccionar.
                            ZStack {
                                AuroraMorphChipShape(cornerRadius: isSelected ? 20 : 14)
                                    .fill(Color(UIColor.secondarySystemBackground))
                                AuroraMorphChipShape(cornerRadius: isSelected ? 20 : 14)
                                    .fill(AppTheme.accentGradient)
                                    .opacity(isSelected ? 1 : 0)
                                AuroraMorphChipShape(cornerRadius: isSelected ? 20 : 14)
                                    .fill(LinearGradient(colors: [.white.opacity(0.18), .clear],
                                                         startPoint: .top, endPoint: .bottom))
                                    .opacity(isSelected ? 1 : 0)
                            }
                            .overlay {
                                AuroraMorphChipShape(cornerRadius: isSelected ? 20 : 14)
                                    .strokeBorder(Color.secondary.opacity(isSelected ? 0 : 0.12), lineWidth: 0.5)
                            }
                        }
                    }
                    .buttonStyle(PressableButtonStyle(scale: AuroraPressScale.chip))
                    // ✅ M3E: morph con el spring expresivo (rebote de goma).
                    .animation(AuroraMotion.emphasized, value: isSelected)
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 10)
    }

    // ✅ Header flotante con nombre de la app integrado al fondo del contenido.
    // No usa NavigationBar ni toolbar → el nombre se ve como parte del layout,
    // sin división visual contra el AppBackground ni el buscador.
    private var headerView: some View {
        HStack {
            // ✅ M3E (Bloque 2): headline-small enfatizado. Wordmark a 24/medium con tracking 0.
            Text(Localization.localized("app.name"))
                .font(M3ETypography.headlineSmallEmphasized)
                .foregroundStyle(AppTheme.accentGradient)
                .accessibilityLabel(Localization.localized("app.name"))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
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
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                .padding(.horizontal, 12)
                .padding(.top, 8)
            if !currentFilteredSongs.isEmpty {
                sortButtonRow
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                ForEach(currentFilteredSongs) { song in
                    librarySongRow(song)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
            }
        } else if currentFilteredSongs.isEmpty {
            if fileAccessService.isScanning && fileAccessService.scanTotal > 0 {
                indexingProgressCard
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else if appliedSearchQuery.isEmpty {
                emptyLibraryView(
                    icon: "music.note.list",
                    title: Localization.localized("library.empty.title"),
                    message: Localization.localized("library.empty.message")
                )
                .padding(.horizontal, 12)
            } else {
                ContentUnavailableLibraryView(
                    icon: "music.note.list",
                    title: Localization.localized("library.noSongsFound.title"),
                    message: Localization.localized("library.noSongsFound.message")
                )
                .padding(.horizontal, 12)
            }
        } else {
            // ✅ ESCANEO CON CANCIONES EXISTENTES: indicador compacto SOLO en
            // re-escaneos (manual o canciones nuevas en segundo plano); la
            // primera indexación usa la tarjeta grande.
            if fileAccessService.isScanning && fileAccessService.scanTotal > 0 && !firstTimeIndexing {
                compactIndexingRow
                    .padding(.top, 8)
            }
            sortButtonRow
                .padding(.horizontal, 12)
                .padding(.top, 8)
            ForEach(currentFilteredSongs) { song in
                librarySongRow(song)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
        }
    }
    
    private var sortButtonRow: some View {
        CategorySortMenu(
            options: SortOption.allCases,
            current: sortOption,
            optionTitle: { $0.title },
            optionIcon: { $0.icon },
            currentSelection: { opt in sortOptionRaw = opt.rawValue; songSortRawStorage = opt.rawValue },
            ascending: songSortAscending,
            onAscendingChange: { songSortAscending = $0; songSortAscendingStorage = $0 }
        )
    }

    private var albumSortButtonRow: some View {
        CategorySortMenu(
            options: AlbumSortOption.allCases,
            current: albumSort,
            optionTitle: { $0.title },
            optionIcon: { $0.icon },
            currentSelection: { opt in albumSortRaw = opt.rawValue; albumSortRawStorage = opt.rawValue },
            ascending: albumSortAscending,
            onAscendingChange: { albumSortAscending = $0; albumSortAscendingStorage = $0 }
        )
    }

    private var artistSortButtonRow: some View {
        CategorySortMenu(
            options: ArtistSortOption.allCases,
            current: artistSort,
            optionTitle: { $0.title },
            optionIcon: { $0.icon },
            currentSelection: { opt in artistSortRaw = opt.rawValue; artistSortRawStorage = opt.rawValue },
            ascending: artistSortAscending,
            onAscendingChange: { artistSortAscending = $0; artistSortAscendingStorage = $0 }
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
                    .foregroundStyle(AppTheme.accentGradient)
            }

            Text(Localization.localized("indexing.indexingLibrary"))
                .font(.system(size: 22, weight: .heavy, design: .rounded))
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
                            .animation(AuroraMotion.quick, value: indexingProgress)
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
                        .foregroundStyle(AppTheme.accentGradient)
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
        // ✅ AURORA DESIGN: card del sistema en variante flat (radio .xl, borde
        // y sombra single soft unificados). Sigue SIN blur.
        .auroraCard(radius: AuroraRadius.xl, style: .flat, withShadow: true)
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
                        .animation(AuroraMotion.quick, value: indexingProgress)
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
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                .padding(.horizontal, 12)
                .padding(.top, 8)
        }
        if albums.isEmpty {
            if !firstTimeIndexing {
                ContentUnavailableLibraryView(
                    icon: "square.stack",
                    title: Localization.localized("library.noAlbums.title"),
                    message: appliedSearchQuery.isEmpty
                        ? Localization.localized("library.noAlbums.empty")
                        : Localization.localized("library.noAlbums.search")
                )
                .padding(.horizontal, 12)
            }
        } else {
            // ✅ ESCANEO CON ÁLBUMES EXISTENTES: indicador compacto SOLO en
            // re-escaneos (la primera indexación usa la tarjeta grande).
            if fileAccessService.isScanning && fileAccessService.scanTotal > 0 && !firstTimeIndexing {
                compactIndexingRow
                    .padding(.top, 8)
            }
            albumSortButtonRow
                .padding(.horizontal, 12)
                .padding(.top, 8)
            ForEach(albums) { album in
                NavigationLink {
                    AlbumDetailView(album: album, audioEngine: audioEngine, fileAccessService: fileAccessService)
                } label: {
                    // ✅ PERF: fila como view valor + `.equatable()`.
                    AlbumRow(album: album).equatable()
                }
                // ✅ M3E: rebote elástico al tocar la fila (antes .plain: la
                // fila no reaccionaba de forma ninguna hasta que navegaba).
                .buttonStyle(PressableButtonStyle(scale: AuroraPressScale.row, pressedOpacity: 0.7))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
    }

    @ViewBuilder
    private var artistsSection: some View {
        let artists = filteredArtists
        // ✅ PRIMERA INDEXACIÓN: tarjeta grande también en artistas.
        if firstTimeIndexing {
            indexingProgressCard
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                .padding(.horizontal, 12)
                .padding(.top, 8)
        }
        if artists.isEmpty {
            if !firstTimeIndexing {
                ContentUnavailableLibraryView(
                    icon: "person.2",
                    title: Localization.localized("library.noArtists.title"),
                    message: appliedSearchQuery.isEmpty
                        ? Localization.localized("library.noArtists.empty")
                        : Localization.localized("library.noArtists.search")
                )
                .padding(.horizontal, 12)
            }
        } else {
            // ✅ ESCANEO CON ARTISTAS EXISTENTES: indicador compacto SOLO en
            // re-escaneos (la primera indexación usa la tarjeta grande).
            if fileAccessService.isScanning && fileAccessService.scanTotal > 0 && !firstTimeIndexing {
                compactIndexingRow
                    .padding(.top, 8)
            }
            artistSortButtonRow
                .padding(.horizontal, 12)
                .padding(.top, 8)
            ForEach(artists) { artist in
                NavigationLink {
                    ArtistDetailView(artist: artist, audioEngine: audioEngine, fileAccessService: fileAccessService)
                } label: {
                    // ✅ PERF: fila como view valor + `.equatable()`.
                    ArtistRow(artist: artist).equatable()
                }
                // ✅ M3E: mismo press feedback que la fila de álbumes.
                .buttonStyle(PressableButtonStyle(scale: AuroraPressScale.row, pressedOpacity: 0.7))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
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
            .padding(.horizontal, 12)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(playlists) { playlist in
                        NavigationLink {
                            PlaylistDetailView(playlist: playlist, fileAccessService: fileAccessService, audioEngine: audioEngine)
                        } label: {
                            playlistLibraryCard(playlist: playlist)
                        }
                        // ✅ AURORA DESIGN: feedback de presión del sistema, el mismo
                        // caso que ArtistAlbumCard. Sigue siendo un NavigationLink
                        // normal: el ButtonStyle solo dibuja el label.
                        .buttonStyle(PressableButtonStyle(scale: AuroraPressScale.chip))
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 16)
        }
    }

    // ✅ BÚSQUEDA optimizada: el índice ya tiene las cadenas normalizadas
    // (sin acentos/mayúsculas) y el matching es por palabras con ranking de
    // relevancia. Con consulta vacía se respeta el orden del usuario.
    // Con consulta presente se CONSERVA el ranking de relevancia (no se
    // re-ordena): aplicar sortSongs() aquí destruía el ranking y hacía que la
    // búsqueda "pareciera no funcionar" (ver comentario de abajo).
    /// ✅ FASE D (60 fps): devuelve la lista YA ordenada/filtrada desde la CACHÉ.
    /// El fallback a `computeFilteredSongs()` cuando está vacía garantiza que la
    /// primera pintura (antes del onAppear) nunca muestre la biblioteca vacía;
    /// después la caché la mantienen los invalidadores (`recomputeOrderedSongs`).
    private var filteredSongs: [Song] {
        // ✅ FASE E: con búsqueda aplicada la fuente es el resultado del índice
        // (publicado por el search de background). Si aún no hay resultado para
        // la consulta vigente se cae a la lista cacheada: el usuario ve el
        // resultado ANTERIOR hasta que llega el nuevo, nunca un "sin
        // resultados" prematuro.
        if !appliedSearchQuery.isEmpty, let searchResults {
            return searchResults
        }
        if orderedSongsCacheDirty || orderedSongsCache.isEmpty {
            return computeFilteredSongs()
        }
        return orderedSongsCache
    }

    /// ✅ FASE E: el campo de texto solo programa el debounce; una tecla nueva
    /// cancela el trabajo pendiente, así que el matching corre UNA vez tras la
    /// pausa (antes: matching en el main en CADA tecla). Vaciar el campo no
    /// necesita matching: se aplica al instante.
    private func scheduleSearch(for rawText: String) {
        searchDebounceWorkItem?.cancel()
        let query = Self.normalizedSearchQuery(rawText)
        if query.isEmpty {
            clearAppliedSearch()
            return
        }
        let work = DispatchWorkItem { [self] in self.applySearch(query: query) }
        searchDebounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    /// ✅ FASE E: consulta vacía → volver al orden completo. No hay matching
    /// pendiente (se canceló en `scheduleSearch`); se invalida la generación
    /// para descartar respuestas en vuelo y la lista vuelve a la caché.
    private func clearAppliedSearch() {
        searchDebounceWorkItem?.cancel()
        searchDebounceWorkItem = nil
        // Ya en el estado "sin búsqueda": no hace falta repetir el trabajo
        // (el botón de limpiar y el onChange con "" llaman ambos aquí).
        guard !appliedSearchQuery.isEmpty || searchResults != nil else { return }
        searchGeneration += 1
        appliedSearchQuery = ""
        searchResults = nil
        if selectedCategory == .songs, orderedSongsCacheDirty {
            recomputeOrderedSongs()
        }
        // ✅ FIX SCROLL ÁLBUMES/ARTISTAS: mismo contrato al salir de la búsqueda.
        if selectedCategory == .albums, orderedAlbumsCacheDirty {
            recomputeOrderedAlbums()
        }
        if selectedCategory == .artists, orderedArtistsCacheDirty {
            recomputeOrderedArtists()
        }
    }

    /// ✅ FASE E: aplica una consulta (ya normalizada) y lanza el matching en
    /// background. El snapshot del índice se toma AQUÍ (main) y es inmutable
    /// (diccionarios = value types): `update(...)` puede reconstruir el índice
    /// en el main sin carrera con el search. El token generacional descarta las
    /// respuestas de consultas ya reemplazadas.
    private func applySearch(query: String) {
        searchGeneration += 1
        let generation = searchGeneration
        appliedSearchQuery = query
        let songs = fileAccessService.songs
        let entries = LibrarySearchIndex.shared.songEntries
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let results = LibrarySearchIndex.searchSongs(songs, query: query, entries: entries)
            DispatchQueue.main.async {
                guard generation == self.searchGeneration,
                      query == self.appliedSearchQuery else { return }
                self.searchResults = results
            }
        }
    }

    /// ✅ FASE E: la biblioteca cambió. Sin búsqueda aplicada se invalida el
    /// orden cacheado (fix D-1, un turno después del willSet); con búsqueda
    /// aplicada hay que repetir la consulta: la lista visible es el resultado
    /// del índice, no la caché de orden.
    private func libraryDidChange() {
        if appliedSearchQuery.isEmpty {
            invalidateOrderedSongs()
            // ✅ FIX SCROLL ÁLBUMES/ARTISTAS: álbumes y artistas también derivan
            // de `songs` — sus cachés se invalidan en el mismo punto.
            invalidateOrderedAlbums()
            invalidateOrderedArtists()
        } else {
            applySearch(query: appliedSearchQuery)
        }
    }

    /// ✅ FASE E: normalización compartida entre el debounce y la ejecución
    /// (la misma que hacía `normalizedQuery`, ahora atada a la consulta
    /// aplicada).
    private static func normalizedSearchQuery(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// ✅ FASE D: marca la caché como sucia y, si la lista de Canciones está a la
    /// vista, la recalcula al instante (el usuario nunca ve un orden obsoleto).
    /// Con otra categoría abierta solo la marca: no se paga el orden por tecla.
    private func invalidateOrderedSongs() {
        orderedSongsCacheDirty = true
        if selectedCategory == .songs {
            recomputeOrderedSongs()
        }
    }

    /// ✅ FASE D: único punto que recalcula el orden cacheado (nunca desde el
    /// body salvo el caso "sucio", que es el comportamiento anterior).
    private func recomputeOrderedSongs() {
        orderedSongsCache = computeFilteredSongs()
        orderedSongsCacheDirty = false
    }

    /// ✅ FIX SCROLL ÁLBUMES/ARTISTAS: mismo par invalidar/recalcular que
    /// Canciones. El invalidante solo ordena si la pestaña está a la vista;
    /// con otra categoría abierta queda sucio y se recalcula al volver.
    private func invalidateOrderedAlbums() {
        orderedAlbumsCacheDirty = true
        if selectedCategory == .albums {
            recomputeOrderedAlbums()
        }
    }

    private func recomputeOrderedAlbums() {
        orderedAlbumsCache = sortAlbums(fileAccessService.albums)
        orderedAlbumsCacheDirty = false
    }

    private func invalidateOrderedArtists() {
        orderedArtistsCacheDirty = true
        if selectedCategory == .artists {
            recomputeOrderedArtists()
        }
    }

    private func recomputeOrderedArtists() {
        orderedArtistsCache = sortArtists(fileAccessService.artists)
        orderedArtistsCacheDirty = false
    }

    /// Cálculo PURO del orden COMPLETO de canciones (el que antes vivía en el
    /// body). ✅ FASE E: aquí ya NO corre el matching de búsqueda (lo hacía en
    /// el main en cada tecla); con consulta aplicada la lista sale de
    /// `searchResults` y esta ruta solo ordena la biblioteca entera.
    private func computeFilteredSongs() -> [Song] {
        sortSongs(fileAccessService.songs)
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
            // Sin fecha → siempre al final, en ambas direcciones
            // (mismo criterio que sortAlbums).
            return songs.sorted { a, b in
                switch (a.releaseDate, b.releaseDate) {
                case (nil, nil): return false
                case (nil, _): return false
                case (_, nil): return true
                case let (da?, db?):
                    if da == db { return false }
                    return ascending ? da < db : da > db
                }
            }
        case .recentlyAdded:
            return ascending ? songs : Array(songs.reversed())
        }
    }

    private var filteredAlbums: [Album] {
        let albums = fileAccessService.albums
        // ✅ FASE E: la consulta APLICADA (no el texto en vuelo del campo).
        let query = appliedSearchQuery
        // ✅ FIX "no busca bien": ver comentario equivalente en filteredSongs.
        guard !query.isEmpty else {
            // ✅ FIX SCROLL ÁLBUMES/ARTISTAS: mismo contrato que `filteredSongs`
            // — la lista ordenada sale de la caché, no del cuerpo del render.
            if orderedAlbumsCacheDirty || orderedAlbumsCache.isEmpty {
                return sortAlbums(albums)
            }
            return orderedAlbumsCache
        }
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
            return albums.sorted { a, b in
                switch (a.releaseDate, b.releaseDate) {
                case (nil, nil):
                    // ✅ FIX: cuando ambos álbumes carecen de fecha, desempatar por NOMBRE
                    // alfabéticamente para orden estable (sin fecha, el orden alfabético es razonable)
                    return a.name.compare(b.name, locale: .current) == .orderedAscending
                case (nil, _):
                    return false   // sin fecha al final
                case (_, nil):
                    return true    // con fecha primero
                case let (da?, db?):
                    if da == db {
                        // ✅ FIX: cuando el año es el mismo, NO desempatar por nombre
                        // mantener el orden de llegada para consistencia (no mezclar orden)
                        return false
                    }
                    return ascending ? da < db : da > db
                }
            }
        }
    }

    private var filteredArtists: [Artist] {
        let artists = fileAccessService.artists
        // ✅ FASE E: la consulta APLICADA (no el texto en vuelo del campo).
        let query = appliedSearchQuery
        // ✅ FIX "no busca bien": ver comentario equivalente en filteredSongs.
        guard !query.isEmpty else {
            // ✅ FIX SCROLL ÁLBUMES/ARTISTAS: mismo contrato que `filteredSongs`
            // — la lista ordenada sale de la caché, no del cuerpo del render.
            if orderedArtistsCacheDirty || orderedArtistsCache.isEmpty {
                return sortArtists(artists)
            }
            return orderedArtistsCache
        }
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
        // ✅ FIX reproducción desde búsqueda: pasar la lista FILTRADA
        // (con búsqueda activa y orden del usuario) en vez de la lista
        // completa. Así al terminar la canción continúa con los
        // resultados y el repeat-all repite ese mismo contexto.
        audioEngine.play(song: song, from: filteredSongs)
    }

    /// ✅ PERF SCROLL (Prioridad 5): la fila de canción ya NO se construye en
    /// este body. Vive en `LibrarySongRow` (View valor + Equatable, que NO
    /// observa el motor) y aquí solo recibe los valores que pinta.
    /// · `.equatable()` corta el diff ANTES de evaluar el body cuando ninguno
    ///   de esos valores cambió: los @Published del engine (ruta de audio,
    ///   cola, EQ, progreso de escaneo…) ya no repintan las ~30 filas visibles.
    /// · Los closures se pasan por referencia y NO entran en la igualdad.
    private func librarySongRow(_ song: Song) -> some View {
        LibrarySongRow(
            song: song,
            isCurrent: audioEngine.currentSong?.id == song.id,
            isPlaying: audioEngine.isPlaying,
            isLiked: fileAccessService.isLiked(song),
            playlists: fileAccessService.playlists,
            onPlay: { playSong(song) },
            onPlayNext: { audioEngine.playNext(song) },
            onAddToQueue: { audioEngine.addToQueue(song) },
            onToggleLike: { fileAccessService.toggleLike(song) },
            onAddToPlaylist: { playlist in
                fileAccessService.addSongToPlaylist(song, playlist: playlist)
            }
        )
        .equatable()
    }

    /// ✅ FASE B2: pistas y discos del álbum de una canción usando el MISMO
    /// agrupado que la biblioteca (`FileAccessService.albums`, que ya une discos
    /// homónimos y normaliza artista/álbum). Devuelve nil si la canción no está
    /// en ningún álbum indexado: el motor no publica conteos inventados.
    static func albumCounts(for song: Song, in service: FileAccessService) -> (tracks: Int, discs: Int)? {
        let albumName = song.album.isEmpty ? "Álbum desconocido" : song.album
        let artistName = song.albumArtist.isEmpty
            ? (song.artist.isEmpty ? "Artista desconocido" : song.artist)
            : song.albumArtist
        let key = Song.albumGroupKey(album: albumName, artist: artistName)
        let album = service.albums.first {
            Song.albumGroupKey(album: $0.name, artist: $0.artist) == key
        }
        guard let album, !album.songs.isEmpty else { return nil }
        // Los discos se cuentan por su número real (nil ⇒ disco 1).
        let discs = Set(album.songs.map { $0.discNumber ?? 1 }).count
        return (album.songs.count, max(discs, 1))
    }

    /// ✅ FIX splash invisible: única puerta de salida del splash. Se retira
    /// cuando la biblioteca está cargada Y ha pasado el tiempo mínimo visible
    /// (1,2 s), o cuando vence el timeout de seguridad (`force`).
    private func dismissSplashIfReady(force: Bool = false) {
        guard isInitialLoad else { return }
        guard force || (fileAccessService.isInitialLibraryLoaded && splashMinimumElapsed) else { return }
        withAnimation(.easeOut(duration: 0.3)) { isInitialLoad = false }
    }

    private func restoreLibraryIfNeeded() {
        guard !hasRestored else { return }
        hasRestored = true
        audioEngine.restoreState(with: fileAccessService.songs)
        // ✅ Detección silenciosa al abrir: enumera el disco en background SIN
        // tarjeta compacta ni re-renders. Solo indexa lo NUEVO; si no hay nada
        // nuevo la lista ni parpadea. Delay de 2s para que el arranque (splash
        // + primera lista) vaya primero y la enumeración no compita con él.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            fileAccessService.backgroundScanForNewSongs()
        }
    }

    // ✅ "Reproducir al iniciar": reanuda la última canción restaurada si el
    // ajuste está activo y aún no hay reproducción. Seguro de llamar varias
    // veces (guards internos + solo actúa con canción restaurada y pausada).
    private func maybeAutoResume() {
        guard autoPlayOnStart,
              audioEngine.currentSong != nil,
              !audioEngine.isPlaying else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [audioEngine] in
            if audioEngine.currentSong != nil, !audioEngine.isPlaying {
                audioEngine.resume()
            }
        }
    }
}

// ✅ REDISEÑO A (MARCA TIPOGRÁFICA): fuera el gradiente-aurora giratorio y el
// badge hero con sombra. La identidad pasa a ser 100 %
// tipográfica (AURORA + PLAYER) con una firma de acento, sobre la base opaca
// del sistema. El motivo de fondo: el LaunchScreen NO ejecuta código y no
// puede pintar gradientes ni badges — sí fondo del sistema y labels. Con esta
// composición launch y splash son la MISMA pieza (mismo fondo, mismo wordmark
// y misma posición) y el handoff deja de ser un corte.
// Reglas duras intactas: base opaca como PRIMER hijo, TODO nace visible (la
// única @State es el latido y su valor inicial pinta la firma a opacity 1: si
// el onAppear no llegara, se ve igual) y UNA sola animación continua propia
// (el latido; LoadingDots es un componente existente y ya venía pulsando).
// ✅ M3E (Tanda 4): la entrada del wordmark es un "pop" elástico de escala
// con `AuroraMotion.emphasized` (overshoot de goma, 0.88 → 1.0). Sigue siendo
// la única transacción finita del splash además del latido.
// Los TIEMPOS no cambian: el mínimo de 1,2 s lo marca ContentView.
struct SplashView: View {
    // ✅ FIX SPLASH (VIGENTE): el contenido EMPIEZA VISIBLE — la firma nace a
    // opacity 1 y nada depende del `.onAppear` para pintarse. PROHIBIDO volver
    // a opacity condicionada a @State en 0 (fue la causa del cuadro negro).
    // ✅ FASE 1 (bucle infinito): el latido del splash ya no es @State ni
    // `repeatForever`; su fase se calcula en el TimelineView de la firma.
    // ✅ M3E (Tanda 4): driver del "pop" elástico de entrada del logotipo.
    // Nace en false → el bloque se pinta al 88 % de escala (VISIBLE, nunca
    // opaco a 0: la regla dura del splash se mantiene) y al dispararse el
    // onAppear sube a 1.0 con `AuroraMotion.emphasized` (damping 0.68), que es
    // el rebote de goma característico de M3E. Solo escala: transformación GPU,
    // cero blurs ni capas nuevas.
    @State private var logoPopped = false
    
    var body: some View {
        ZStack {
            // ✅ FIX SPLASH TRANSPARENTE: base OPACA del color del sistema como
            // PRIMER hijo del ZStack (regla dura). Los tintes de acento son
            // translúcidos por definición; sin esta base el splash deja ver la
            // app detrás. No mover ni reordenar.
            // ✅ REDISEÑO A: es la MISMA base que el LaunchScreen
            // (`systemBackgroundColor`), así que el handoff no cambia de fondo
            // ni en claro ni en oscuro.
            Color(UIColor.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                // ✅ REDISEÑO A: bloque de marca CENTRADO EXACTO — los dos
                // Spacers flexibles lo parten igual, así que su posición coincide
                // con la del LaunchScreen (que lo espeja con labels del sistema).
                // El halo es un RadialGradient ESTÁTICO del acento al 7 % (capa
                // fija: no se anima ni pasa por offscreen) como fondo del bloque;
                // sustituye al gradiente diagonal giratorio sin coste por frame.
                VStack(spacing: AuroraSpacing.md) {
                    Text("AURORA")
                        .font(.system(size: 68, weight: .heavy, design: .rounded))
                        .tracking(9)
                        .foregroundStyle(AppTheme.accentGradient)
                    
                    Text("PLAYER")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .tracking(5)
                        .foregroundStyle(.secondary)
                    
                    // ✅ FASE 1: firma de acento con latido por TimelineView.
                    // La fase sale de la fecha de cada frame; no hay ninguna
                    // animación infinita encolada que pueda quedar viva al
                    // desmontarse el splash.
                    TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                        let phase = CGFloat((sin(2 * Double.pi * timeline.date.timeIntervalSinceReferenceDate / 2.5) + 1) / 2)
                        Capsule()
                            .fill(AppTheme.accent)
                            .frame(width: 32, height: 4)
                            .padding(.top, AuroraSpacing.sm)
                            .opacity(Double(1.0 - 0.6 * phase))
                    }
                }
                .background(
                    RadialGradient(
                        colors: [AppTheme.accent.opacity(0.07), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 260
                    )
                    .frame(width: 560, height: 560)
                )
                // ✅ M3E: entrada con "pop" elástico del wordmark + halo (escala
                // del bloque completo, así el logo y su halo se asientan como una
                // sola pieza). La curva vive en el onAppear, junto al latido.
                .scaleEffect(logoPopped ? 1.0 : 0.88)
                
                Spacer()
            }
            // ✅ REDISEÑO A: el loader baja AL PIE y en `overlay` para que NO
            // participe del centrado (como hijo del VStack, el bloque de marca
            // quedaría por encima del centro y se rompería la continuidad con el
            // launch). Espaciado con tokens, no medidas propias.
            .overlay(alignment: .bottom) {
                LoadingDots()
                    .padding(.bottom, AuroraSpacing.xxl + AuroraSpacing.xl)
            }
        }
        // ✅ FIX SPLASH TRANSPARENTE: anclamos el ZStack exterior a pantalla
        // completa (cinturón y tirantes). El `.ignoresSafeArea()` de abajo YA
        // estaba desde el POST-G y la base opaca sigue siendo el primer hijo:
        // si la app se ve detrás, no es por el marco.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // ✅ FIX POST-G (splash negro): el splash cubre la pantalla completa; sin
        // esto se quedaba dentro del safe area y el inset inferior le recortaba
        // la zona de la PlayerBar.
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            // ✅ M3E: "pop" de entrada con el spring expresivo de AuroraMotion
            // (respuesta 0.50, damping 0.68). Es una transacción finita con
            // overshoot visible; el bloque nunca parpadea ni se oculta.
            withAnimation(AuroraMotion.emphasized) {
                logoPopped = true
            }
        }
    }
}

// ✅ FASE 1: indicador de carga por Canvas (una sola pasada por frame).
// Antes cada punto lanzaba su propio `repeatForever` escalonado con `delay`:
// al re-renderizarse el splash las transacciones se reencolaban y el bucle no
// terminaba nunca. Ahora la fase es una función de la fecha del TimelineView.
struct LoadingDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let dot: CGFloat = 6
                let gap: CGFloat = 6
                for index in 0..<3 {
                    let phase = (sin(2 * Double.pi * (t - Double(index) * 0.12)) + 1) / 2
                    let scale = CGFloat(0.5 + 0.5 * phase)
                    let radius = dot / 2 * scale
                    let center = CGPoint(
                        x: dot / 2 + CGFloat(index) * (dot + gap),
                        y: size.height / 2
                    )
                    let rect = CGRect(
                        x: center.x - radius,
                        y: center.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(AppTheme.accent.opacity(Double(0.4 + 0.6 * scale)))
                    )
                }
            }
        }
        .frame(width: 6 * 3 + 6 * 2, height: 6)
        .accessibilityHidden(true)
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
                    .foregroundStyle(AppTheme.accentGradient)
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
                // ✅ AURORA DESIGN: mismo fill que el chip no seleccionado del
                // sistema (0.12). No migra a auroraChip completo: impondría su
                // font/padding al trigger compacto del sort.
                Capsule().fill(Color.secondary.opacity(0.12))
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

/// ✅ FIX SCROLL ÁLBUMES/ARTISTAS: miniatura de fila para álbum/artista por la
/// MISMA ruta que la fila de canción (`Song.rowThumbnail`: ImageIO decodifica
/// el JPEG ya al tamaño pedido y lo cachea por hash+px). La selección de
/// portada es idéntica a `Album.artwork`/`Artist.artwork` (primera canción con
/// arte); sin hash (instalación vieja con bytes inline) cae al camino completo.
struct ContentUnavailableLibraryView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        // ✅ M3E (Prioridad 4): el vacío usa el componente del sistema
        // (`AuroraEmptyState`): icono hero que respira y título de 24pt, en vez
        // de un icono de 48pt con texto de 18pt que parecía un error.
        // ✅ RENDIMIENTO (Prioridad 3): fuera `.enhancedGlass` (era un
        // `.ultraThinMaterial` dentro de un ScrollView de hasta 1.000 filas:
        // un pase offscreen por frame en el A11). Ahora superficie flat del
        // sistema, sin material y sin bordes que puedan verse como líneas
        // blancas/grises en modo oscuro.
        AuroraEmptyState(icon: icon, title: title, message: message)
            .auroraCard(radius: AuroraRadius.xl, style: .flat, withShadow: false)
    }
}

struct playlistLibraryCard: View {
    let playlist: Playlist

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if let artwork = playlist.artwork {
                    // ✅ ANTI-JETSAM: card de 140pt → miniatura de 280px cacheada.
                    Image(uiImage: AppTheme.thumbnail(from: artwork, size: CGSize(width: 280, height: 280)))
                        .resizable().scaledToFill()
                        .frame(width: 140, height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(AppTheme.accentGradient(opacity: 0.25))
                            .frame(width: 140, height: 140)
                        Image(systemName: "music.note.list")
                            .font(.system(size: 35))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(playlist.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary).lineLimit(1)
                Text(localizedSongCount(playlist.songIDs.count))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 140).padding(.vertical, 8)
    }
}