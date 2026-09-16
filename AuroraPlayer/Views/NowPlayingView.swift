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
    // ✅ Observar el idioma: al cambiar, esta vista se re-renderiza al instante
    @ObservedObject private var localization = Localization.shared
    // ✅ Observar el tema: al activar/desactivar "Acento desde carátula" (o al
    // resolverse el color dominante de forma asíncrona) esta vista se entera y
    // vuelve a aplicar los colores, sin quedarse con los de la portada anterior.
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.dismiss) private var dismiss

    // Configuraciones de personalización
    @AppStorage("com.aurora.showVisualizer") private var showVisualizer = true
    @AppStorage("com.aurora.keepScreenOn") private var keepScreenOn = false
    @AppStorage("com.aurora.artworkCorner") private var artworkCorner: Double = 22
    @AppStorage("com.aurora.reduceTransparency") private var reduceTransparency = false
    // ✅ Ajuste "Mostrar letras" (antes no se aplicaba)
    @AppStorage("com.aurora.showLyricsByDefault") private var showLyricsByDefault = false
    @AppStorage("com.aurora.visualizerStyle") private var visualizerStyle = 0 // 0 = clásico, 1 = elegante, 2 = moderno

    @State private var showLyrics = false
    @State private var showEqualizer = false
    @State private var showQueue = false
    @State private var showQualityDetail = false
    // ✅ NUEVO: menú de 3 puntos → ver artista / álbum / letras / cola / compartir
    @State private var showArtistDetail = false
    @State private var showAlbumDetail = false
    @State private var artworkScale: CGFloat = 1.0
    @State private var extractedColor: Color = AppTheme.accent
    // ✅ Guardamos el UIColor dominante crudo para calcular contraste
    // ✅ FIX: usar accentUIColor en vez de systemPurple hardcodeado
    @State private var extractedUIColor: UIColor = AppTheme.accentUIColor

    // ✅ Caché de color dominante por canción: evita recalcular el histograma
    // HSB al reabrir NowPlaying o re-entrar a la misma pista (60fps sin hitch)


    // ✅ Scrub optimizado: preview local a 60fps, seek real solo al soltar.
    // (isScrubbing/scrubPreviewTime/progressBarWidth viven en ProgressScrubView)

    // Tamaño de la vista presentada, no de la pantalla física (rotación/iPad).
    @State private var availableSize = CGSize(width: 414, height: 736)
    private var isCompactScreen: Bool { availableSize.height < 800 }

    private var artworkSize: CGFloat {
        let maxByWidth = max(0, availableSize.width - 40)
        let maxByHeight = availableSize.height * (isCompactScreen ? 0.35 : 0.45)
        return min(340, maxByWidth, maxByHeight)
    }

    // Blanco fijo por preferencia de diseño.
    private var playIconColor: Color { AppTheme.contrastingText(on: extractedUIColor) }

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

                // ✅ DISEÑO MEJORADO: distribución equilibrada con Spacers
                // flexibles (la proporción se adapta a cualquier pantalla,
                // iPhone 8 Plus incluido) en lugar de espaciados fijos.
                VStack(spacing: 0) {
                    // ✅ Header integrado al fondo difuminado — sin cuadro negro.
                    // Antes usaba safeAreaInset con fondo del sistema que pintaba
                    // un rectángulo negro/opaco sobre el blur. Ahora es la primera
                    // fila del VStack, completamente transparente sobre el mismo
                    // backgroundView difuminado.
                    HStack(spacing: 0) {
                        Button {
                            dismiss()
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
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(playIconColor.opacity(0.9))
                            .shadow(color: .black.opacity(0.15), radius: 4, y: 1)

                        Spacer()
                        Color.clear.frame(width: 44, height: 44)
                    }
                    .padding(.horizontal, 8)

                    Spacer(minLength: isCompactScreen ? 4 : 10)

                    artworkView
                        // ✅ MEJORADO: la portada solo anima al CAMBIAR de canción,
                        // no al pausar/resumir. Antes había una animación rara de
                        // escala (1.02 → 1.0) que se veía artificial al tocar play/pause.
                        .animation(.easeInOut(duration: 0.2), value: audioEngine.currentSong?.id)

                    Spacer(minLength: isCompactScreen ? 10 : 16)

                    if showVisualizer {
                        // ✅ MEJORADO: Selector de estilo de visualizador
                        switch visualizerStyle {
                        case 1:
                            // Elegante: ondas fluidas con gradientes
                            ElegantAudioVisualizer(audioEngine: audioEngine, tintColor: extractedColor)
                                .frame(height: isCompactScreen ? 50 : 70)
                                .padding(.horizontal, 0)
                                .drawingGroup()
                        case 2:
                            // Moderno: barras con reflejos y sombras
                            ModernBarVisualizer(audioEngine: audioEngine, tintColor: extractedColor)
                                .frame(height: isCompactScreen ? 40 : 50)
                                .padding(.horizontal, 20)
                        default:
                            // Clásico: barras simples originales
                            AudioVisualizer(audioEngine: audioEngine, tintColor: extractedColor)
                                .frame(height: isCompactScreen ? 32 : 48)
                                .padding(.horizontal, 36)
                        }
                    }

                    Spacer(minLength: isCompactScreen ? 8 : 14)

                    songInfoView
                        .animation(.easeInOut(duration: 0.15), value: audioEngine.currentSong?.id)

                    Spacer(minLength: isCompactScreen ? 8 : 14)

                    ProgressScrubView(
                        audioEngine: audioEngine,
                        clock: clock,
                        extractedColor: extractedColor,
                        extractedUIColor: extractedUIColor,
                        playIconColor: playIconColor,
                        isCompactScreen: isCompactScreen
                    )

                    Spacer(minLength: isCompactScreen ? 10 : 18)

                    controlsView

                    Spacer(minLength: isCompactScreen ? 8 : 14)

                    featureButtonsView

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
                .fixedSize(horizontal: false, vertical: true)
            }
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { availableSize = geometry.size }
                        .onChange(of: geometry.size) { availableSize = $0 }
                }
            }
            .onAppear {
                extractColorFromArtwork()
                AppLog.info(.interface, "NowPlaying abierto: '\(audioEngine.currentSong?.displayName ?? "—")'")
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
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
                extractColorFromArtwork()
                // ✅ Propagar el color de acento a ThemeManager para que PlayerBar
                // y todas las vistas que lo observen se actualicen al instante
                ThemeManager.shared.updateArtworkAccent(from: audioEngine.currentSong)
            }
            .onChange(of: theme.accentFromArtwork) { value in
                // ✅ FIX: se re-extrae en AMBOS sentidos. Antes, al DESACTIVAR
                // el acento desde la carátula, `extractedUIColor` se quedaba con
                // el color de la portada anterior → mezcla de colores en la
                // vista (barra con el acento real e iconos/tiempos con el viejo).
                if value, let song = audioEngine.currentSong {
                    ThemeManager.shared.updateArtworkAccent(from: song)
                }
                extractColorFromArtwork()
            }
            .onChange(of: theme.artworkAccentUIColor) { _ in
                // El color dominante puede resolverse de forma asíncrona (o
                // llegar desde otra vista): al cambiar, se vuelve a aplicar para
                // que barra, iconos y tiempos usen siempre el mismo color.
                extractColorFromArtwork()
            }
            // ✅ NUEVO: destinos del menú de 3 puntos
            .sheet(isPresented: $showArtistDetail) {
                if let artist = currentArtist {
                    NavigationStack {
                        ArtistDetailView(artist: artist, audioEngine: audioEngine)
                    }
                }
            }
            .sheet(isPresented: $showAlbumDetail) {
                if let album = currentAlbum {
                    NavigationStack {
                        AlbumDetailView(album: album, audioEngine: audioEngine)
                    }
                }
            }
            .presentationDetents([.large])
            // ✅ Mezcla el header con el fondo inmersivo: oculta cualquier banda/corte del sistema
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
            .sheet(isPresented: $showLyrics) {
                LyricsView(song: audioEngine.currentSong, audioEngine: audioEngine, clock: audioEngine.clock)
            }
            .sheet(isPresented: $showEqualizer) {
                EqualizerView(audioEngine: audioEngine)
            }
            .sheet(isPresented: $showQueue) {
                QueueView(audioEngine: audioEngine)
            }
            .overlay {
                if showQualityDetail {
                    qualityCardModal
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
            .animation(.easeOut(duration: 0.15), value: showQualityDetail)
    }

    // MARK: - Background (respeta "Reducir transparencia")
    private var backgroundView: some View {
        Group {
            if let artwork = audioEngine.currentSong?.artwork, !reduceTransparency {
                GeometryReader { geometry in
                    ZStack {
                        // ✅ FIX barra negra: scaledToFill + clipped para cubrir
                        // TODA la pantalla (scaledToFit dejaba franjas en pantallas
                        // altas/anchas por encima y debajo de la imagen cuadrada).
                        // ✅ OPTIMIZACIÓN A11: blur adaptativo según hardware
                        let hw = HardwareCapabilities.shared
                        let blurRadius = hw.useHighQualityBlur ? 25.0 : 15.0
                        
                        Image(uiImage: artwork)
                            .resizable()
                            .interpolation(.medium)
                            .scaledToFill()
                            .frame(width: geometry.size.width + 60, height: geometry.size.height + 60)
                            .clipped()
                            .blur(radius: blurRadius)
                            .opacity(0.45)

                        extractedColor.opacity(0.12)
                    }
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                // ✅ OPTIMIZACIÓN A11: drawingGroup agresivo solo en A11
                .drawingGroup()
            } else {
                LinearGradient(
                    colors: [
                        Color(UIColor.systemBackground),
                        Color(UIColor.secondarySystemBackground)
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
                        .fill(
                            LinearGradient(
                                colors: [extractedColor.opacity(0.3), extractedColor.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: artworkSize, height: artworkSize)

                    Image(systemName: "music.note")
                        .font(.system(size: artworkSize * 0.15, weight: .light))
                        .foregroundStyle(extractedColor.opacity(0.8))
                }
                .shadow(color: .black.opacity(0.15), radius: 15, x: 0, y: 8)
                .shadow(color: extractedColor.opacity(0.15), radius: 8, x: 0, y: 4)
            }
        }
    }

    // MARK: - Song Info (mejorado con mejor tipografía y espaciado)
    private var songInfoView: some View {
        VStack(spacing: 6) {
            // ✅ Título con gradiente sutil del color extraído (mejor tipografía)
            // ✅ 60fps: shadow removido del texto con gradiente (forzaba blur
            // offscreen por frame; el gradiente ya da suficiente profundidad).
            Text(audioEngine.currentSong?.displayName ?? Localization.localized("quality.noSong"))
                .font(.system(size: isCompactScreen ? 20 : 24, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(
                    LinearGradient(
                        colors: [playIconColor, playIconColor.opacity(0.85)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .lineLimit(2)

            Text(audioEngine.currentSong?.displaySubtitle ?? "—")
                .font(.system(size: isCompactScreen ? 14 : 16, weight: .medium))
                .foregroundStyle(AppTheme.contrastingText(on: extractedUIColor).opacity(0.75))
                .lineLimit(1)
                .padding(.horizontal, 20)

            if let song = audioEngine.currentSong, !song.audioQualityDescription.isEmpty {
                Button {
                    Haptics.light()
                    showQualityDetail = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 10, weight: .semibold))

                        Text(song.audioQualityDescription)
                            .font(.system(size: 10, weight: .medium).monospacedDigit())

                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(extractedColor.opacity(0.6))
                    }
                    .foregroundStyle(playIconColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background {
                        Capsule().fill(extractedColor.opacity(0.2))
                    }
                    .overlay {
                        Capsule().strokeBorder(playIconColor.opacity(0.15), lineWidth: 0.5)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Localization.localized("quality.viewDetails"))
            }

            // ✅ Me gusta movido aquí: debajo de las ondas, junto a la info de
            // calidad de la canción (antes estaba en la fila de transporte).
            Button {
                Haptics.light()
                if let song = audioEngine.currentSong {
                    fileAccessService.toggleLike(song)
                }
            } label: {
                Image(systemName: isCurrentLiked ? "heart.fill" : "heart")
                    .font(.system(size: 18, weight: isCurrentLiked ? .bold : .semibold))
                    .foregroundStyle(isCurrentLiked ? Color.red : AppTheme.contrastingText(on: extractedUIColor).opacity(0.7))
                    .frame(width: 44, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isCurrentLiked)
            .accessibilityLabel(Localization.localized("actions.like"))
        }
        .padding(.horizontal, 6)
    }

    // MARK: - Progress View (scrub fluido a 60fps)
    // ⚠️ ELIMINADO de NowPlayingView: la barra vive en ProgressScrubView
    // (al final de este archivo) para que el reloj (0.4s) NO re-renderice
    // esta vista y los botones de shuffle/repeat respondan al primer toque.

    // MARK: - Controls
    private var controlsView: some View {
        HStack(spacing: isCompactScreen ? 8 : 14) {
            // Shuffle
            Button {
                Haptics.light()
                audioEngine.toggleShuffle()
            } label: {
                ZStack {
                    Capsule()
                        .fill(audioEngine.isShuffleEnabled ? extractedColor.opacity(0.45) : Color.clear)
                        .frame(width: isCompactScreen ? 42 : 46, height: isCompactScreen ? 30 : 36)

                    Image(systemName: "shuffle")
                        .font(.system(size: isCompactScreen ? 15 : 17, weight: audioEngine.isShuffleEnabled ? .bold : .semibold))
                        .foregroundStyle(audioEngine.isShuffleEnabled ? playIconColor : AppTheme.contrastingText(on: extractedUIColor).opacity(0.7))
                }
                .frame(width: isCompactScreen ? 56 : 64, height: isCompactScreen ? 56 : 64)
                .contentShape(Rectangle())
            }
            // ✅ Feedback de PRENSIÓN visible (antes .plain: sin reacción al tocar
            // y el cambio de estado era casi invisible sobre la portada). El
            // .animation(value:) colorea el icono AL INSTANTE al conmutar.
            .buttonStyle(PressableButtonStyle(scale: 0.86))
            .animation(.easeInOut(duration: 0.15), value: audioEngine.isShuffleEnabled)

            // Previous
            Button {
                Haptics.light()
                audioEngine.playPrevious()
            } label: {
                ZStack {
                    Circle().fill(controlBackground).frame(width: isCompactScreen ? 44 : 50, height: isCompactScreen ? 44 : 50)
                    Image(systemName: "backward.fill")
                        .font(.system(size: isCompactScreen ? 16 : 18, weight: .semibold))
                        .foregroundStyle(playIconColor)
                }
                .frame(width: isCompactScreen ? 56 : 64, height: isCompactScreen ? 56 : 64)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Play/Pause (icono con contraste)
            Button {
                Haptics.medium()
                if audioEngine.isPlaying {
                    audioEngine.pause()
                } else {
                    audioEngine.resume()
                }
            } label: {
                ZStack {
                    Circle().fill(extractedColor).frame(width: isCompactScreen ? 62 : 72, height: isCompactScreen ? 62 : 72)
                    // ✅ El icono cambia instantáneamente (sin .id() ni transición
                    // de reemplazo — recreaba la vista entera y se sentía lento en
                    // A11); solo un breve fade de 0.1s suaviza el cambio visual.
                    Image(systemName: audioEngine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: isCompactScreen ? 22 : 26, weight: .bold))
                        .foregroundStyle(playIconColor)
                }
                .shadow(color: extractedColor.opacity(0.35), radius: 10, x: 0, y: 4)
                .animation(.easeOut(duration: 0.1), value: audioEngine.isPlaying)
                .frame(width: isCompactScreen ? 76 : 88, height: isCompactScreen ? 76 : 88)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Next
            Button {
                Haptics.light()
                audioEngine.playNext()
            } label: {
                ZStack {
                    Circle().fill(controlBackground).frame(width: isCompactScreen ? 44 : 50, height: isCompactScreen ? 44 : 50)
                    Image(systemName: "forward.fill")
                        .font(.system(size: isCompactScreen ? 16 : 18, weight: .semibold))
                        .foregroundStyle(playIconColor)
                }
                .frame(width: isCompactScreen ? 56 : 64, height: isCompactScreen ? 56 : 64)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Repeat
            Button {
                Haptics.light()
                audioEngine.cycleRepeatMode()
            } label: {
                ZStack {
                    Capsule()
                        .fill(audioEngine.repeatMode != .off ? extractedColor.opacity(0.45) : Color.clear)
                        .frame(width: isCompactScreen ? 42 : 46, height: isCompactScreen ? 30 : 36)

                    Image(systemName: repeatIcon)
                        .font(.system(size: isCompactScreen ? 15 : 17, weight: audioEngine.repeatMode != .off ? .bold : .semibold))
                        .foregroundStyle(audioEngine.repeatMode != .off ? playIconColor : AppTheme.contrastingText(on: extractedUIColor).opacity(0.7))
                }
                .frame(width: isCompactScreen ? 56 : 64, height: isCompactScreen ? 56 : 64)
                .contentShape(Rectangle())
            }
            // ✅ Mismo tratamiento que shuffle: feedback de presión visible y
            // animación inmediata del icono (repeat → repeat.1 → off) al tocar.
            .buttonStyle(PressableButtonStyle(scale: 0.86))
            .animation(.easeInOut(duration: 0.2), value: audioEngine.repeatMode)
        }
        .frame(maxWidth: .infinity)
        .fixedSize()
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
                        .fill(audioEngine.isEQEnabled ? extractedColor.opacity(0.25) : Color.clear)
                        .frame(width: capsuleWidth, height: capsuleHeight)

                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: iconSize, weight: audioEngine.isEQEnabled ? .bold : .semibold))
                        .foregroundStyle(audioEngine.isEQEnabled ? playIconColor : AppTheme.contrastingText(on: extractedUIColor).opacity(0.7))
                }
                .frame(width: buttonSize, height: buttonSize)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Localization.localized("quality.accessibility.equalizer"))

            // Letras
            Button {
                Haptics.light()
                showLyrics = true
            } label: {
                ZStack {
                    Capsule()
                        .fill(audioEngine.currentSong?.lyrics.isEmpty == false ? extractedColor.opacity(0.25) : Color.clear)
                        .frame(width: capsuleWidth, height: capsuleHeight)

                    Image(systemName: audioEngine.currentSong?.lyrics.isEmpty == false ? "quote.bubble.fill" : "quote.bubble")
                        .font(.system(size: iconSize, weight: audioEngine.currentSong?.lyrics.isEmpty == false ? .bold : .semibold))
                        .foregroundStyle(audioEngine.currentSong?.lyrics.isEmpty == false ? playIconColor : AppTheme.contrastingText(on: extractedUIColor).opacity(0.7))
                }
                .frame(width: buttonSize, height: buttonSize)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Localization.localized("quality.accessibility.lyrics"))

            // Cola
            Button {
                Haptics.light()
                showQueue = true
            } label: {
                ZStack {
                    Capsule()
                        .fill(audioEngine.nextUpQueue.isEmpty ? Color.clear : extractedColor.opacity(0.25))
                        .frame(width: capsuleWidth, height: capsuleHeight)

                    Image(systemName: "list.bullet")
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundStyle(audioEngine.nextUpQueue.isEmpty ? AppTheme.contrastingText(on: extractedUIColor).opacity(0.7) : playIconColor)
                }
                .frame(width: buttonSize, height: buttonSize)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Localization.localized("quality.accessibility.queue"))

            // ✅ AirPlay (FIX): en vez de abrir un sheet con un AVRoutePickerView
            // gigante que fallaba, el picker NATIVO de iOS va superpuesto e
            // invisible sobre el botón: al tocar, iOS muestra directamente su
            // menú emergente de AirPlay (comportamiento estándar del sistema).
            ZStack {
                // Botón visual (icono + resaltado si la salida es AirPlay)
                Capsule()
                    .fill(audioEngine.outputPortType == AVAudioSession.Port.airPlay.rawValue ? extractedColor.opacity(0.25) : Color.clear)
                    .frame(width: capsuleWidth, height: capsuleHeight)

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
                    withAnimation(.easeOut(duration: 0.22)) {
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
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Spacer()

                    Button {
                        Haptics.light()
                        withAnimation(.easeOut(duration: 0.22)) {
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

                AudioQualityDetailView(audioEngine: audioEngine, embeddedInCard: true)
            }
            // ✅ Panel EXPANDIDO: mejor legibilidad y espacio para todos los detalles
            // Aumentado de 480x440 a 520x500 para mejor experiencia visual.
            .frame(maxWidth: 520, maxHeight: 500)
            .background {
                // Cristal ultraThinMaterial: el arte borroso del fondo se ve
                // a través del panel, con borde luminoso y profundidad.
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(reduceTransparency
                          ? AnyShapeStyle(Color(UIColor.systemBackground))
                          : AnyShapeStyle(.ultraThinMaterial))
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
        .animation(.easeOut(duration: 0.22), value: showQualityDetail)
    }

    // MARK: - Helpers
    private var controlBackground: AnyShapeStyle {
        reduceTransparency
            ? AnyShapeStyle(Color(UIColor.secondarySystemBackground))
            : AnyShapeStyle(.ultraThinMaterial)
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

private func extractColorFromArtwork() {
        // UNIFICADO: un solo ajuste maestro (ThemeManager.accentFromArtwork)
        // controla el acento de portada en TODOS los entornos.
        // ✅ FIX: SIEMPRE se actualizan los DOS colores (antes solo se reseteaba
        // `extractedColor`, así que `extractedUIColor` conservaba el color de la
        // portada anterior → iconos y textos con un color y la barra con otro).
        guard ThemeManager.shared.accentFromArtwork else {
            extractedColor = AppTheme.accent
            extractedUIColor = AppTheme.accentUIColor
            return
        }

        guard let artwork = audioEngine.currentSong?.artwork, let songID = audioEngine.currentSong?.id else {
            extractedColor = AppTheme.accent
            extractedUIColor = AppTheme.accentUIColor
            return
        }

        // Cache compartida: mismo color que AlbumDetail/ArtistDetail.
        if let cached = AppTheme.cachedDominantColor(from: artwork, key: songID.uuidString) {
            extractedColor = AppTheme.readableColor(from: cached)
            extractedUIColor = cached
            return
        }
        // Sin color calculable → volver al acento real (y no dejar el anterior).
        extractedColor = AppTheme.accent
        extractedUIColor = AppTheme.accentUIColor
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
    let extractedUIColor: UIColor
    let playIconColor: Color
    let isCompactScreen: Bool

    @State private var isScrubbing = false
    @State private var scrubPreviewTime: TimeInterval = 0
    @State private var progressBarWidth: CGFloat = 0

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
            // ✅ FIX: .frame(maxWidth: .infinity) para que el GeometryReader
            // se expanda al ancho completo disponible. El gesture usa
            // progressBarWidth (actualizado por onAppear/onChange del
            // GeometryReader) para calcular el porcentaje de scrub.
            GeometryReader { geometry in
                // ✅ Feedback táctil: la barra engrosa al hacer scrub
                // (animación de frame → GPU, sin costo de calidad)
                let barHeight: CGFloat = isScrubbing ? 10 : 4
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: barHeight)

                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [extractedColor.opacity(0.85), extractedColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * progress, height: barHeight)
                        // ✅ Glow más notorio mientras se arrastra
                        .shadow(color: isScrubbing ? extractedColor.opacity(0.6) : extractedColor.opacity(0.3), radius: isScrubbing ? 8 : 4, x: 0, y: 0)
                    // ✅ IndicADOR CIRCULAR: posicionado con .position en vez de
                        // .offset (el offset causaba el "punto blanco" fuera de lugar).
                        // Solo visible cuando hay progreso intermedio.
                        .overlay(alignment: .leading) {
                            Circle()
                                .fill(.white)
                                .frame(width: isScrubbing ? 14 : 12, height: isScrubbing ? 14 : 12)
                                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 1)
                                .position(
                                    x: geometry.size.width * progress,
                                    y: barHeight / 2
                                )
                                .opacity(progress > 0.01 && progress < 0.99 ? 1 : 0)
                        }
                }
                .onAppear {
                    progressBarWidth = geometry.size.width
                }
                .onChange(of: geometry.size.width) { newWidth in
                    progressBarWidth = newWidth
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 10)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
            // ✅ FIX animación rara: antes había UNA animación spring sobre
            // todo el subárbol disparada por isScrubbing, lo que hacía que el
            // indicador circular "botara" cada vez que el reloj (0.3s) movía
            // el progreso. Ahora: easing lineal suave para el avance normal
            // del reloj + spring SOLO para el cambio de tamaño al arrastrar.
            .animation(.linear(duration: 0.25), value: progress)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isScrubbing)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard progressBarWidth.isFinite, progressBarWidth > 0,
                              value.location.x.isFinite, audioEngine.duration.isFinite,
                              audioEngine.duration > 0 else { return }
                        isScrubbing = true
                        let percentage = max(0, min(1, value.location.x / progressBarWidth))
                        scrubPreviewTime = audioEngine.duration * percentage
                    }
                    .onEnded { value in
                        defer { isScrubbing = false }
                        guard progressBarWidth.isFinite, progressBarWidth > 0,
                              value.location.x.isFinite, audioEngine.duration.isFinite,
                              audioEngine.duration > 0 else { return }
                        let percentage = max(0, min(1, value.location.x / progressBarWidth))
                        let newTime = audioEngine.duration * percentage
                        isScrubbing = false
                        audioEngine.seek(to: newTime)
                    }
            )

            HStack {
                Text(scrubPreviewText)
                    .font(.system(size: isCompactScreen ? 12 : 13, weight: isScrubbing ? .bold : .medium))
                    .foregroundStyle(isScrubbing ? playIconColor : AppTheme.contrastingText(on: extractedUIColor).opacity(0.75))
                    .monospacedDigit()
                    .animation(.easeInOut(duration: 0.15), value: isScrubbing)

                Spacer()

                Text(formatTime(audioEngine.duration))
                    .font(.system(size: isCompactScreen ? 12 : 13, weight: .medium))
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
