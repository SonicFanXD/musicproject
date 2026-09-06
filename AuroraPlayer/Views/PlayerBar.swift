import SwiftUI

struct PlayerBar: View {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var fileAccessService: FileAccessService
    // ✅ Reloj aislado: este view re-renderiza cada tick de tiempo sin
    // arrastrar al ContentView/la biblioteca (60fps estables al reproducir)
    @ObservedObject var clock: PlaybackClock
    // ✅ Observar el idioma: al cambiar, esta vista se re-renderiza al instante
    @ObservedObject private var localization = Localization.shared
    @State private var showingNowPlaying = false

    // ✅ Scrub optimizado: preview local a 60fps, seek real solo al soltar
    @State private var isScrubbing = false
    @State private var scrubPreviewProgress: Double = 0
    // ✅ Inicializar scrub con progreso actual para evitar salto a 0
    @State private var scrubStartProgress: Double = 0

    // Animaciones optimizadas (una sola @State, triggers discretos = 60fps)
    @State private var playButtonScale: CGFloat = 1.0
    // ✅ Opacidad del visualizador para transición suave (no crear/destruir)
    @State private var visualizerOpacity: Double = 0

    // ✅ Esquinas del artwork sincronizadas con el ajuste de Apariencia
    @AppStorage("com.aurora.artworkCorner") private var artworkCorner: Double = 22
    @AppStorage("com.aurora.compactPlayerBar") private var compactPlayerBar = false
    // ✅ Ajuste "Visualizador en barra" (antes no se aplicaba)
    @AppStorage("com.aurora.showVisualizerInBar") private var showVisualizerInBar = true

    private var progress: Double {
        if isScrubbing { return scrubPreviewProgress }
        guard audioEngine.duration > 0 else { return 0 }
        return min(max(clock.time / audioEngine.duration, 0), 1)
    }

    /// Progreso actual real (para inicializar scrub sin salto)
    private var currentProgress: Double {
        guard audioEngine.duration > 0 else { return 0 }
        return min(max(clock.time / audioEngine.duration, 0), 1)
    }

    var body: some View {
        Group {
            if let song = audioEngine.currentSong {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        // ✅ Artwork con mejor calidad y animación
                        artwork(for: song)

                        // ✅ Song info con tap target expandido
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.title)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                Text(song.artist.isEmpty ? Localization.localized("details.unknownArtist") : song.artist)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            // ✅ Mini visualizador con opacidad animada (no se crea/destruye)
                            // Evita saltos visuales y mantiene estado de animación
                            if showVisualizerInBar {
                                AudioVisualizer(audioEngine: audioEngine)
                                    .frame(width: 18, height: 14)
                                    .opacity(visualizerOpacity)
                                    .animation(.easeInOut(duration: 0.3), value: visualizerOpacity)
                                    .onAppear {
                                        visualizerOpacity = audioEngine.isPlaying ? 1 : 0
                                    }
                                    .onChange(of: audioEngine.isPlaying) { _, playing in
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            visualizerOpacity = playing ? 1 : 0
                                        }
                                    }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .padding(.vertical, 6)
                        .onTapGesture {
                            openNowPlaying()
                        }

                        // ✅ Botón de me gusta
                        Button {
                            Haptics.light()
                            fileAccessService.toggleLike(song)
                        } label: {
                            Image(systemName: fileAccessService.isLiked(song) ? "heart.fill" : "heart")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(fileAccessService.isLiked(song) ? .red : .secondary)
                                .frame(width: 36, height: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        // ✅ Controles rediseñados con mejor feedback visual
                        HStack(spacing: 2) {
                            // Previous
                            Button {
                                Haptics.light()
                                audioEngine.playPrevious()
                            } label: {
                                Image(systemName: "backward.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .frame(width: 40, height: 40)
                                    .contentShape(Circle())
                                    .scaleEffect(playButtonScale)
                            }
                            .buttonStyle(PressableButtonStyle(scale: 0.85))
                            .accessibilityLabel(Localization.localized("accessibility.previousSong"))

                            // ✅ Play/Pause con animación de escala y halo
                            Button {
                                animatePlayButton()
                                Haptics.light()
                                if audioEngine.isPlaying {
                                    audioEngine.pause()
                                } else {
                                    audioEngine.resume()
                                }
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(AppTheme.accent)

                                    // ✅ Halo animado cuando reproduce
                                    Circle()
                                        .stroke(AppTheme.accent.opacity(0.35), lineWidth: 2)
                                        .scaleEffect(audioEngine.isPlaying ? 1.12 : 1.0)
                                        .opacity(audioEngine.isPlaying ? 0.9 : 0)
                                        .animation(
                                            audioEngine.isPlaying
                                                ? .easeInOut(duration: 1.6).repeatForever(autoreverses: true)
                                                : .easeOut(duration: 0.2),
                                            value: audioEngine.isPlaying
                                        )
                                        .drawingGroup()

                                    Image(systemName: audioEngine.isPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                                .frame(width: compactPlayerBar ? 40 : 44, height: compactPlayerBar ? 40 : 44)
                                .shadow(color: AppTheme.accent.opacity(0.35), radius: 8, x: 0, y: 3)
                                .scaleEffect(playButtonScale)
                                .contentShape(Circle())
                            }
                            .buttonStyle(PressableButtonStyle(scale: 0.88))
                            .accessibilityLabel(Localization.localized("accessibility.playPause"))

                            // Next
                            Button {
                                Haptics.light()
                                audioEngine.playNext()
                            } label: {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .frame(width: 40, height: 40)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(PressableButtonStyle(scale: 0.85))
                            .accessibilityLabel(Localization.localized("accessibility.nextSong"))
                        }
                    }
                    .padding(.leading, 14)
                    .padding(.trailing, 10)
                    .padding(.top, compactPlayerBar ? 8 : 12)
                    .padding(.bottom, 4)

                    // ✅ Barra de progreso mejorada con preview de scrub
                    // ✅ FIX: .frame(maxWidth: .infinity) para que el GeometryReader
                    // se expanda al ancho completo disponible. Sin esto, el ancho
                    // podía colapsar y la barra quedaba desalineada/estrecha.
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.secondary.opacity(0.18))
                                .frame(height: compactPlayerBar ? 3 : 4)

                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [AppTheme.accent.opacity(0.75), AppTheme.accent],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(4, geometry.size.width * progress), height: compactPlayerBar ? 3 : 4)

                            // ✅ Indicador de posición al hacer scrub
                            if isScrubbing {
                                Circle()
                                    .fill(AppTheme.accent)
                                    .frame(width: 10, height: 10)
                                    .offset(x: geometry.size.width * scrubPreviewProgress - 5)
                                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                            }
                        }
                        .frame(height: compactPlayerBar ? 3 : 4)
                        // ✅ FIX: el área táctil era enorme (maxHeight infinity +
                        // padding 14) y robaba los toques del artwork/título,
                        // impidiendo abrir NowPlayingView tras reanudar la app.
                        // Ahora el gesto se limita a la barra (+6pt de margen)
                        // y un toque simple (sin arrastre) abre NowPlaying.
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            openNowPlaying()
                        }
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    guard audioEngine.duration > 0, geometry.size.width > 0 else { return }
                                    // ✅ Inicializar scrub con progreso actual (evita salto a 0)
                                    if !isScrubbing {
                                        startScrubbing()
                                    }
                                    // ✅ Preview local a 60fps (sin toques al engine durante el arrastre)
                                    scrubPreviewProgress = max(0, min(1, value.location.x / geometry.size.width))
                                }
                                .onEnded { value in
                                    guard audioEngine.duration > 0, geometry.size.width > 0 else { return }
                                    // ✅ Seek real UNA sola vez al soltar
                                    let percentage = max(0, min(1, value.location.x / geometry.size.width))
                                    scrubPreviewProgress = percentage
                                    endScrubbing()
                                }
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: (compactPlayerBar ? 3 : 4) + 12)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 8)
                }
                .background {
                    // ✅ Esquinas muy redondeadas (34pt) con material premium
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(.regularMaterial)
                        .shadow(color: .black.opacity(0.14), radius: 16, x: 0, y: 6)
                    // Borde sutil superior para profundidad
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                }
                .onAppear {
                    // ✅ Sincronizar estado visual inicial
                    visualizerOpacity = audioEngine.isPlaying ? 1 : 0
                }
                .sheet(isPresented: $showingNowPlaying) {
                    NowPlayingView(audioEngine: audioEngine, fileAccessService: fileAccessService, clock: audioEngine.clock)
                }
            }
        }
    }

    // MARK: - Animaciones optimizadas

    /// Animación de feedback del botón play (spring discreto, no repeatForever)
    private func animatePlayButton() {
        playButtonScale = 0.88
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            playButtonScale = 1.0
        }
    }

    /// Inicializar scrub con progreso actual para evitar salto a 0
    private func startScrubbing() {
        Haptics.selection()
        scrubStartProgress = currentProgress
        scrubPreviewProgress = currentProgress
        isScrubbing = true
    }

    /// Finalizar scrub con seek real
    private func endScrubbing() {
        Haptics.light()
        let targetTime = scrubPreviewProgress * audioEngine.duration
        isScrubbing = false
        audioEngine.seek(to: targetTime)
    }

    private func openNowPlaying() {
        Haptics.light()
        showingNowPlaying = true
    }

    // MARK: - Artwork (calidad alta, animación sutil = 60fps)
    @ViewBuilder
    private func artwork(for song: Song) -> some View {
        if let art = song.artwork {
            Image(uiImage: art)
                .resizable()
                .interpolation(.high) // ✅ Mejor calidad de interpolación
                .scaledToFill()
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: CGFloat(artworkCorner * (14.0 / 22.0)), style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                .overlay(
                    // ✅ Indicador de reproducción con animación suave
                    RoundedRectangle(cornerRadius: CGFloat(artworkCorner * (14.0 / 22.0)), style: .continuous)
                        .stroke(AppTheme.accent.opacity(audioEngine.isPlaying ? 0.45 : 0.0), lineWidth: 1.5)
                        .animation(.easeInOut(duration: 0.35), value: audioEngine.isPlaying)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    openNowPlaying()
                }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: CGFloat(artworkCorner * (14.0 / 22.0)), style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.accent.opacity(0.28), AppTheme.accent.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 46, height: 46)

                Image(systemName: audioEngine.isPlaying ? "waveform" : "music.note")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
                    .animation(.easeInOut(duration: 0.3), value: audioEngine.isPlaying)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                openNowPlaying()
            }
        }
    }
}

// MARK: - ButtonStyle con feedback de presión (reusable, GPU barato)
struct PressableButtonStyle: ButtonStyle {
    let scale: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
