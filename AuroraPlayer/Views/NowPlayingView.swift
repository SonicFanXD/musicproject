import SwiftUI
import AVFoundation
import AVKit

struct NowPlayingView: View {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var fileAccessService: FileAccessService
    // ✅ El reloj ya NO se observa aquí: cada tick (0.4s) re-renderizaba TODA
    // la vista y un re-render en el instante del toque descartaba el primer
    // tap de shuffle/repeat. Ahora vive aislado en ProgressScrubView (patrón
    // PlayerBar) y aquí se guarda como valor plano para pasarlo a subvistas.
    let clock: PlaybackClock
    // ✅ REMAKE: presentación como overlay a pantalla completa (no sheet).
    // `heroNamespace` conecta la portada con la PlayerBar y `onClose` cierra
    // desde el header sin depender de un entorno de presentación.
    var heroNamespace: Namespace.ID? = nil
    var onClose: (() -> Void)? = nil
    // ✅ Observar el idioma: al cambiar, esta vista se re-renderiza al instante
    @ObservedObject private var localization = Localization.shared
    @Environment(\.dismiss) private var dismiss

    // Configuraciones de personalización
    @AppStorage("com.aurora.showVisualizer") private var showVisualizer = true
    @AppStorage("com.aurora.keepScreenOn") private var keepScreenOn = false
    @AppStorage("com.aurora.artworkCorner") private var artworkCorner: Double = 22
    @AppStorage("com.aurora.reduceTransparency") private var reduceTransparency = false
    // ✅ Ajuste "Mostrar letras" (antes no se aplicaba)
    @AppStorage("com.aurora.showLyricsByDefault") private var showLyricsByDefault = false

    @State private var showLyrics = false
    @State private var showEqualizer = false
    @State private var showQueue = false
    @State private var showQualityDetail = false
    // ✅ FIX log duplicado: el overlay puede reevaluarse durante la transición
    // de entrada y el onAppear puede correr más de una vez. El resto de
    // acciones son idempotentes; el LOG no: se guarda tras este flag para que
    // "NowPlaying abierto" aparezca una sola vez.
    @State private var hasLoggedAppear = false
    // ✅ NUEVO: menú de 3 puntos → ver artista / álbum / letras / cola / compartir
    @State private var showArtistDetail = false
    @State private var showAlbumDetail = false
    @State private var artworkScale: CGFloat = 1.0
    // ✅ M3E: opacidad de la portada y desplazamiento de la info para la
    // transición de canción (fade + micro-escala + slide con stagger).
    // Solo cambian al cambiar de pista: transformaciones GPU sobre una
    // única imagen, nunca crossfade de dos carátulas grandes (en A11
    // doblar el blit en el instante del cambio de pista no compensa).
    @State private var artworkOpacity: Double = 1.0
    @State private var infoOffset: CGFloat = 0
    @State private var infoOpacity: Double = 1.0
    // ✅ FUENTE ÚNICA: ThemeManager resuelve y publica el par de acento
    // (resolvedAccentPair + caché por huella de imagen). Esta vista SOLO LEE:
    // aquí no se extrae ni se computa ningún color.
    @ObservedObject private var theme = ThemeManager.shared

    // ✅ ESPEJOS DE VISTA (solo lectura; mismas firmas que antes para NO tocar
    // el layout ni las subvistas). Con "Acento desde portada" devuelven el par
    // publicado por ThemeManager; con el modo apagado, el acento manual.
    private var extractedColor: Color {
        if theme.accentFromArtwork, let c = theme.artworkAccentColor { return c }
        return AppTheme.accent
    }
    // ✅ Segundo color dominante de la carátula (solo con "Acento desde
    // portada" activo). Alimenta los gradientes de DOS colores, igual que en
    // PlayerBar y en Album/Artist detail.
    private var extractedSecondaryColor: Color? {
        guard theme.accentFromArtwork else { return nil }
        return theme.artworkSecondaryColor
    }
    // ✅ UIColor dominante crudo para calcular contraste
    private var extractedUIColor: UIColor {
        if theme.accentFromArtwork, let c = theme.artworkAccentUIColor { return c }
        return AppTheme.accentUIColor
    }

    // ✅ Sin caché local ni extracción: el clustering corre UNA vez por
    // carátula en ThemeManager (caché compartida por huella de imagen).


    // ✅ Scrub optimizado: preview local a 60fps, seek real solo al soltar.
    // (isScrubbing/scrubPreviewTime/progressBarWidth viven en ProgressScrubView)

    // MARK: - Adaptive sizing for iOS 16 & iPhone 8 Plus
    private var isCompactScreen: Bool {
        UIScreen.main.bounds.height < 800
    }

    private var artworkSize: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        // ✅ GOLPE FINAL: portada más grande y centrada, como el hero de un
        // reproductor Android. En el 8 Plus gana ~50 pt frente al layout iOS.
        let maxByWidth = screenWidth - 48
        let maxByHeight = screenHeight * (isCompactScreen ? 0.35 : 0.46)
        return min(360, maxByWidth, maxByHeight)
    }

    // ✅ Contraste: si el color dominante es claro → texto oscuro; si es oscuro → texto blanco
    private var playIconColor: Color { AppTheme.contrastingText(on: extractedUIColor) }

    // MARK: - Acento de DOS colores (mismo criterio que PlayerBar/Album/Artist)
    /// ✅ Par de colores del acento de ESTA canción (SIEMPRE dos): con "Acento
    /// desde portada", el dominante de la carátula + su secundario real; con el
    /// modo desactivado, el acento manual con su segunda parada al 40% (mismo
    /// criterio que `AppTheme.accentGradient`).
    private var accentPair: (primary: Color, secondary: Color) {
        if ThemeManager.shared.accentFromArtwork {
            return (extractedColor, extractedSecondaryColor ?? extractedColor.opacity(0.7))
        }
        return (AppTheme.accent, AppTheme.accent.opacity(0.4))
    }

    /// ✅ Gradiente de DOS colores con opacidad por parada: sustituye los
    /// antiguos `[color, color.opacity(x)]`, que eran de un solo color.
    private func accentGradient(
        start: UnitPoint = .topLeading,
        end: UnitPoint = .bottomTrailing,
        primaryOpacity: Double = 1,
        secondaryOpacity: Double = 1
    ) -> LinearGradient {
        let pair = accentPair
        return LinearGradient(
            colors: [pair.primary.opacity(primaryOpacity), pair.secondary.opacity(secondaryOpacity)],
            startPoint: start,
            endPoint: end
        )
    }

    /// ✅ Superficies con GLIFO BLANCO encima (botón de play y cápsulas de estado
    /// activo): si el secundario difiere MUCHO en brillo del primario, se
    /// conserva su TONO pero se ancla su BRILLO al del primario. El degradado
    /// sigue siendo de dos colores reales y la legibilidad del icono blanco
    /// queda igual que antes de este cambio.
    private func textSafeAccentGradient(primaryOpacity: Double = 1, secondaryOpacity: Double = 1) -> LinearGradient {
        let pair = accentPair
        var secondaryStop = pair.secondary
        var h1: CGFloat = 0, s1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 1
        var h2: CGFloat = 0, s2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 1
        if UIColor(pair.primary).getHue(&h1, saturation: &s1, brightness: &b1, alpha: &a1),
           UIColor(pair.secondary).getHue(&h2, saturation: &s2, brightness: &b2, alpha: &a2),
           abs(b1 - b2) > 0.3 {
            secondaryStop = Color(UIColor(hue: h2, saturation: s2, brightness: b1, alpha: a2))
        }
        return LinearGradient(
            colors: [pair.primary.opacity(primaryOpacity), secondaryStop.opacity(secondaryOpacity)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // ✅ I-3 RESUELTO: la carga async duplicada del secundario (con su
    // animación de 0.3s, causa del parpadeo al abrir) ya no existe. El
    // secundario llega publicado desde ThemeManager y la vista solo lo lee.

    // ✅ NUEVO: resoluciones para el menú de 3 puntos (artista/álbum actuales)
    private var currentArtist: Artist? {
        guard let song = audioEngine.currentSong else { return nil }
        let preferred = song.albumArtist.isEmpty ? song.artist : song.albumArtist
        return fileAccessService.artists.first { $0.name == preferred }
            ?? fileAccessService.artists.first { $0.name == song.artist }
    }

    private var currentAlbum: Album? {
        guard let song = audioEngine.currentSong, !song.album.isEmpty else { return nil }
        return fileAccessService.albums.first { $0.name == song.album && $0.artist == song.albumArtist }
            ?? fileAccessService.albums.first { $0.name == song.album }
    }

    var body: some View {
        ZStack {
            backgroundView

            // ✅ ESTRUCTURA FIJA: el header es una fila propia de 44pt + 8pt de
            // margen, hermana del contenido (ya no comparten inset). El
            // contenido vive en un contenedor flexible que ocupa el resto de la
            // hoja y se centra DENTRO de él, así que la altura del contenido
            // (título de 1 o 2 líneas, chip presente o no) ya no puede mover el
            // header: su fila mide siempre lo mismo.
            VStack(spacing: 0) {
                headerView

                // ✅ DISEÑO MEJORADO: distribución equilibrada con Spacers
                // flexibles (la proporción se adapta a cualquier pantalla,
                // iPhone 8 Plus incluido) en lugar de espaciados fijos.
                VStack(spacing: 0) {
                    artworkView
                        // ✅ M3E: la portada reacciona al CAMBIAR de canción con
                        // fade + micro-escala (el resorte se dispara desde
                        // onChange más abajo); nunca al pausar/resumir.
                        .scaleEffect(artworkScale)
                        .opacity(artworkOpacity)

                    Spacer(minLength: isCompactScreen ? 10 : 16)

                    // ✅ GOLPE FINAL: info ALINEADA A LA IZQUIERDA (título,
                    // artista y chip de calidad), como una fila de Android.
                    songInfoView
                        // ✅ M3E: la info entra con un slide vertical sutil y
                        // fundido, escalonado 40 ms respecto a la portada.
                        .offset(y: infoOffset)
                        .opacity(infoOpacity)

                    if showVisualizer {
                        // ✅ Mismo sistema de DOS colores que el resto de la vista.
                        // Va debajo de la info y alineado a la izquierda: en
                        // Android el visualizador acompaña al texto, no flota
                        // centrado sobre la portada.
                        AudioVisualizer(
                            audioEngine: audioEngine,
                            tintColor: extractedColor,
                            secondaryTintColor: extractedSecondaryColor
                        )
                            .frame(height: isCompactScreen ? 26 : 38)
                            .padding(.horizontal, 2)
                            .padding(.top, isCompactScreen ? 4 : 8)
                    }

                    Spacer(minLength: isCompactScreen ? 6 : 10)

                    // ✅ Barra ondulada + tiempos justo ENCIMA de los controles
                    // (orden de un reproductor Android, no debajo del título).
                    ProgressScrubView(
                        audioEngine: audioEngine,
                        clock: clock,
                        extractedColor: extractedColor,
                        extractedSecondaryColor: extractedSecondaryColor,
                        extractedUIColor: extractedUIColor,
                        playIconColor: playIconColor,
                        isCompactScreen: isCompactScreen
                    )
                    .frame(maxWidth: .infinity)

                    Spacer(minLength: isCompactScreen ? 2 : 6)

                    controlsView

                    Spacer(minLength: isCompactScreen ? 8 : 14)

                    featureButtonsView

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
                .fixedSize(horizontal: false, vertical: true)
                // ✅ El contenido (portada, visualizador, info, progreso,
                // controles y botones) se centra en el espacio RESTANTE bajo el
                // header; su altura ya no influye en la fila del header.
                .frame(maxHeight: .infinity)
            }
            }
            .onAppear {
                if !hasLoggedAppear {
                    hasLoggedAppear = true
                    AppLog.info(.interface, "NowPlaying abierto: '\(audioEngine.currentSong?.displayName ?? "—")'")
                }
                withAnimation(AuroraMotion.spatialDefault) {
                    artworkScale = 1.0
                }
                audioEngine.isKeepScreenOnEnabled = keepScreenOn
                // ✅ Abrir letras automáticamente si el ajuste está activado
                // y la canción tiene letras sincronizadas/plain
                if showLyricsByDefault, audioEngine.currentSong?.lyrics.isEmpty == false, !showLyrics {
                    showLyrics = true
                }
            }
            .onChange(of: audioEngine.isPlaying) { isPlaying in
                UIApplication.shared.isIdleTimerDisabled = keepScreenOn && isPlaying
            }
            .onChange(of: audioEngine.currentSong?.id) { _ in
                // ✅ Propagar el color de acento a ThemeManager para que PlayerBar
                // y todas las vistas que lo observen se actualicen al instante
                // (ThemeManager resuelve y cachea; aquí no se extrae nada).
                ThemeManager.shared.updateArtworkAccent(from: audioEngine.currentSong)
                // ✅ M3E: entrada de la nueva pista en DOS fases (patrón
                // obligatorio en SwiftUI: si el estado inicial y el final se
                // escriben en el mismo tick, coalescen y NO hay diff que
                // animar). Fase 1: snap al estado inicial SIN animación.
                // Fase 2 (siguiente tick): los springs lanzan la entrada. La
                // portada y la info comparten curva (normal) con 40 ms de
                // stagger: la sensación es un "despliegue" orgánico, no dos
                // animaciones sueltas.
                var snap = Transaction()
                snap.disablesAnimations = true
                withTransaction(snap) {
                    artworkScale = 0.94
                    artworkOpacity = 0
                    infoOffset = 12
                    infoOpacity = 0
                }
                DispatchQueue.main.async {
                    withAnimation(AuroraMotion.spatialDefault) {
                        artworkScale = 1.0
                        artworkOpacity = 1.0
                    }
                    withAnimation(AuroraMotion.spatialDefault.delay(0.04)) {
                        infoOffset = 0
                        infoOpacity = 1
                    }
                }
            }
            .onChange(of: ThemeManager.shared.accentFromArtwork) { value in
                // ✅ FIX: propaga el color a ThemeManager (que a su vez publica a
                // PlayerBar y todas las vistas) — no solo re-extraer localmente.
                // Así PlayerBar/NowPlaying cambian de acento al activar el toggle
                // en Settings sin esperar a un cambio de canción.
                if value, let song = audioEngine.currentSong {
                    ThemeManager.shared.updateArtworkAccent(from: song)
                }
            }
            // ✅ REMAKE: destinos del menú de 3 puntos como PANTALLAS COMPLETAS
            // M3E. El detalle entra como raíz de su propio stack (sin back
            // nativo; su header cierra con dismiss) y el tint cubre alerts,
            // sliders y controles internos. Nada de sheets apilados sobre la
            // pantalla de reproducción.
            // ✅ M3E: sin `NavigationStack`; el detalle trae su propio top app
            // bar y `dismiss` cierra la pantalla completa.
            .m3eScreen(isPresented: $showArtistDetail) {
                if let artist = currentArtist {
                    ArtistDetailView(artist: artist, audioEngine: audioEngine, fileAccessService: fileAccessService)
                }
            }
            .m3eScreen(isPresented: $showAlbumDetail) {
                if let album = currentAlbum {
                    AlbumDetailView(album: album, audioEngine: audioEngine, fileAccessService: fileAccessService)
                }
            }
            // ✅ REMAKE: pantallas completas M3E, no sheets.
            .fullScreenCover(isPresented: $showLyrics) {
                LyricsView(song: audioEngine.currentSong, viewModel: audioEngine.lyricsViewModel)
            }
            .fullScreenCover(isPresented: $showEqualizer) {
                EqualizerView(audioEngine: audioEngine)
            }
            .m3eScreen(isPresented: $showQueue) {
                // ✅ E3.4: la cola necesita el servicio de archivos para el item
                // "Me gusta" del menú de "A continuación". Ya vivía aquí al lado.
                QueueView(audioEngine: audioEngine, fileAccessService: fileAccessService)
            }
            .overlay {
                if showQualityDetail {
                    qualityCardModal
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
            .animation(AuroraMotion.spatialDefault, value: showQualityDetail)
    }

    // MARK: - Header (fila fija: no depende de la altura del contenido)
    /// ✅ Antes vivía en `.safeAreaInset(edge: .top)` colgado del VStack del
    /// contenido, y ese VStack (con `.fixedSize`) se centra dentro del ZStack:
    /// al crecer el contenido —título de 2 líneas o chip— el bloque centrado
    /// subía ~Δaltura/2 y el header terminaba pegado al borde superior del
    /// sheet. Ahora es una fila propia del contenedor raíz: 44pt + 8pt de
    /// margen, idéntica con cualquier combinación de contenido.
    private var headerView: some View {
        HStack(spacing: 0) {
            Button {
                if let onClose {
                    onClose()
                } else {
                    dismiss()
                }
            } label: {
                Image(systemName: "chevron.down")
                    .foregroundStyle(playIconColor)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Localization.localized("nowPlaying.close"))

            Spacer()

            Text(Localization.localized("nowPlaying.title"))
                .font(M3ETypography.titleMediumEmphasized)
                .foregroundStyle(playIconColor.opacity(0.9))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 1)

            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        // ✅ Margen superior CONSTANTE: el header no debe tocar el borde del
        // sheet. Al ser una fila propia (no un inset compartido con el
        // contenido) es fijo por construcción: no depende del contenido
        // (título de 1/2 líneas, chip sí/no).
        .padding(.top, 8)
        .padding(.horizontal, 8)
    }

    // MARK: - Background (respeta "Reducir transparencia")
    private var backgroundView: some View {
        Group {
            if let artwork = audioEngine.currentSong?.artwork, !reduceTransparency {
                // ✅ FASE 1 (remake): vuelve el fondo de portada desenfocado que
                // pide la referencia. La imagen queda recortada a la pantalla y
                // OPACA (clipped + opaque) y encima lleva el velo tonal del color
                // extraído: la portada es atmósfera, no un cristal interactivo.
                GeometryReader { geo in
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .blur(radius: 40, opaque: true)
                        .opacity(0.6)
                        .overlay(
                            LinearGradient(
                                colors: [
                                    extractedColor.opacity(0.30),
                                    extractedColor.opacity(0.18),
                                    M3EColor.surface.opacity(0.94)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            } else {
                LinearGradient(
                    colors: [
                        M3EColor.surface,
                        M3EColor.surfaceContainerLow
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Artwork (mejorado con mejor sombras y efectos)
    private var artworkView: some View {
        Group {
            if let artwork = audioEngine.currentSong?.artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .interpolation(.high) // ✅ Mejor calidad de interpolación
                    .scaledToFill()
                    .frame(width: artworkSize, height: artworkSize)
                    .clipShape(RoundedRectangle(cornerRadius: CGFloat(artworkCorner), style: .continuous))
                    // ✅ 60fps: sombra ÚNICA consolidada (la doble sombra forzaba
                    // 2 pasadas de offscreen rendering por frame; visualmente
                    // equivalente con radius medio + borde luminoso).
                    .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8)
                    .overlay(
                        // ✅ Borde con brillo sutil
                        RoundedRectangle(cornerRadius: CGFloat(artworkCorner), style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.15), extractedColor.opacity(0.2), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: CGFloat(artworkCorner), style: .continuous)
                        .fill(accentGradient(primaryOpacity: 0.3, secondaryOpacity: 0.1))
                        .frame(width: artworkSize, height: artworkSize)

                    Image(systemName: "music.note")
                        .font(.system(size: artworkSize * 0.15, weight: .light))
                        .foregroundStyle(extractedColor.opacity(0.8))
                }
                .shadow(color: .black.opacity(0.15), radius: 15, x: 0, y: 8)
                .shadow(color: extractedColor.opacity(0.15), radius: 8, x: 0, y: 4)
            }
        }
        .modifier(NowPlayingHeroModifier(namespace: heroNamespace))
    }

    /// ✅ Fuente del título de `songInfoView`.
    private var songTitleFont: Font {
        // ✅ FASE 2 (M3E): rol `titleLargeEmphasized` (22/semibold). El peso
        // "emphasized" de M3E es UN paso sobre el baseline (medium → semibold),
        // no `heavy`: el título sigue siendo el foco sin romper la escala.
        M3ETypography.titleLargeEmphasized
    }

    /// ✅ Fuentes del chip de calidad (línea de calidad y línea de ruta).
    private var qualityChipFont: Font {
        M3ETypography.labelMedium
    }

    private var routeChipFont: Font {
        M3ETypography.labelSmall
    }

    // MARK: - Song Info (mejorado con mejor tipografía y espaciado)
    private var songInfoView: some View {
        // ✅ GOLPE FINAL: bloque alineado a la IZQUIERDA. El corazón queda a la
        // derecha de la fila (patrón Android); ya no se centra todo el bloque
        // como una hoja de iOS.
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(audioEngine.currentSong?.displayName ?? Localization.localized("quality.noSong"))
                    .font(songTitleFont)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(playIconColor)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(audioEngine.currentSong?.displaySubtitle ?? "—")
                    .font(M3ETypography.labelLargeEmphasized)
                    .foregroundStyle(playIconColor.opacity(0.72))
                    .lineLimit(1)

                if let song = audioEngine.currentSong, !song.audioQualityDescription.isEmpty {
                    Button {
                        Haptics.light()
                        showQualityDetail = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "waveform.circle.fill")
                                .font(.system(size: 10, weight: .semibold))

                            VStack(alignment: .leading, spacing: 1) {
                                Text(song.audioQualityDescription)
                                    .font(qualityChipFont)

                                if !audioEngine.routeDisplay.isEmpty {
                                    Text(audioEngine.routeDisplay)
                                        .font(routeChipFont)
                                        .foregroundStyle(playIconColor.opacity(0.7))
                                }
                            }

                            Image(systemName: "chevron.down")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(extractedColor.opacity(0.6))
                        }
                        .foregroundStyle(playIconColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background {
                            Capsule().fill(extractedColor.opacity(0.22))
                        }
                        .overlay {
                            Capsule().strokeBorder(playIconColor.opacity(0.15), lineWidth: 0.5)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Localization.localized("quality.viewDetails"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Haptics.light()
                if let song = audioEngine.currentSong {
                    fileAccessService.toggleLike(song)
                }
            } label: {
                Image(systemName: isCurrentLiked ? "heart.fill" : "heart")
                    .font(.system(size: 18, weight: isCurrentLiked ? .bold : .semibold))
                    .foregroundStyle(isCurrentLiked ? Color.red : playIconColor.opacity(0.75))
                    .frame(width: 42, height: 42)
                    .background(
                        Circle().fill(extractedColor.opacity(0.18))
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(PressableButtonStyle(scale: AuroraPressScale.chip, pressedOpacity: 0.6))
            .animation(AuroraMotion.spatialFast, value: isCurrentLiked)
            .accessibilityLabel(Localization.localized("actions.like"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }

    // MARK: - Progress View (scrub fluido a 60fps)
    // ⚠️ ELIMINADO de NowPlayingView: la barra vive en ProgressScrubView
    // (al final de este archivo) para que el reloj (0.4s) NO re-renderice
    // esta vista y los botones de shuffle/repeat respondan al primer toque.

    // MARK: - Controls
    private var controlsView: some View {
        // ✅ GOLPE FINAL: fila de transporte Android. El play deja de ser un
        // círculo flotante y pasa a ser una PÍLDORA con icono + texto, con
        // shuffle/prev/next/repeat a los lados.
        HStack(spacing: isCompactScreen ? 2 : 6) {
            transportIcon(
                icon: "shuffle",
                isActive: audioEngine.isShuffleEnabled,
                accessibility: Localization.localized("accessibility.shuffle")
            ) {
                audioEngine.toggleShuffle()
            }
            .animation(AuroraMotion.spatialFast, value: audioEngine.isShuffleEnabled)

            transportIcon(
                icon: "backward.fill",
                accessibility: Localization.localized("accessibility.previousSong")
            ) {
                audioEngine.playPrevious()
            }

            playPill

            transportIcon(
                icon: "forward.fill",
                enabled: audioEngine.hasNextTrack,
                accessibility: Localization.localized("accessibility.nextSong")
            ) {
                audioEngine.playNext()
            }

            transportIcon(
                icon: repeatIcon,
                isActive: audioEngine.repeatMode != .off,
                accessibility: Localization.localized("accessibility.repeat")
            ) {
                audioEngine.cycleRepeatMode()
            }
            .animation(AuroraMotion.spatialFast, value: audioEngine.repeatMode)
        }
        .frame(maxWidth: .infinity)
    }

    /// Píldora central de reproducción. Mantiene el morph de ancho de M3E
    /// (más ancha al reproducir) pero con la forma de píldora que pide el
    /// lenguaje Android, no un círculo.
    private var playPill: some View {
        Button {
            Haptics.medium()
            if audioEngine.isPlaying {
                audioEngine.pause()
            } else {
                audioEngine.resume()
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: audioEngine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: isCompactScreen ? 15 : 17, weight: .bold))

                Text(audioEngine.isPlaying
                     ? Localization.localized("actions.pause")
                     : Localization.localized("actions.play"))
                    .font(M3ETypography.labelLargeEmphasized)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(playIconColor)
            .padding(.horizontal, isCompactScreen ? 13 : 20)
            .frame(height: isCompactScreen ? 48 : 54)
            .background(
                Capsule(style: .continuous)
                    .fill(textSafeAccentGradient())
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(playIconColor.opacity(0.12), lineWidth: 1)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(M3ESquishButtonStyle())
        .accessibilityLabel(Localization.localized("accessibility.playPause"))
    }

    private func transportIcon(
        icon: String,
        isActive: Bool = false,
        enabled: Bool = true,
        accessibility: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: isCompactScreen ? 15 : 17, weight: isActive ? .bold : .semibold))
                .foregroundStyle(isActive ? playIconColor : playIconColor.opacity(0.72))
                .frame(width: isCompactScreen ? 40 : 46, height: isCompactScreen ? 40 : 46)
                .background {
                    Circle().fill(
                        isActive
                            ? AnyShapeStyle(textSafeAccentGradient(primaryOpacity: 0.38, secondaryOpacity: 0.38))
                            : AnyShapeStyle(Color.clear)
                    )
                }
                .contentShape(Circle())
        }
        .buttonStyle(M3ESquishButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(accessibility)
    }

    // MARK: - Feature Buttons (EQ · Letras · Cola · AirPlay en una sola línea)
    private var featureButtonsView: some View {
        let buttonSize: CGFloat = isCompactScreen ? 60 : 68
        let capsuleWidth: CGFloat = isCompactScreen ? 44 : 50
        let capsuleHeight: CGFloat = isCompactScreen ? 34 : 38
        let iconSize: CGFloat = isCompactScreen ? 15 : 17

        return HStack(spacing: isCompactScreen ? 10 : 14) {
            // Equalizador
            Button {
                Haptics.light()
                showEqualizer = true
            } label: {
                ZStack {
                    Capsule()
                        .fill(audioEngine.isEQEnabled
                              ? AnyShapeStyle(accentGradient(primaryOpacity: 0.25, secondaryOpacity: 0.25))
                              : AnyShapeStyle(Color.clear))
                        .frame(width: audioEngine.isEQEnabled ? capsuleWidth : capsuleHeight, height: capsuleHeight)
                        // ✅ M3E: la cápsula se EXPANDE desde el círculo del icono al
                        // activarse (morph de ancho, sin mover el frame exterior).
                        .animation(AuroraMotion.spatialDefault, value: audioEngine.isEQEnabled)

                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: iconSize, weight: audioEngine.isEQEnabled ? .bold : .semibold))
                        .foregroundStyle(audioEngine.isEQEnabled ? playIconColor : AppTheme.contrastingText(on: extractedUIColor).opacity(0.7))
                }
                .frame(width: buttonSize, height: buttonSize)
                .contentShape(Rectangle())
            }
            // ✅ M3E: rebote elástico al pulsar (antes `.plain`, sin respuesta).
            .buttonStyle(M3ESquishButtonStyle())
            .accessibilityLabel(Localization.localized("quality.accessibility.equalizer"))

            // Letras
            Button {
                Haptics.light()
                showLyrics = true
            } label: {
                ZStack {
                    Capsule()
                        .fill(audioEngine.currentSong?.lyrics.isEmpty == false
                              ? AnyShapeStyle(accentGradient(primaryOpacity: 0.25, secondaryOpacity: 0.25))
                              : AnyShapeStyle(Color.clear))
                        .frame(width: audioEngine.currentSong?.lyrics.isEmpty == false ? capsuleWidth : capsuleHeight, height: capsuleHeight)
                        .animation(AuroraMotion.spatialDefault, value: audioEngine.currentSong?.lyrics.isEmpty == false)

                    Image(systemName: audioEngine.currentSong?.lyrics.isEmpty == false ? "quote.bubble.fill" : "quote.bubble")
                        .font(.system(size: iconSize, weight: audioEngine.currentSong?.lyrics.isEmpty == false ? .bold : .semibold))
                        .foregroundStyle(audioEngine.currentSong?.lyrics.isEmpty == false ? playIconColor : AppTheme.contrastingText(on: extractedUIColor).opacity(0.7))
                }
                .frame(width: buttonSize, height: buttonSize)
                .contentShape(Rectangle())
            }
            // ✅ M3E: rebote elástico al pulsar (antes `.plain`, sin respuesta).
            .buttonStyle(M3ESquishButtonStyle())
            .accessibilityLabel(Localization.localized("quality.accessibility.lyrics"))

            // Cola
            Button {
                Haptics.light()
                showQueue = true
            } label: {
                ZStack {
                    Capsule()
                        .fill(audioEngine.nextUpQueue.isEmpty
                              ? AnyShapeStyle(Color.clear)
                              : AnyShapeStyle(accentGradient(primaryOpacity: 0.25, secondaryOpacity: 0.25)))
                        .frame(width: audioEngine.nextUpQueue.isEmpty ? capsuleHeight : capsuleWidth, height: capsuleHeight)
                        .animation(AuroraMotion.spatialDefault, value: audioEngine.nextUpQueue.isEmpty)

                    Image(systemName: "list.bullet")
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundStyle(audioEngine.nextUpQueue.isEmpty ? AppTheme.contrastingText(on: extractedUIColor).opacity(0.7) : playIconColor)
                }
                .frame(width: buttonSize, height: buttonSize)
                .contentShape(Rectangle())
            }
            // ✅ M3E: rebote elástico al pulsar (antes `.plain`, sin respuesta).
            .buttonStyle(M3ESquishButtonStyle())
            .accessibilityLabel(Localization.localized("quality.accessibility.queue"))

            // ✅ AirPlay (FIX): en vez de abrir un sheet con un AVRoutePickerView
            // gigante que fallaba, el picker NATIVO de iOS va superpuesto e
            // invisible sobre el botón: al tocar, iOS muestra directamente su
            // menú emergente de AirPlay (comportamiento estándar del sistema).
            ZStack {
                // Botón visual (icono + resaltado si la salida es AirPlay)
                Capsule()
                    .fill(audioEngine.outputPortType == AVAudioSession.Port.airPlay.rawValue
                          ? AnyShapeStyle(accentGradient(primaryOpacity: 0.25, secondaryOpacity: 0.25))
                          : AnyShapeStyle(Color.clear))
                    .frame(width: audioEngine.outputPortType == AVAudioSession.Port.airPlay.rawValue ? capsuleWidth : capsuleHeight, height: capsuleHeight)
                    .animation(AuroraMotion.spatialDefault, value: audioEngine.outputPortType == AVAudioSession.Port.airPlay.rawValue)

                Image(systemName: "airplayaudio")
                    .font(.system(size: iconSize, weight: audioEngine.outputPortType == AVAudioSession.Port.airPlay.rawValue ? .bold : .semibold))
                    .foregroundStyle(audioEngine.outputPortType == AVAudioSession.Port.airPlay.rawValue ? playIconColor : AppTheme.contrastingText(on: extractedUIColor).opacity(0.7))

                // ✅ Picker nativo invisible encima: captura el toque y muestra
                // el menú de AirPlay del sistema. opacity 0.011 (no 0) para que
                // UIKit siga entregando los toques al AVRoutePickerView.
                AirPlayRoutePickerView()
                    .frame(width: buttonSize, height: buttonSize)
                    .opacity(0.011)
                    .contentShape(Rectangle())
            }
            .frame(width: buttonSize, height: buttonSize)
            .contentShape(Rectangle())
            .accessibilityLabel(Localization.localized("quality.accessibility.airplay"))
            // Menu de opciones (3 puntos)
            Menu {
                if currentArtist != nil {
                    Button {
                        Haptics.light()
                        showArtistDetail = true
                    } label: {
                        Label(Localization.localized("nowPlaying.viewArtist"), systemImage: "person.crop.circle")
                    }
                }
                if currentAlbum != nil {
                    Button {
                        Haptics.light()
                        showAlbumDetail = true
                    } label: {
                        Label(Localization.localized("nowPlaying.viewAlbum"), systemImage: "square.stack")
                    }
                }
                Button {
                    Haptics.light()
                    showLyrics = true
                } label: {
                    Label(Localization.localized("nowPlaying.viewLyrics"), systemImage: "quote.opening")
                }
                Button {
                    Haptics.light()
                    showQueue = true
                } label: {
                    Label(Localization.localized("nowPlaying.viewQueue"), systemImage: "list.number")
                }
                if let url = audioEngine.currentSong?.url {
                    Divider()
                    ShareLink(item: url) {
                        Label(Localization.localized("nowPlaying.shareSong"), systemImage: "square.and.arrow.up")
                    }
                }
            } label: {
                ZStack {
                    Capsule()
                        .fill(Color.clear)
                        .frame(width: capsuleWidth, height: capsuleHeight)

                    Image(systemName: "ellipsis")
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundStyle(AppTheme.contrastingText(on: extractedUIColor).opacity(0.7))
                }
                .frame(width: buttonSize, height: buttonSize)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(Localization.localized("nowPlaying.more"))
        }
        .frame(maxWidth: .infinity)
        .fixedSize()
    }

    // MARK: - Modal centrado con X (ventana emergente sobre el NowPlaying)
    private var qualityCardModal: some View {
        ZStack {
            // ✅ Velo translúcido SIN material: el arte y el entorno de
            // NowPlaying se siguen viendo claramente detrás (solo oscurecido).
            Color.black.opacity(0.22)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(AuroraMotion.spatialFast) {
                        showQualityDetail = false
                    }
                }
                .transition(.opacity)

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "waveform.badge.magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)

                    Text(Localization.localized("audio.quality.title"))
                        .font(M3ETypography.titleMediumEmphasized)
                        .foregroundStyle(.primary)

                    Spacer()

                    Button {
                        Haptics.light()
                        withAnimation(AuroraMotion.spatialFast) {
                            showQualityDetail = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background {
                                Circle().fill(Color.secondary.opacity(0.15))
                            }
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Localization.localized("audio.quality.close"))
                }
                .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 8)

                AudioQualityDetailView(audioEngine: audioEngine)
            }
            // ✅ Panel EXPANDIDO: mejor legibilidad y espacio para todos los detalles
            // Aumentado de 480x440 a 520x500 para mejor experiencia visual.
            .frame(maxWidth: 520, maxHeight: 500)
            .background {
                // ✅ M3E: panel de superficie SÓLIDA (SurfaceContainer). El
                // material obligaba a muestrear el arte desenfocado del fondo
                // en cada frame del panel; un color del sistema con el mismo
                // radio y borde da la misma jerarquía sin coste de composición.
                RoundedRectangle(cornerRadius: AuroraRadius.xl, style: .continuous)
                    .fill(M3EColor.surfaceContainerHigh)
                    // ✅ Una sola sombra (la doble costaba render en A11)
                    .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 12)
            }
            .overlay {
                // ✅ Borde luminoso "hifi" (solo si hay transparencia real;
                // con Reduce Transparency el borde no aporta nada sobre opaco)
                if !reduceTransparency {
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.45), .white.opacity(0.06), .clear],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .padding(.horizontal, 24)
            // ✅ Animación de entrada ligera: fade + scale SUTIL (sin blur —
            // el blur animado provocaba tirones en dispositivos antiguos).
            .scaleEffect(showQualityDetail ? 1.0 : 0.94)
            .opacity(showQualityDetail ? 1.0 : 0)
        }
        .animation(AuroraMotion.spatialDefault, value: showQualityDetail)
    }

    // MARK: - Helpers
    private var controlBackground: AnyShapeStyle {
        // ✅ M3E (Bloque 3): contenedor SÓLIDO, no material. `.ultraThinMaterial`
        // sobre la carátula obliga a un pase offscreen por cada uno de los 4
        // círculos del transporte en CADA frame del reloj/animación; en el A11 eso
        // se paga en batería. Un negro translúcido plano da el mismo contraste
        // (los glifos son siempre blancos) sin coste de composición.
        reduceTransparency
            ? AnyShapeStyle(Color.black.opacity(0.45))
            : AnyShapeStyle(Color.black.opacity(0.3))
    }

    private var isCurrentLiked: Bool {
        guard let song = audioEngine.currentSong else { return false }
        return fileAccessService.isLiked(song)
    }
    private var repeatIcon: String {
        switch audioEngine.repeatMode {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

}

// MARK: - Barra de progreso AISLADA del reloj (patrón PlayerBar)
// La única subvista que observa PlaybackClock: NowPlayingView ya no
// re-renderiza cada 0.4s → los botones (shuffle/repeat) responden siempre
// al primer toque, sin que un re-render descarte el gesto.
private struct ProgressScrubView: View {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var clock: PlaybackClock
    let extractedColor: Color
    /// ✅ Segundo color de la carátula: hace que la barra también sea de dos
    /// colores (leading → trailing), como el track del PlayerBar.
    let extractedSecondaryColor: Color?
    let extractedUIColor: UIColor
    let playIconColor: Color
    let isCompactScreen: Bool

    @State private var isScrubbing = false
    @State private var scrubPreviewTime: TimeInterval = 0

    private var progress: Double {
        if isScrubbing {
            guard audioEngine.duration > 0 else { return 0 }
            return min(max(scrubPreviewTime / audioEngine.duration, 0), 1)
        }
        guard audioEngine.duration > 0 else { return 0 }
        return min(max(clock.time / audioEngine.duration, 0), 1)
    }

    private var scrubPreviewText: String {
        formatTime(isScrubbing ? scrubPreviewTime : clock.time)
    }

    var body: some View {
        VStack(spacing: 8) {
            // ✅ FASE 1 (remake): el gesto vive dentro del componente, que ya
            // conoce su ancho real con GeometryReader. Aquí solo se traduce el
            // progreso 0...1 a tiempo y se hace UN seek al soltar.
            AuroraWavyProgress(
                progress: isScrubbing ? scrubPreviewTime / max(audioEngine.duration, 1) : clock.time / max(audioEngine.duration, 1),
                isPlaying: audioEngine.isPlaying,
                isScrubbing: isScrubbing,
                onScrub: { newProgress in
                    guard audioEngine.duration > 0 else { return }
                    if !isScrubbing { Haptics.selection() }
                    isScrubbing = true
                    scrubPreviewTime = audioEngine.duration * newProgress
                },
                onScrubEnd: { newProgress in
                    guard audioEngine.duration > 0 else { return }
                    isScrubbing = false
                    Haptics.light()
                    audioEngine.seek(to: audioEngine.duration * newProgress)
                }
            )
            .frame(maxWidth: .infinity)
            .frame(height: 18)
            .padding(.vertical, isCompactScreen ? 6 : 10)

            HStack {
                Text(scrubPreviewText)
                    .font(M3ETypography.timeDisplayCompact)
                    .foregroundStyle(isScrubbing ? playIconColor : AppTheme.contrastingText(on: extractedUIColor).opacity(0.75))
                    .monospacedDigit()
                    // ✅ M3E: color/peso = efecto → effectsDefault (sin rebote).
                    .animation(AuroraMotion.effectsDefault, value: isScrubbing)

                Spacer()

                Text(formatTime(audioEngine.duration))
                    .font(M3ETypography.timeDisplayCompact)
                    .foregroundStyle(AppTheme.contrastingText(on: extractedUIColor).opacity(0.75))
                    .monospacedDigit()
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard !time.isNaN && time.isFinite else { return "0:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - AirPlay Route Picker View (UIKit wrapper)
// ✅ FIX: el picker nativo embebido directamente (no dentro de un contenedor
// extra). Al tocarlo, iOS muestra su menú emergente de AirPlay del sistema.
struct AirPlayRoutePickerView: UIViewRepresentable {
    typealias UIViewType = AVRoutePickerView

    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = false
        // ✅ FIX: usar AppTheme.accent (UIColor(AppTheme.accent) resolvía el
        // asset por defecto y no respetaba el ajuste "Color de acento")
        picker.tintColor = AppTheme.accentUIColor
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        // FIX: reaccionar al acento dinamico de la caratula / acento manual
        let tint = AppTheme.accentUIColor
        if uiView.tintColor != tint { uiView.tintColor = tint }
    }
}

// MARK: - Hero de la portada

/// Aplica `matchedGeometryEffect` solo cuando NowPlaying se presenta como
/// overlay con un namespace compartido. Si se usa como vista suelta (preview
/// o presentación antigua), no toca la jerarquía.
private struct NowPlayingHeroModifier: ViewModifier {
    let namespace: Namespace.ID?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: "nowPlaying.artwork", in: namespace)
        } else {
            content
        }
    }
}
