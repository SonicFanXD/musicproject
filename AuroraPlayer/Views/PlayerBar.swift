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

    // ✅ Esquinas del artwork sincronizadas con el ajuste de Apariencia
    @AppStorage("com.aurora.artworkCorner") private var artworkCorner: Double = 22
    @AppStorage("com.aurora.compactPlayerBar") private var compactPlayerBar = false
    // ✅ Ajuste "Visualizador en barra" (antes no se aplicaba)
    @AppStorage("com.aurora.showVisualizerInBar") private var showVisualizerInBar = true

    // ✅ Observar ThemeManager para que los cambios de acento (manual o desde carátula)
    // se apliquen instantáneamente sin necesidad de cambiar de canción.
    @ObservedObject private var theme = ThemeManager.shared

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

    // ✅ Color dominante del artwork para indicadores dinámicos
    // Observa ThemeManager: si "Acento desde portada" está activo, usa el color
    // publicado (re-render instantáneo). Si no, usa el acento manual del tema.
    private var artworkDominantColor: Color {
        if theme.accentFromArtwork, let artworkColor = theme.artworkAccentColor {
            return artworkColor
        }
        return theme.accent
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
                                    // ✅ iOS 16 compatible: animar opacidad con value: isPlaying
                                    // (audioEngine es ObservedObject → re-renderiza al cambiar)
                                    .opacity(audioEngine.isPlaying ? 1 : 0)
                                    .animation(.easeInOut(duration: 0.3), value: audioEngine.isPlaying)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .padding(.vertical, 6)
                        .onTapGesture {
                            openNowPlaying()
                        }

                        // ✅ Botón de me gusta con material de vidrio (estilo NowPlayingView)
                        Button {
                            Haptics.light()
                            fileAccessService.toggleLike(song)
                        } label: {
                            Image(systemName: fileAccessService.isLiked(song) ? "heart.fill" : "heart")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(fileAccessService.isLiked(song) ? .red : .secondary)
                                .frame(width: 38, height: 38)
                                .background {
                                    Circle().fill(AnyShapeStyle(.ultraThinMaterial))
                                        .frame(width: 38, height: 38)
                                }
                                .contentShape(Circle())
                        }
                        .buttonStyle(PressableButtonStyle(scale: 0.9))

                        // ✅ Controles rediseñados con mejor feedback visual
                        HStack(spacing: 4) {
                            // ✅ Previous con material de vidrio (estilo NowPlayingView)
                            Button {
                                Haptics.light()
                                audioEngine.playPrevious()
                            } label: {
                                Image(systemName: "backward.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .frame(width: 42, height: 42)
                                    .background {
                                        Circle().fill(AnyShapeStyle(.ultraThinMaterial))
                                    }
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
                                    // ✅ Círculo con gradiente del color dominante
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [artworkDominantColor, artworkDominantColor.opacity(0.85)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )

                                    // ✅ Halo animado cuando reproduce
                                    Circle()
                                        .stroke(artworkDominantColor.opacity(0.4), lineWidth: 2)
                                        .scaleEffect(audioEngine.isPlaying ? 1.15 : 1.0)
                                        .opacity(audioEngine.isPlaying ? 1.0 : 0)
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
                                .shadow(color: artworkDominantColor.opacity(0.4), radius: 10, x: 0, y: 4)
                                .scaleEffect(playButtonScale)
                                .contentShape(Circle())
                            }
                            .buttonStyle(PressableButtonStyle(scale: 0.88))
                            .accessibilityLabel(Localization.localized("accessibility.playPause"))

                            // ✅ Next con material de vidrio (estilo NowPlayingView)
                            Button {
                                Haptics.light()
                                audioEngine.playNext()
                            } label: {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .frame(width: 42, height: 42)
                                    .background {
                                        Circle().fill(AnyShapeStyle(.ultraThinMaterial))
                                    }
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

                    // ✅ Barra de progreso mejorada con preview de scrub y color dinámico
                    // ✅ FIX: .frame(maxWidth: .infinity) para que el GeometryReader
                    // se expanda al ancho completo disponible. Sin esto, el ancho
                    // podía colapsar y la barra quedaba desalineada/estrecha.
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // ✅ Track con material de vidrio (estilo NowPlayingView)
                            Capsule()
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: compactPlayerBar ? 3 : 4)

                            // ✅ Progreso con gradiente del color dominante del artwork
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [artworkDominantColor.opacity(0.8), artworkDominantColor],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(4, geometry.size.width * progress), height: compactPlayerBar ? 3 : 4)
                                .shadow(color: artworkDominantColor.opacity(0.4), radius: 4, x: 0, y: 0)

                            // ✅ Indicador de posición al hacer scrub
                            if isScrubbing {
                                Circle()
                                    .fill(artworkDominantColor)
                                    .frame(width: 12, height: 12)
                                    .offset(x: geometry.size.width * scrubPreviewProgress - 6)
                                    .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)
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
                    // ✅ Esquinas muy redondeadas (34pt) con material premium (estilo NowPlayingView)
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(AnyShapeStyle(.ultraThinMaterial))
                        .shadow(color: .black.opacity(0.18), radius: 20, x: 0, y: 8)
                    // Borde sutil superior para profundidad
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.15), .white.opacity(0.03), .clear],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
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
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: CGFloat(artworkCorner * (14.0 / 22.0)), style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
                .overlay(
                    // ✅ Indicador de reproducción con color dinámico del artwork
                    RoundedRectangle(cornerRadius: CGFloat(artworkCorner * (14.0 / 22.0)), style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [artworkDominantColor.opacity(0.6), artworkDominantColor.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ).opacity(audioEngine.isPlaying ? 1.0 : 0.0),
                            lineWidth: 2
                        )
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
                            colors: [artworkDominantColor.opacity(0.32), artworkDominantColor.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                    .shadow(color: artworkDominantColor.opacity(0.2), radius: 6, x: 0, y: 3)

                Image(systemName: audioEngine.isPlaying ? "waveform" : "music.note")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(artworkDominantColor)
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
