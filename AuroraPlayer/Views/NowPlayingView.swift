import SwiftUI
import AVFoundation
import AVKit

struct NowPlayingView: View {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var fileAccessService: FileAccessService
    @ObservedObject var clock: PlaybackClock
    // ✅ Observar el idioma: al cambiar, esta vista se re-renderiza al instante
    @ObservedObject private var localization = Localization.shared
    @Environment(\.dismiss) private var dismiss

    // Configuraciones de personalización
    @AppStorage("com.aurora.showVisualizer") private var showVisualizer = true
    @AppStorage("com.aurora.keepScreenOn") private var keepScreenOn = false
    @AppStorage("com.aurora.dynamicColor") private var dynamicColor = true
    @AppStorage("com.aurora.artworkCorner") private var artworkCorner: Double = 22
    @AppStorage("com.aurora.reduceTransparency") private var reduceTransparency = false
    // ✅ Ajuste "Mostrar letras" (antes no se aplicaba)
    @AppStorage("com.aurora.showLyricsByDefault") private var showLyricsByDefault = false

    @State private var showLyrics = false
    @State private var showEqualizer = false
    @State private var showQueue = false
    @State private var showQualityDetail = false
    // ✅ NUEVO: menú de 3 puntos → ver artista / álbum / letras / cola / compartir
    @State private var showArtistDetail = false
    @State private var showAlbumDetail = false
    @State private var artworkScale: CGFloat = 1.0
    @State private var progressBarWidth: CGFloat = 0
    @State private var extractedColor: Color = AppTheme.accent
    // ✅ Guardamos el UIColor dominante crudo para calcular contraste
    // ✅ FIX: usar accentUIColor en vez de systemPurple hardcodeado
    @State private var extractedUIColor: UIColor = AppTheme.accentUIColor

    // ✅ Caché de color dominante por canción: evita recalcular el histograma
    // HSB al reabrir NowPlaying o re-entrar a la misma pista (60fps sin hitch)


    // ✅ Scrub optimizado: preview local a 60fps, seek real solo al soltar
    @State private var isScrubbing = false
    @State private var scrubPreviewTime: TimeInterval = 0

    // MARK: - Adaptive sizing for iOS 16 & iPhone 8 Plus
    private var isCompactScreen: Bool {
        UIScreen.main.bounds.height < 800
    }

    private var artworkSize: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        // ✅ MEJORADO: Portada más grande y mejor centrada
        let maxByWidth = screenWidth - 40
        let maxByHeight = screenHeight * (isCompactScreen ? 0.32 : 0.42)
        return min(340, maxByWidth, maxByHeight)
    }

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

    // ✅ Contraste: si el color dominante es claro → texto oscuro; si es oscuro → texto blanco
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
        NavigationStack {
            ZStack {
                backgroundView

                // ✅ DISEÑO MEJORADO: distribución equilibrada con Spacers
                // flexibles (la proporción se adapta a cualquier pantalla,
                // iPhone 8 Plus incluido) en lugar de espaciados fijos.
                VStack(spacing: 0) {
                    Spacer(minLength: isCompactScreen ? 4 : 10)

                    artworkView
                        // ✅ MEJORADO: la portada solo anima al CAMBIAR de canción,
                        // no al pausar/resumir. Antes había una animación rara de
                        // escala (1.02 → 1.0) que se veía artificial al tocar play/pause.
                        .animation(.easeInOut(duration: 0.3), value: audioEngine.currentSong?.id)

                    Spacer(minLength: isCompactScreen ? 10 : 16)

                    if showVisualizer {
                        // ✅ MEJORADO: AudioVisualizer ya rasteriza internamente
                        // con .drawingGroup() y maneja la atenuación al pausar.
                        // Nada de animaciones raras de escala aquí.
                        AudioVisualizer(audioEngine: audioEngine, tintColor: extractedColor)
                            .frame(height: isCompactScreen ? 32 : 48)
                            .padding(.horizontal, 36)
                    }

                    Spacer(minLength: isCompactScreen ? 8 : 14)

                    songInfoView
                        .animation(.easeInOut(duration: 0.25), value: audioEngine.currentSong?.id)

                    Spacer(minLength: isCompactScreen ? 8 : 14)

                    progressView

                    Spacer(minLength: isCompactScreen ? 10 : 18)

                    controlsView

                    Spacer(minLength: isCompactScreen ? 8 : 14)

                    featureButtonsView

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
                .fixedSize(horizontal: false, vertical: true)
            }
            // ✅ Header personalizado: la navigation bar del sistema pintaba un
            // recuadro gris/negro sobre el fondo inmersivo. safeAreaInset dibuja
            // el chevron + título SIN ningún fondo y empuja el contenido.
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 0) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .foregroundStyle(extractedColor)
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Localization.localized("nowPlaying.close"))

                    Spacer()

                    Text(Localization.localized("nowPlaying.title"))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [extractedColor, extractedColor.opacity(0.75)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )

                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 8)
            }
            .onAppear {
                extractColorFromArtwork()
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
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
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showQualityDetail)
        }
    }

    // MARK: - Background (respeta "Reducir transparencia")
    private var backgroundView: some View {
        Group {
            if let artwork = audioEngine.currentSong?.artwork, !reduceTransparency {
                GeometryReader { geometry in
                    ZStack {
                        Image(uiImage: artwork)
                            .resizable()
                            .interpolation(.medium)
                            .scaledToFit()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .blur(radius: 25)
                            .opacity(0.45)

                        extractedColor.opacity(0.12)
                    }
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .drawingGroup(opaque: false)
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
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isCurrentLiked)
            .accessibilityLabel(Localization.localized("actions.like"))
        }
        .padding(.horizontal, 6)
    }

    // MARK: - Progress View (scrub fluido a 60fps)
    private var progressView: some View {
        VStack(spacing: 8) {
            // ✅ FIX: .frame(maxWidth: .infinity) para que el GeometryReader
            // se expanda al ancho completo disponible. El gesture usa
            // progressBarWidth (actualizado por onAppear/onChange del
            // GeometryReader) para calcular el porcentaje de scrub.
            GeometryReader { geometry in
                // ✅ Feedback táctil: la barra engrosa al hacer scrub
                // (animación de frame → GPU, sin costo de calidad)
                let barHeight: CGFloat = isScrubbing ? 10 : 6
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
                                .frame(width: isScrubbing ? 14 : 10, height: isScrubbing ? 14 : 10)
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
                        isScrubbing = true
                        let percentage = max(0, min(1, value.location.x / progressBarWidth))
                        scrubPreviewTime = audioEngine.duration * percentage
                    }
                    .onEnded { value in
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
                        .fill(audioEngine.isShuffleEnabled ? extractedColor.opacity(0.25) : Color.clear)
                        .frame(width: isCompactScreen ? 42 : 46, height: isCompactScreen ? 30 : 36)

                    Image(systemName: "shuffle")
                        .font(.system(size: isCompactScreen ? 15 : 17, weight: audioEngine.isShuffleEnabled ? .bold : .semibold))
                        .foregroundStyle(audioEngine.isShuffleEnabled ? playIconColor : AppTheme.contrastingText(on: extractedUIColor).opacity(0.7))
                }
                .frame(width: isCompactScreen ? 56 : 64, height: isCompactScreen ? 56 : 64)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

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
                    // ✅ El icono cambia con crossfade de opacidad al pausar/resumir
                    // (sin animación de scale rara; compatible iOS 16)
                    Image(systemName: audioEngine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: isCompactScreen ? 22 : 26, weight: .bold))
                        .foregroundStyle(playIconColor)
                        .transition(.opacity)
                        .id(audioEngine.isPlaying ? "playing" : "paused")
                }
                .shadow(color: extractedColor.opacity(0.35), radius: 10, x: 0, y: 4)
                .animation(.easeInOut(duration: 0.2), value: audioEngine.isPlaying)
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
                        .fill(audioEngine.repeatMode != .off ? extractedColor.opacity(0.25) : Color.clear)
                        .frame(width: isCompactScreen ? 42 : 46, height: isCompactScreen ? 30 : 36)

                    Image(systemName: repeatIcon)
                        .font(.system(size: isCompactScreen ? 15 : 17, weight: audioEngine.repeatMode != .off ? .bold : .semibold))
                        .foregroundStyle(audioEngine.repeatMode != .off ? playIconColor : AppTheme.contrastingText(on: extractedUIColor).opacity(0.7))
                }
                .frame(width: isCompactScreen ? 56 : 64, height: isCompactScreen ? 56 : 64)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
            // ✅ Backdrop con blur (más premium que solo opacidad)
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .background(.ultraThinMaterial)
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
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
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
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
            .frame(maxWidth: 480, maxHeight: 640)
            .background {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(Color(UIColor.systemBackground))
                    // ✅ Sombra doble para mayor profundidad
                    .shadow(color: .black.opacity(0.35), radius: 30, x: 0, y: 15)
                    .shadow(color: AppTheme.accent.opacity(0.08), radius: 20, x: 0, y: 5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .padding(.horizontal, 24)
            // ✅ ANIMACIÓN DE ENTRADA/SALIDA: scale + opacity + blur
            .scaleEffect(showQualityDetail ? 1.0 : 0.88)
            .opacity(showQualityDetail ? 1.0 : 0)
            .blur(radius: showQualityDetail ? 0 : 8)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showQualityDetail)
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

    private func formatTime(_ time: TimeInterval) -> String {
        guard !time.isNaN && time.isFinite else { return "0:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func extractColorFromArtwork() {
        // ✅ FIX: respetar el ajuste "Color dinámico"
        guard dynamicColor else {
            extractedColor = AppTheme.accent
            return
        }

        guard let artwork = audioEngine.currentSong?.artwork else {
            extractedColor = AppTheme.accent
            return
        }

        // ✅ Color dominante VIVO vía histograma HSB, con caché por canción
        let cacheKey = (audioEngine.currentSong?.id.uuidString ?? "none") as NSString
        if let cached = AppTheme.artworkColorCache.object(forKey: cacheKey) {
            extractedColor = AppTheme.readableColor(from: cached)
            extractedUIColor = cached
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let dominant = AppTheme.dominantColor(from: artwork) ?? AppTheme.accentUIColor
            AppTheme.artworkColorCache.setObject(dominant, forKey: cacheKey)
            DispatchQueue.main.async {
                self.extractedColor = AppTheme.readableColor(from: dominant)
                self.extractedUIColor = dominant
            }
        }
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