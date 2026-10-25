import SwiftUI
import AVFoundation
import AVKit

// ══════════════════════════════════════════════════════════════════════════
// NOW PLAYING — reescritura estricta para pantallas de 5.5" (iPhone 8 Plus).
//
// Orden fijo de arriba a abajo:
//   1. Header: cerrar + "Reproduciendo".
//   2. Fondo: portada desenfocada + degradado tonal.
//   3. Portada: min(ancho - 60, 300), radio 24.
//   4. Info: título 24/Roboto Bold, artista 16/Roboto Regular, a la izquierda.
//   5. Progreso: onda + tiempos.
//   6. Controles: play en píldora + shuffle/anterior/siguiente/repeat.
//   7. Features: Letras, Cola, EQ y AirPlay.
//
// No hay `matchedGeometryEffect`, ni hero, ni tarjetas flotantes: el contenido
// vive en un ScrollView para que en el 8 Plus nunca se solape ni se recorte.
// ══════════════════════════════════════════════════════════════════════════

struct NowPlayingView: View {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var fileAccessService: FileAccessService
    let clock: PlaybackClock
    var onClose: (() -> Void)? = nil

    @ObservedObject private var localization = Localization.shared
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.dismiss) private var dismiss

    @AppStorage("com.aurora.keepScreenOn") private var keepScreenOn = false
    @AppStorage("com.aurora.reduceTransparency") private var reduceTransparency = false

    @State private var showLyrics = false
    @State private var showEqualizer = false
    @State private var showQueue = false

    // MARK: - Colores de la portada

    private var extractedColor: Color {
        if theme.accentFromArtwork, let color = theme.artworkAccentColor {
            return color
        }
        return AppTheme.accent
    }

    private var extractedUIColor: UIColor {
        if theme.accentFromArtwork, let color = theme.artworkAccentUIColor {
            return color
        }
        return AppTheme.accentUIColor
    }

    /// Texto/iconos sobre la portada desenfocada.
    private var playIconColor: Color {
        AppTheme.contrastingText(on: extractedUIColor)
    }

    private var isNarrow: Bool {
        UIScreen.main.bounds.width < 380
    }

    private var artworkSide: CGFloat {
        min(UIScreen.main.bounds.width - 60, 300)
    }

    private var currentSong: Song? {
        audioEngine.currentSong
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            backgroundView

            VStack(spacing: 0) {
                headerView

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 18) {
                        artworkView
                        songInfoView
                        progressView
                        controlsView
                        featureButtonsView
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
            }
        }
        .onAppear {
            audioEngine.isKeepScreenOnEnabled = keepScreenOn
            UIApplication.shared.isIdleTimerDisabled = keepScreenOn && audioEngine.isPlaying
            ThemeManager.shared.updateArtworkAccent(from: audioEngine.currentSong)
        }
        .onChange(of: audioEngine.currentSong?.id) { _ in
            ThemeManager.shared.updateArtworkAccent(from: audioEngine.currentSong)
        }
        .onChange(of: audioEngine.isPlaying) { isPlaying in
            UIApplication.shared.isIdleTimerDisabled = keepScreenOn && isPlaying
        }
        .onChange(of: theme.accentFromArtwork) { value in
            if value, let song = audioEngine.currentSong {
                ThemeManager.shared.updateArtworkAccent(from: song)
            }
        }
        .m3eScreen(isPresented: $showLyrics) {
            LyricsView(song: audioEngine.currentSong, viewModel: audioEngine.lyricsViewModel)
        }
        .m3eScreen(isPresented: $showEqualizer) {
            EqualizerView(audioEngine: audioEngine)
        }
        .m3eScreen(isPresented: $showQueue) {
            QueueView(audioEngine: audioEngine, fileAccessService: fileAccessService)
        }
    }

    // MARK: - 1. Header

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
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(playIconColor)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Localization.localized("nowPlaying.close"))

            Spacer(minLength: 8)

            Text(Localization.localized("nowPlaying.title"))
                .font(M3ETypography.titleMedium)
                .tracking(0.15)
                .foregroundStyle(playIconColor.opacity(0.9))
                .lineLimit(1)

            Spacer(minLength: 8)

            Color.clear
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    // MARK: - 2. Fondo

    private var backgroundView: some View {
        ZStack {
            M3EColor.surface
                .ignoresSafeArea()

            if let artwork = currentSong?.artwork, !reduceTransparency {
                GeometryReader { geo in
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .blur(radius: 40, opaque: true)
                        .opacity(0.6)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            LinearGradient(
                colors: [
                    M3EColor.primary.opacity(0.55),
                    M3EColor.primary.opacity(0.22),
                    M3EColor.surface
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    // MARK: - 3. Portada

    private var artworkView: some View {
        Group {
            if let artwork = currentSong?.artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: artworkSide, height: artworkSide)
                    .clipShape(M3EShape(family: .extraLarge))
                    .overlay(
                        M3EShape(family: .extraLarge)
                            .strokeBorder(playIconColor.opacity(0.14), lineWidth: 1)
                    )
            } else {
                M3EShape(family: .extraLarge)
                    .fill(M3EColor.surfaceContainerHigh)
                    .frame(width: artworkSide, height: artworkSide)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: artworkSide * 0.18, weight: .light))
                            .foregroundStyle(M3EColor.onSurfaceVariant)
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    // MARK: - 4. Info (izquierda) + corazón (derecha)

    private var songInfoView: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(currentSong?.displayName ?? Localization.localized("quality.noSong"))
                    .font(M3ETypography.displaySmall)
                    .tracking(0)
                    .foregroundStyle(playIconColor)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(currentSong?.displaySubtitle ?? "—")
                    .font(M3ETypography.bodyLarge)
                    .tracking(0.5)
                    .foregroundStyle(playIconColor.opacity(0.72))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Haptics.light()
                if let song = currentSong {
                    fileAccessService.toggleLike(song)
                }
            } label: {
                Image(systemName: isCurrentLiked ? "heart.fill" : "heart")
                    .font(.system(size: 18, weight: isCurrentLiked ? .bold : .semibold))
                    .foregroundStyle(isCurrentLiked ? Color.red : playIconColor.opacity(0.75))
                    .frame(width: 42, height: 42)
                    .background(
                        Circle().fill(M3EColor.surfaceContainerHigh)
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(PressableButtonStyle(scale: AuroraPressScale.chip, pressedOpacity: 0.6))
            .accessibilityLabel(Localization.localized("actions.like"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var isCurrentLiked: Bool {
        guard let song = currentSong else { return false }
        return fileAccessService.isLiked(song)
    }

    // MARK: - 5. Progreso

    private var progressView: some View {
        NowPlayingProgress(
            audioEngine: audioEngine,
            clock: clock,
            tint: playIconColor
        )
    }

    // MARK: - 6. Controles

    private var controlsView: some View {
        HStack(spacing: isNarrow ? 2 : 6) {
            transportButton(
                icon: "shuffle",
                active: audioEngine.isShuffleEnabled,
                accessibility: Localization.localized("accessibility.shuffle")
            ) {
                audioEngine.toggleShuffle()
            }

            transportButton(
                icon: "backward.fill",
                accessibility: Localization.localized("accessibility.previousSong")
            ) {
                audioEngine.playPrevious()
            }

            playPill

            transportButton(
                icon: "forward.fill",
                enabled: audioEngine.hasNextTrack,
                accessibility: Localization.localized("accessibility.nextSong")
            ) {
                audioEngine.playNext()
            }

            transportButton(
                icon: repeatIcon,
                active: audioEngine.repeatMode != .off,
                accessibility: Localization.localized("accessibility.repeat")
            ) {
                audioEngine.cycleRepeatMode()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var playPill: some View {
        M3EFilledButton(
            horizontalPadding: isNarrow ? 12 : 18,
            verticalPadding: 0
        ) {
            Haptics.medium()
            if audioEngine.isPlaying {
                audioEngine.pause()
            } else {
                audioEngine.resume()
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: audioEngine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: isNarrow ? 14 : 16, weight: .bold))

                Text(audioEngine.isPlaying
                     ? Localization.localized("actions.pause")
                     : Localization.localized("actions.play"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(height: isNarrow ? 48 : 52)
        }
        .accessibilityLabel(Localization.localized("accessibility.playPause"))
    }

    private func transportButton(
        icon: String,
        active: Bool = false,
        enabled: Bool = true,
        accessibility: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: isNarrow ? 14 : 16, weight: active ? .bold : .semibold))
                .foregroundStyle(active ? M3EColor.onPrimary : M3EColor.onPrimaryContainer)
                .frame(width: isNarrow ? 38 : 44, height: isNarrow ? 38 : 44)
                .background(
                    Circle().fill(active ? M3EColor.primary : M3EColor.primaryContainer)
                )
                .contentShape(Circle())
        }
        .buttonStyle(M3ESquishButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(accessibility)
    }

    private var repeatIcon: String {
        audioEngine.repeatMode == .one ? "repeat.1" : "repeat"
    }

    // MARK: - 7. Features

    private var featureButtonsView: some View {
        HStack(spacing: 8) {
            featureButton(
                icon: "quote.bubble",
                title: Localization.localized("nowPlaying.lyrics"),
                accessibility: Localization.localized("quality.accessibility.lyrics")
            ) {
                showLyrics = true
            }

            featureButton(
                icon: "list.bullet",
                title: Localization.localized("nowPlaying.queue"),
                accessibility: Localization.localized("quality.accessibility.queue")
            ) {
                showQueue = true
            }

            featureButton(
                icon: "slider.horizontal.3",
                title: Localization.localized("quality.accessibility.equalizer"),
                accessibility: Localization.localized("quality.accessibility.equalizer")
            ) {
                showEqualizer = true
            }

            // AirPlay: el picker nativo va invisible encima y abre su menú.
            ZStack {
                featureButtonLabel(
                    icon: "airplayaudio",
                    title: "AirPlay"
                )

                AirPlayRoutePickerView()
                    .opacity(0.011)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .accessibilityLabel(Localization.localized("quality.accessibility.airplay"))
        }
        .padding(.top, 4)
    }

    private func featureButton(
        icon: String,
        title: String,
        accessibility: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            featureButtonLabel(icon: icon, title: title)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.94, pressedOpacity: 0.75))
        .frame(maxWidth: .infinity)
        .accessibilityLabel(accessibility)
    }

    private func featureButtonLabel(icon: String, title: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(M3EColor.onSecondaryContainer)

            Text(title)
                .font(M3ETypography.labelSmall)
                .foregroundStyle(M3EColor.onSecondaryContainer.opacity(0.78))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(M3EShape(family: .large).fill(M3EColor.secondaryContainer))
        .overlay(
            M3EShape(family: .large)
                .strokeBorder(M3EColor.outline.opacity(0.2), lineWidth: 1)
        )
        .contentShape(M3EShape(family: .large))
    }
}

// MARK: - Progreso aislado del reloj

/// Única subvista que observa `PlaybackClock`: NowPlaying no se re-renderiza
/// cada 0.4 s y los botones conservan el primer toque.
private struct NowPlayingProgress: View {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var clock: PlaybackClock
    let tint: Color

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

    private var currentText: String {
        format(isScrubbing ? scrubPreviewTime : clock.time)
    }

    var body: some View {
        VStack(spacing: 6) {
            AuroraWavyProgress(
                progress: progress,
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
            .frame(height: 20)

            HStack {
                Text(currentText)
                Spacer()
                Text(format(audioEngine.duration))
            }
            .font(M3ETypography.labelMedium)
            .foregroundStyle(tint.opacity(0.72))
            .monospacedDigit()
        }
    }

    private func format(_ time: TimeInterval) -> String {
        guard time.isFinite, !time.isNaN else { return "0:00" }
        let total = Int(max(0, time))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - AirPlay (UIKit)

struct AirPlayRoutePickerView: UIViewRepresentable {
    typealias UIViewType = AVRoutePickerView

    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = false
        picker.tintColor = AppTheme.accentUIColor
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        let tint = AppTheme.accentUIColor
        if uiView.tintColor != tint { uiView.tintColor = tint }
    }
}
