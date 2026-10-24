import SwiftUI

// ══════════════════════════════════════════════════════════════════════════
// PLAYER BAR — mini reproductor flotante con lenguaje Android/M3E.
//
// · Superficie tonal sólida (`M3ETonalSurface`), radio 28 y separación de los
//   bordes: es una barra que FLOTA sobre la biblioteca, no un dock pegado.
// · El play es una píldora con icono + texto ("Reproducir"/"Pausar"), no el
//   círculo de iOS.
// · La onda de progreso vive entre anterior/siguiente, en una segunda fila,
//   con el gesto de scrub dentro del propio componente.
// · Sin halo `repeatForever`: el único movimiento continuo es la onda y se
//   detiene al pausar (`TimelineView` pausado).
// ══════════════════════════════════════════════════════════════════════════

struct PlayerBar: View {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var fileAccessService: FileAccessService
    // El reloj de reproducción YA NO se observa aquí: vive en la subvista
    // PlayerScrubBar, la única que necesita el tiempo. Así cada tick (0.4 s)
    // no re-renderiza los botones y el primer toque nunca se pierde.
    var clock: PlaybackClock
    // La portada de la barra y la de NowPlaying comparten namespace para que
    // el hero viaje entre ambas geometrías.
    var heroNamespace: Namespace.ID
    var onOpenNowPlaying: () -> Void

    @ObservedObject private var localization = Localization.shared
    @ObservedObject private var theme = ThemeManager.shared

    @AppStorage("com.aurora.artworkCorner") private var artworkCorner: Double = 22
    @AppStorage("com.aurora.compactPlayerBar") private var compactPlayerBar = false
    @AppStorage("com.aurora.showVisualizerInBar") private var showVisualizerInBar = true

    private var artworkSide: CGFloat { compactPlayerBar ? 44 : 48 }

    // MARK: - Acento

    private var accentPair: (primary: Color, secondary: Color) {
        if theme.accentFromArtwork, let artworkColor = theme.artworkAccentColor {
            return (artworkColor, theme.artworkSecondaryColor ?? artworkColor.opacity(0.7))
        }
        return (theme.accent, theme.accent.opacity(0.4))
    }

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

    /// Si el secundario de la carátula difiere MUCHO en brillo del primario, se
    /// conserva su TONO pero se ancla su brillo al del primario: el glifo del
    /// play mantiene contraste sin perder el color real de la portada.
    private func textSafeAccentGradient() -> LinearGradient {
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
            colors: [pair.primary, secondaryStop],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var playGlyphColor: Color {
        if theme.accentFromArtwork, let accent = theme.artworkAccentUIColor {
            return AppTheme.contrastingText(on: accent)
        }
        return AppTheme.contrastingText(on: AppTheme.accentUIColor)
    }

    // MARK: - Body

    var body: some View {
        Group {
            if let song = audioEngine.currentSong {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        artwork(for: song)

                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.title)
                                    .font(M3ETypography.titleMediumEmphasized)
                                    .foregroundStyle(M3EColor.onSurface)
                                    .lineLimit(1)

                                Text(song.artist.isEmpty ? Localization.localized("details.unknownArtist") : song.artist)
                                    .font(M3ETypography.bodyMedium)
                                    .foregroundStyle(M3EColor.onSurfaceVariant)
                                    .lineLimit(1)
                            }

                            if showVisualizerInBar {
                                AudioVisualizer(
                                    audioEngine: audioEngine,
                                    secondaryTintColor: theme.artworkSecondaryColor
                                )
                                .frame(width: 18, height: 14)
                                .opacity(audioEngine.isPlaying ? 1 : 0)
                                .animation(AuroraMotion.spatialFast, value: audioEngine.isPlaying)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { openNowPlaying() }

                        likeButton(for: song)

                        playPill
                    }
                    .padding(.leading, 14)
                    .padding(.trailing, 10)
                    .padding(.top, compactPlayerBar ? 8 : 10)
                    .padding(.bottom, 2)

                    PlayerScrubBar(
                        audioEngine: audioEngine,
                        clock: clock,
                        onOpenNowPlaying: { openNowPlaying() }
                    )
                }
                .background(
                    M3ETonalSurface(
                        cornerRadius: 28,
                        tint: theme.accent
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
        }
    }

    // MARK: - Play (píldora Android)

    private var playPill: some View {
        Button {
            Haptics.light()
            if audioEngine.isPlaying {
                audioEngine.pause()
            } else {
                audioEngine.resume()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: audioEngine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))

                Text(audioEngine.isPlaying
                     ? Localization.localized("actions.pause")
                     : Localization.localized("actions.play"))
                    .font(M3ETypography.labelLargeEmphasized)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(playGlyphColor)
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(
                Capsule(style: .continuous)
                    .fill(textSafeAccentGradient())
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(playGlyphColor.opacity(0.12), lineWidth: 1)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(M3ESquishButtonStyle())
        .accessibilityLabel(Localization.localized("accessibility.playPause"))
    }

    // MARK: - Like

    private func likeButton(for song: Song) -> some View {
        Button {
            Haptics.light()
            fileAccessService.toggleLike(song)
        } label: {
            Image(systemName: fileAccessService.isLiked(song) ? "heart.fill" : "heart")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(fileAccessService.isLiked(song) ? .red : M3EColor.onSurfaceVariant)
                .frame(width: 36, height: 36)
                .background(
                    Circle().fill(M3EColor.surfaceContainerHigh)
                )
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.9))
    }

    // MARK: - Artwork

    private func artwork(for song: Song) -> some View {
        Group {
            if let art = song.artwork {
                // Miniatura 96 px (48 pt @2x) en vez de la 768 px completa.
                Image(uiImage: AppTheme.thumbnail(from: art, size: CGSize(width: 96, height: 96)))
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: artworkSide, height: artworkSide)
                    .clipShape(RoundedRectangle(cornerRadius: CGFloat(artworkCorner * (14.0 / 22.0)), style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
                    .overlay(
                        RoundedRectangle(cornerRadius: CGFloat(artworkCorner * (14.0 / 22.0)), style: .continuous)
                            .stroke(
                                accentGradient(primaryOpacity: 0.6, secondaryOpacity: 0.45)
                                    .opacity(audioEngine.isPlaying ? 1.0 : 0.0),
                                lineWidth: 2
                            )
                            .animation(AuroraMotion.spatialFast, value: audioEngine.isPlaying)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { openNowPlaying() }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: CGFloat(artworkCorner * (14.0 / 22.0)), style: .continuous)
                        .fill(accentGradient(primaryOpacity: 0.32, secondaryOpacity: 0.18))
                        .frame(width: artworkSide, height: artworkSide)

                    Image(systemName: audioEngine.isPlaying ? "waveform" : "music.note")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(theme.accent)
                        .animation(AuroraMotion.spatialFast, value: audioEngine.isPlaying)
                }
                .contentShape(Rectangle())
                .onTapGesture { openNowPlaying() }
            }
        }
        // Hero: la MISMA portada de NowPlaying lleva el id compartido.
        .matchedGeometryEffect(id: "nowPlaying.artwork", in: heroNamespace)
    }

    private func openNowPlaying() {
        onOpenNowPlaying()
    }
}

// MARK: - Onda + anterior/siguiente (única vista que observa el reloj)

private struct PlayerScrubBar: View {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var clock: PlaybackClock
    var onOpenNowPlaying: () -> Void

    @State private var isScrubbing = false
    @State private var scrubPreviewProgress: Double = 0

    private var progress: Double {
        if isScrubbing { return scrubPreviewProgress }
        guard audioEngine.duration > 0 else { return 0 }
        return min(max(clock.time / audioEngine.duration, 0), 1)
    }

    private var currentProgress: Double {
        guard audioEngine.duration > 0 else { return 0 }
        return min(max(clock.time / audioEngine.duration, 0), 1)
    }

    var body: some View {
        HStack(spacing: 4) {
            Button {
                Haptics.light()
                audioEngine.playPrevious()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(M3EColor.onSurfaceVariant)
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
            }
            .buttonStyle(M3ESquishButtonStyle())
            .accessibilityLabel(Localization.localized("accessibility.previousSong"))

            AuroraWavyProgress(
                progress: progress,
                isPlaying: audioEngine.isPlaying,
                isScrubbing: isScrubbing,
                onScrub: { newProgress in
                    guard audioEngine.duration > 0 else { return }
                    if !isScrubbing {
                        Haptics.selection()
                        scrubPreviewProgress = currentProgress
                    }
                    isScrubbing = true
                    scrubPreviewProgress = newProgress
                },
                onScrubEnd: { newProgress in
                    guard audioEngine.duration > 0 else { return }
                    isScrubbing = false
                    Haptics.light()
                    audioEngine.seek(to: audioEngine.duration * newProgress)
                },
                onTap: { onOpenNowPlaying() }
            )
            .frame(height: 16)

            Button {
                Haptics.light()
                audioEngine.playNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(M3EColor.onSurfaceVariant)
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
            }
            .buttonStyle(M3ESquishButtonStyle())
            .opacity(audioEngine.hasNextTrack ? 1 : 0.35)
            .disabled(!audioEngine.hasNextTrack)
            .accessibilityLabel(Localization.localized("accessibility.nextSong"))
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }
}
