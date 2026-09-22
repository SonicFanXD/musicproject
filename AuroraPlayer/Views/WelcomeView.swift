import SwiftUI

/// ✅ PESTAÑA BIENVENIDA (3.0): portada de la app.
/// Saludo por hora, mezcla del día, playlists automáticas, recomendadas y
/// artistas top. Todo se calcula al vuelo desde FileAccessService (biblioteca +
/// estadísticas de reproducción) y se cachea en @State una vez por apertura:
/// las consultas ordenan la biblioteca entera y NUNCA deben correr en un render.
struct WelcomeView: View {
    /// ✅ FLUIDEZ 3.0.1: SIN @ObservedObject. WelcomeView no LEE ningún estado
    /// observable del motor ni de la biblioteca (todo lo que pinta vive en sus
    /// snapshots @State), así que observarlos solo servía para reconstruir la
    /// portada entera —cuadrícula de recomendadas incluida— en cada reproducción
    /// (playCounts/playTimes cambian con cada canción).
    let audioEngine: AudioEngine
    let fileAccessService: FileAccessService
    // ✅ Observar el idioma: los textos cambian al instante.
    @ObservedObject private var localization = Localization.shared

    @State private var showFolderPicker = false
    /// ✅ Contenido de las 5 playlists automáticas, indexado por id.
    @State private var smartContent: [String: [Song]] = [:]
    @State private var recommendedSongs: [Song] = []
    @State private var topArtists: [Artist] = []
    /// ✅ Playlist automática abierta en el sheet (Identifiable por id).
    @State private var selectedPlaylist: SmartPlaylist?
    @State private var appeared = false
    /// ✅ FLUIDEZ 3.0.1: número de canciones, alimentado por el publisher de
    /// `songs`. Permite que la vista sepa si hay biblioteca sin observar el
    /// servicio completo.
    @State private var songCount = 0
    /// ✅ MEMOIZACIÓN: último contenido calculado, su firma y cuándo se calculó.
    /// Calcular las 5 playlists ordena la biblioteca varias veces y cada mezcla
    /// baraja el catálogo completo dos veces: reabrir la pestaña no debe repetirlo.
    @State private var cachedContent: CachedContent?

    private var hasSongs: Bool { songCount > 0 }
    private var dailyMixSongs: [Song] { smartContent[SmartPlaylist.dailyMix.id] ?? [] }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        headerSection
                        if hasSongs {
                            dailyMixSection
                            smartPlaylistsSection
                            recommendedSection
                            topArtistsSection
                        } else {
                            emptyLibrarySection
                        }
                    }
                    // ✅ Espacio al pie para la PlayerBar flotante.
                    .padding(.bottom, 130)
                    // ✅ POLISH 3.0.1: UNA sola entrada para toda la pestaña — fade
                    // + micro-escala (0.98 → 1). Opacity y transform son las dos
                    // propiedades que compone la GPU, así que no cuesta un fotograma;
                    // al ser `value:`-scoped, los cambios de contenido NO se animan
                    // (solo la aparición de la pestaña).
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.98)
                    .animation(.easeOut(duration: 0.35), value: appeared)
                }
                .scrollIndicators(.hidden)
            }
            // ✅ Header propio: la barra de navegación queda invisible (solo existe
            // para poder empujar el detalle de artista).
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showFolderPicker) {
            FolderPickerView(fileAccessService: fileAccessService)
        }
        .sheet(item: $selectedPlaylist) { playlist in
            SmartPlaylistDetailView(
                playlist: playlist,
                songs: smartContent[playlist.id] ?? [],
                audioEngine: audioEngine,
                fileAccessService: fileAccessService
            )
        }
        .task { reloadContent() }
        // ✅ El publisher de `songs` sustituye a observar el servicio entero: solo
        // re-acciona cuando cambia la biblioteca en sí (termina de cargar, se
        // indexan canciones nuevas), nunca por estadísticas de reproducción.
        .onReceive(fileAccessService.$songs) { songs in
            songCount = songs.count
            reloadContent()
        }
        .onAppear { appeared = true }
    }

    // MARK: - 1. Header

    private var greetingKey: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "welcome.goodMorning" }
        if hour < 19 { return "welcome.goodAfternoon" }
        return "welcome.goodEvening"
    }

    /// ✅ POLISH: el header empieza con una pieza gráfica (como NowPlaying y los
    /// detalles de álbum/artista, que siempre abren con carátula o icono). Antes
    /// era solo texto: el punto más débil de la portada.
    private var headerSection: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(AppTheme.accentGradient(opacity: 0.16))
                    .frame(width: 46, height: 46)

                Image(systemName: "music.note")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppTheme.accentGradient)
            }
            .overlay(
                Circle().strokeBorder(
                    LinearGradient(
                        colors: [AppTheme.accent.opacity(0.45), AppTheme.accent.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(Localization.localized(greetingKey))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.accentGradient)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text(Localization.localized("welcome.subtitle"))
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - 2. Mezcla del día

    private var dailyMixSection: some View {
        Button {
            playSongs(dailyMixSongs)
        } label: {
            ZStack(alignment: .bottomLeading) {
                // Gradiente de acento (dos colores) + carátula de la primera
                // canción como textura. Nada de blur de pantalla completa.
                LinearGradient(
                    colors: [AppTheme.accent, AppTheme.accent.opacity(0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                if let artwork = dailyMixSongs.first?.artwork {
                    Image(uiImage: AppTheme.thumbnail(from: artwork, size: CGSize(width: 600, height: 600)))
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFill()
                        .opacity(0.32)
                        .allowsHitTesting(false)
                }

                // ✅ POLISH: barrido diagonal del acento sobre la carátula — da
                // dirección a la textura y sube el contraste del texto sin velos
                // opacos (nada de blur de superficie completa).
                LinearGradient(
                    colors: [AppTheme.accent.opacity(0.5), .clear, AppTheme.accent.opacity(0.22)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Velo inferior para que el texto siempre sea legible.
                LinearGradient(
                    colors: [.black.opacity(0.5), .black.opacity(0.05), .clear],
                    startPoint: .bottom,
                    endPoint: .top
                )

                dailyMixLabels
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .topLeading) {
                dailyMixBadge
                    .padding(16)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
            )
            .shadow(color: AppTheme.accent.opacity(0.35), radius: 20, x: 0, y: 10)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.985))
        .disabled(dailyMixSongs.isEmpty)
        .opacity(dailyMixSongs.isEmpty ? 0.6 : 1)
        .padding(.horizontal, 20)
    }

    private var dailyMixLabels: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Localization.localized("smart.dailyMix"))
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(Localization.localized("welcome.updatedToday"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))

            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.black.opacity(0.35)))

                Text(dailyMixChipLabel)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            // ✅ POLISH: se usa la primitiva de vidrio COMPARTIDA
            // (`nativeGlassCapsule`, ver OpaqueGlass.swift) en vez de
            // `.ultraThinMaterial` suelto: respeta "Reducir transparencia" igual
            // que el resto de la app. Sigue siendo un chip pequeño, nunca un blur
            // de superficie completa.
            .padding(.leading, 6)
            .padding(.trailing, 14)
            .padding(.vertical, 6)
            .nativeGlassCapsule()
            .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.5))
        }
        .padding(20)
    }

    /// ✅ Badge editorial de la card del día: mayúsculas con letra espaciada sobre
    /// vidrio. El texto sale del nombre ya localizado de la mezcla (sin clave
    /// nueva) en mayúsculas.
    private var dailyMixBadge: some View {
        Text(Localization.localized(SmartPlaylist.dailyMix.nameKey).uppercased())
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(1.4)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .nativeGlassCapsule()
            .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
    }

    /// ✅ "12 canciones · Reproducir" — se compone como String (no como
    /// interpolación de `Text`) para no depender de cómo SwiftUI trate una
    /// LocalizedStringKey con dos comodines.
    private var dailyMixChipLabel: String {
        "\(localizedSongCount(dailyMixSongs.count)) · \(Localization.localized("actions.play"))"
    }

    // MARK: - 3. Tus playlists (automáticas)

    private var smartPlaylistsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("welcome.smartPlaylists")

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(SmartPlaylist.all) { playlist in
                        smartPlaylistCard(playlist)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
        }
    }

    private func smartPlaylistCard(_ playlist: SmartPlaylist) -> some View {
        let songs = smartContent[playlist.id] ?? []
        // ✅ POLISH: 170pt (antes 160) y todo el tratamiento en un solo sitio.
        let edge: CGFloat = 170

        return VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [playlist.colorHint.opacity(0.92), playlist.colorHint.opacity(0.45)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // ✅ POLISH: barrido diagonal de luz sobre el gradiente — una
                // superficie que antes era completamente plana.
                LinearGradient(
                    colors: [.white.opacity(0.22), .clear, .black.opacity(0.14)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Image(systemName: playlist.icon)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))

                playBadge {
                    playSongs(songs)
                }
                .padding(10)
            }
            .frame(width: edge, height: edge)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)

            Text(playlist.name)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(localizedSongCount(songs.count))
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(width: edge, alignment: .leading)
        .contentShape(Rectangle())
        // ✅ Tap en la card → lista completa (con estadísticas); el botón de play
        // reproduce directamente sin abrir nada.
        .onTapGesture {
            Haptics.light()
            selectedPlaylist = playlist
        }
    }

    // MARK: - 4. Recomendadas para ti

    private var recommendedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("welcome.recommended")

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                ForEach(recommendedSongs) { song in
                    recommendedCell(song)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func recommendedCell(_ song: Song) -> some View {
        Button {
            playSong(song)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    artworkThumb(song, edge: 160, corner: 16)
                    // ✅ POLISH: el play flotante usa la primitiva de vidrio
                    // compartida (respeta "Reducir transparencia") en vez del negro
                    // sólido, con filo y sombra propios. Sigue sin recibir toques:
                    // la celda entera reproduce.
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .nativeGlassCapsule()
                        .overlay(Circle().strokeBorder(.white.opacity(0.28), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
                        .padding(8)
                        .allowsHitTesting(false)
                }

                Text(song.displayName)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(song.displaySubtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(10)
            // ✅ Mismo patrón que las filas de la biblioteca: color opaco, sin blur,
            // ahora con el filo de vidrio y la sombra que sí usa el resto de la app
            // (sin ellos la rejilla se leía completamente plana).
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(UIColor.secondarySystemBackground).opacity(0.6))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.97))
    }

    // MARK: - 5. Tus artistas top

    private var topArtistsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("welcome.topArtists")

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(topArtists) { artist in
                        NavigationLink {
                            ArtistDetailView(
                                artist: artist,
                                audioEngine: audioEngine,
                                fileAccessService: fileAccessService
                            )
                        } label: {
                            artistCell(artist)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
        }
    }

    private func artistCell(_ artist: Artist) -> some View {
        VStack(spacing: 8) {
            Group {
                if let artwork = artist.artwork {
                    Image(uiImage: AppTheme.thumbnail(from: artwork, size: CGSize(width: 200, height: 200)))
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFill()
                } else {
                    Circle()
                        .fill(AppTheme.accentGradient(opacity: 0.35))
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 34))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                }
            }
            .frame(width: 110, height: 110)
            .clipShape(Circle())
            // ✅ POLISH: anillo de acento de 2pt — es lo que en el resto de la app
            // convierte una miniatura en un elemento claramente tocable.
            .overlay(
                Circle()
                    .strokeBorder(
                        AngularGradient(
                            colors: [
                                AppTheme.accent.opacity(0.55),
                                AppTheme.accent.opacity(0.15),
                                AppTheme.accent.opacity(0.45)
                            ],
                            center: .center
                        ),
                        lineWidth: 2
                    )
            )
            .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 5)

            Text(artist.name)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: 110)

            Text(localizedSongCount(artist.songs.count))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 6. Estado vacío

    /// ✅ POLISH: ilustración PROPIA de Bienvenida. Antes reutilizaba
    /// `ContentUnavailableLibraryView`, que es literalmente el mismo estado vacío
    /// de la Biblioteca → la portada no tenía identidad cuando la biblioteca estaba
    /// vacía, que es justo cuando más se ve.
    private var emptyLibrarySection: some View {
        VStack(spacing: 22) {
            emptyHero
            emptyTexts

            Button {
                Haptics.light()
                showFolderPicker = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text(Localization.localized("actions.addFolder"))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 26)
                .frame(height: 48)
                .background {
                    Capsule().fill(AppTheme.accentGradient)
                }
                .shadow(color: AppTheme.accent.opacity(0.35), radius: 12, x: 0, y: 6)
            }
            .buttonStyle(PressableButtonStyle(scale: 0.96))
        }
        .padding(.horizontal, 20)
        .padding(.top, 30)
    }

    /// ✅ Disco de acento al 10% + símbolo grande con el gradiente de dos colores,
    /// con anillo y sombra de tinte: mismo lenguaje que las cards destacadas.
    private var emptyHero: some View {
        ZStack {
            Circle()
                .fill(AppTheme.accentGradient(opacity: 0.1))
                .frame(width: 120, height: 120)

            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [AppTheme.accent.opacity(0.35), AppTheme.accent.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .frame(width: 120, height: 120)

            Image(systemName: "music.note.list")
                .font(.system(size: 72, weight: .medium))
                .foregroundStyle(AppTheme.accentGradient)
        }
        .shadow(color: AppTheme.accent.opacity(0.18), radius: 18, x: 0, y: 8)
    }

    private var emptyTexts: some View {
        VStack(spacing: 8) {
            Text(Localization.localized("welcome.emptyTitle"))
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            Text(Localization.localized("welcome.emptyMessage"))
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Piezas compartidas

    private func sectionTitle(_ key: String) -> some View {
        Text(Localization.localized(key))
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.horizontal, 20)
    }

    private func playBadge(_ action: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            Image(systemName: "play.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(.black.opacity(0.38)))
                .overlay(Circle().strokeBorder(.white.opacity(0.22), lineWidth: 0.5))
        }
        .buttonStyle(PressableButtonStyle(scale: 0.92))
    }

    /// ✅ Carátula SIEMPRE por miniatura cacheada (AppTheme.thumbnail), nunca la
    /// portada completa: en A11 eso es la diferencia entre 60 fps y tirones.
    private func artworkThumb(_ song: Song, edge: CGFloat, corner: CGFloat) -> some View {
        Group {
            if let image = song.artwork {
                Image(uiImage: AppTheme.thumbnail(from: image, size: CGSize(width: edge * 2, height: edge * 2)))
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [AppTheme.accent.opacity(0.35), AppTheme.accent.opacity(0.15)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .frame(width: edge, height: edge)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }

    // MARK: - Contenido y reproducción

    /// ✅ Se recalcula al abrir la pestaña y cuando cambia la biblioteca (termina
    /// de cargar o se indexan canciones nuevas), pero SIEMPRE con memoización: si
    /// nada relevante cambió y el último cálculo es reciente, se reutiliza.
    ///
    /// Motivo: cada consulta recorre y ordena la biblioteca entera, y las dos
    /// mezclas la barajan dos veces cada una. Con 1000+ canciones eso son varios
    /// órdenes completos por apertura de pestaña — y la pestaña se reabre a menudo.
    private func reloadContent(force: Bool = false) {
        let signature = Self.signature(for: fileAccessService)
        if !force,
           let cached = cachedContent,
           cached.signature == signature,
           Date().timeIntervalSince(cached.computedAt) < Self.cacheLifetime {
            AppLog.debug(.performance, "[Welcome] contenido reutilizado de caché (firma sin cambios)")
            return
        }

        let started = CFAbsoluteTimeGetCurrent()
        let service = fileAccessService
        var snapshot: [String: [Song]] = [:]
        for playlist in SmartPlaylist.all {
            snapshot[playlist.id] = measure(playlist.id) { playlist.songs(from: service) }
        }
        smartContent = snapshot
        recommendedSongs = Self.recommended(for: service)
        topArtists = Self.topArtists(for: service)
        cachedContent = CachedContent(signature: signature, computedAt: Date())

        let total = (CFAbsoluteTimeGetCurrent() - started) * 1000
        AppLog.debug(.performance, String(format: "[Welcome] reloadContent en %.1f ms", total))
    }

    /// ✅ Cronometra cada playlist automática: si alguna pasa de 50 ms es la
    /// culpable de los tirones al abrir la pestaña (diagnóstico de rendimiento).
    private func measure<T>(_ id: String, _ work: () -> T) -> T {
        let started = CFAbsoluteTimeGetCurrent()
        let result = work()
        let elapsed = (CFAbsoluteTimeGetCurrent() - started) * 1000
        if elapsed > 50 {
            AppLog.warning(.performance, String(format: "[Welcome] '%@' lenta: %.1f ms", id, elapsed))
        } else {
            AppLog.debug(.performance, String(format: "[Welcome] '%@' en %.1f ms", id, elapsed))
        }
        return result
    }

    // MARK: - Memoización del contenido

    /// ✅ Firma BARATA de "lo que cambia el contenido": tamaño de la biblioteca,
    /// reproducciones acumuladas, favoritos y el día/semana actuales (las mezclas
    /// dependen de ellos). Recorrer `playCounts` es O(canciones reproducidas).
    private struct ContentSignature: Equatable {
        let songs: Int
        let plays: Int
        let liked: Int
        let day: String
        let week: String
    }

    private struct CachedContent {
        let signature: ContentSignature
        let computedAt: Date
    }

    /// ✅ Vigencia máxima de la caché: aunque la firma no cambie, a los 5 minutos
    /// se recalcula (cubre "hace X horas" y cambios de hora del día).
    private static let cacheLifetime: TimeInterval = 300

    private static func signature(for service: FileAccessService) -> ContentSignature {
        ContentSignature(
            songs: service.songs.count,
            plays: service.playCounts.values.reduce(0, +),
            liked: service.likedSongs.count,
            day: SmartPlaylist.dayKey(),
            week: SmartPlaylist.weekKey()
        )
    }

    private func playSongs(_ songs: [Song]) {
        guard let first = songs.first else { return }
        Haptics.light()
        audioEngine.play(song: first, from: songs)
    }

    private func playSong(_ song: Song) {
        Haptics.light()
        // ✅ Contexto = la propia cuadrícula (el "siguiente" sigue las recomendadas).
        audioEngine.play(song: song, from: recommendedSongs)
    }

    /// ✅ "Recomendadas": casi nunca escuchadas (≤ 1 reproducción) pero que te
    /// gustan o llevan tiempo en la biblioteca. Si todavía no hay historial ni
    /// favoritos, cae a las menos reproducidas para no dejar la sección vacía.
    ///
    /// ✅ 3.0.1: el orden ya NO es "menos reproducciones primero". Ese `sorted`
    /// dejaba todos los empates al orden de la biblioteca (alfabético por título),
    /// así que con biblioteca nueva —todas a 0 reproducciones— la cuadrícula eran
    /// SIEMPRE las 10 primeras por título, y solo cambiaba "al consumirse" cuando
    /// cada una sonaba una vez. Ahora se puntúa cada candidata y el azar de la
    /// semilla del DÍA rompe los empates: favoritas y abandonadas pesan más,
    /// la lista es estable durante el día y distinta al siguiente.
    private static func recommended(for service: FileAccessService) -> [Song] {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
        let candidates = service.songs.filter { service.playCount(for: $0.id) <= 1 }
        let preferred = candidates.filter { song in
            service.isLiked(song) || SmartPlaylist.recency(song) < cutoff
        }
        let pool = preferred.isEmpty ? candidates : preferred

        // ✅ PRNG determinista ya existente (SplitMix64 sembrado con un hash
        // FNV-1a estable): NUNCA `String.hashValue`, que está aleatorizado por
        // proceso y daría una lista distinta en cada arranque de la app.
        var generator = SmartPlaylist.SeededGenerator(
            seed: SmartPlaylist.stableSeed("recommended-" + SmartPlaylist.dayKey())
        )

        let scored = pool.map { song -> (song: Song, score: Double) in
            var score = 0.0
            if service.isLiked(song) { score += 2.0 }
            if let last = service.lastPlayed(for: song.id) {
                // Lleva más de 30 días sin sonar.
                if last < cutoff { score += 1.5 }
            } else {
                // Nunca ha sonado.
                score += 1.0
            }
            if service.playCount(for: song.id) == 0 { score += 0.5 }
            // ✅ Azar con la semilla del día: rompe empates sin ser aleatorio
            // entre aperturas de la misma jornada.
            score += Double.random(in: 0...1, using: &generator)
            return (song, score)
        }

        let ranked = scored.sorted { $0.score > $1.score }
        // ✅ Sin keypath de tupla (Swift no lo permite): extracción explícita.
        return ranked.prefix(10).map { $0.song }
    }

    /// ✅ Artistas ordenados por reproducciones AGREGADAS de sus canciones. En
    /// empate gana el que tiene más canciones (así el carrusel no sale en orden
    /// arbitrario cuando el historial está a cero).
    private static func topArtists(for service: FileAccessService) -> [Artist] {
        let scored = service.artists.map { artist -> (artist: Artist, plays: Int) in
            (artist, artist.songs.reduce(0) { $0 + service.playCount(for: $1.id) })
        }
        let ranked = scored.sorted { first, second in
            if first.plays == second.plays { return first.artist.songs.count > second.artist.songs.count }
            return first.plays > second.plays
        }
        // ✅ Sin keypath de tupla (Swift no lo permite): extracción explícita.
        return ranked.prefix(10).map { $0.artist }
    }
}
