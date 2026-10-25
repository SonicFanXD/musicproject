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
    var onOpenNowPlaying: () -> Void

    @ObservedObject private var localization = Localization.shared
    @ObservedObject private var theme = ThemeManager.shared

    @AppStorage("com.aurora.artworkCorner") private var artworkCorner: Double = 22
    @AppStorage("com.aurora.compactPlayerBar") private var compactPlayerBar = false
    @AppStorage("com.aurora.showVisualizerInBar") private var showVisualizerInBar = true

    private var artworkSide: CGFloat { compactPlayerBar ? 44 : 48 }

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
                        tint: M3EColor.primary,
                        base: M3EColor.surfaceContainerHigh
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
            .foregroundStyle(M3EColor.onPrimary)
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(
                Capsule(style: .continuous)
                    .fill(M3EColor.primary)
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
                    .overlay(
                        RoundedRectangle(cornerRadius: CGFloat(artworkCorner * (14.0 / 22.0)), style: .continuous)
                            .strokeBorder(M3EColor.outline.opacity(0.2), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { openNowPlaying() }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: CGFloat(artworkCorner * (14.0 / 22.0)), style: .continuous)
                        .fill(M3EColor.surfaceContainerHigh)
                        .frame(width: artworkSide, height: artworkSide)

                    Image(systemName: "music.note")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(M3EColor.primary)
                }
                .contentShape(Rectangle())
                .onTapGesture { openNowPlaying() }
            }
        }
        // ✅ Sin `matchedGeometryEffect`: la portada no viaja entre vistas.
        // En el 8 Plus el hero arrastraba la miniatura por encima de los
        // controles durante la transición; NowPlaying entra con su propio fundido.
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
