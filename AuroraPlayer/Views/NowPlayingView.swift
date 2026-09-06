import SwiftUI
import AVFoundation
import AVKit

struct NowPlayingView: View {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var fileAccessService: FileAccessService
    @ObservedObject var clock: PlaybackClock
    @ObservedObject private var localization = Localization.shared
    @Environment(\.dismiss) private var dismiss

    @AppStorage("com.aurora.showVisualizer") private var showVisualizer = true
    @AppStorage("com.aurora.keepScreenOn") private var keepScreenOn = false
    @AppStorage("com.aurora.dynamicColor") private var dynamicColor = true
    @AppStorage("com.aurora.artworkCorner") private var artworkCorner: Double = 22
    @AppStorage("com.aurora.reduceTransparency") private var reduceTransparency = false
    @AppStorage("com.aurora.showLyricsByDefault") private var showLyricsByDefault = false

    @State private var showLyrics = false
    @State private var showEqualizer = false
    @State private var showQueue = false
    @State private var showQualityDetail = false
    @State private var showArtistDetail = false
    @State private var showAlbumDetail = false
    @State private var artworkScale: CGFloat = 1.0
    @State private var progressBarWidth: CGFloat = 0
    @State private var extractedColor: Color = AppTheme.accent
    @State private var extractedUIColor: UIColor = AppTheme.accentUIColor
    @State private var isScrubbing = false
    @State private var scrubPreviewTime: TimeInterval = 0

    private static let colorCache = NSCache<NSString, UIColor>()

    private var isCompactScreen: Bool {
        UIScreen.main.bounds.height < 800
    }

    private var artworkSize: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
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

    private var playIconColor: Color { AppTheme.contrastingText(on: extractedUIColor) }

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

    private var currentSongHasLyrics: Bool {
        !(audioEngine.currentSong?.lyrics.isEmpty ?? true)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundView

                VStack(spacing: 0) {
                    Spacer().frame(height: isCompactScreen ? 50 : 60)

                    artworkSection

                    Spacer().frame(height: isCompactScreen ? 16 : 24)

                    if let song = audioEngine.currentSong, !song.audioQualityDescription.isEmpty {
                        qualityBadge(song.audioQualityDescription)
                            .padding(.bottom, 8)
                    }

                    trackInfoSection

                    Spacer().frame(height: isCompactScreen ? 12 : 20)

                    progressSection

                    Spacer().frame(height: isCompactScreen ? 16 : 24)

                    controlsView

                    Spacer().frame(height: isCompactScreen ? 12 : 16)

                    featureButtonsView

                    Spacer(minLength: isCompactScreen ? 16 : 24)
                }
            }
            .ignoresSafeArea(.container, edges: .top)
            .sheet(isPresented: $showLyrics) {
                LyricsView(song: audioEngine.currentSong, audioEngine: audioEngine, clock: audioEngine.clock)
            }
            .sheet(isPresented: $showEqualizer) {
                EqualizerView(audioEngine: audioEngine)
            }
            .sheet(isPresented: $showQueue) {
                QueueView(audioEngine: audioEngine)
            }
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
            .toolbarBackground(Color(UIColor.systemBackground).opacity(0.92), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(Localization.localized("nowPlaying.title"))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .tracking(2.5)
                        .foregroundStyle(AppTheme.contrastingText(on: extractedUIColor).opacity(0.9))
                        .textCase(.uppercase)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .foregroundStyle(AppTheme.contrastingText(on: extractedUIColor).opacity(0.7))
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
            }
            .onChange(of: audioEngine.isPlaying) { isPlaying in
                UIApplication.shared.isIdleTimerDisabled = keepScreenOn && isPlaying
            }
            .onChange(of: audioEngine.currentSong?.id) { _ in
                extractColorFromArtwork()
            }
        }
        .overlay {
            qualityDetailModal
        }
    }

    private var backgroundView: some View {
        Group {
            if reduceTransparency {
                Color(UIColor.systemBackground).ignoresSafeArea()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(extractedUIColor).opacity(0.18),
                            Color(UIColor.systemBackground),
                            Color(UIColor.systemBackground)
                        ],
                        startPoint: .top, endPoint: .bottom
                    ).ignoresSafeArea()

                    Color(UIColor.systemBackground).opacity(0.75).ignoresSafeArea()

                    // ✅ Capa de material translúcido (sin dependencia externa)
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea()
                        .opacity(reduceTransparency ? 0 : 1)
                }
            }
        }
    }

    private var artworkSection: some View {
        GeometryReader { geometry in
            let size = artworkSize

            return HStack {
                Spacer()
                artworkView(frame: CGSize(width: size, height: size))
                Spacer()
            }
            .frame(height: geometry.size.height)
        }
        .frame(height: artworkSize)
    }

    @ViewBuilder
    private func artworkView(frame: CGSize) -> some View {
        if let artwork = audioEngine.currentSong?.artwork {
            Image(uiImage: artwork)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: frame.width, height: frame.height)
                .clipShape(RoundedRectangle(cornerRadius: CGFloat(artworkCorner), style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 10)
                .overlay {
                    RoundedRectangle(cornerRadius: CGFloat(artworkCorner), style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                }
                .scaleEffect(artworkScale)
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: artworkScale)
                .onAppear {
                    artworkScale = 0.92
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                        artworkScale = 1.0
                    }
                }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: CGFloat(artworkCorner), style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [extractedColor.opacity(0.3), extractedColor.opacity(0.1)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: frame.width, height: frame.height)
                    .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)

                Image(systemName: "music.note")
                    .font(.system(size: frame.width * 0.18, weight: .light))
                    .foregroundStyle(extractedColor.opacity(0.8))
            }
        }
    }

    @ViewBuilder
    private func qualityBadge(_ text: String) -> some View {
        Button {
            Haptics.light()
            showQualityDetail = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text(text)
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
            }
            .foregroundStyle(playIconColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                Capsule().fill(
                    LinearGradient(
                        colors: [extractedColor.opacity(0.22), extractedColor.opacity(0.12)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            }
            .overlay {
                Capsule().strokeBorder(playIconColor.opacity(0.2), lineWidth: 0.5)
            }
            .shadow(color: extractedColor.opacity(0.15), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }

    private var trackInfoSection: some View {
        VStack(spacing: 5) {
            Text(audioEngine.currentSong?.title ?? Localization.localized("quality.noSong"))
                .font(.system(size: isCompactScreen ? 20 : 24, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Text(audioEngine.currentSong?.displaySubtitle ?? "")
                .font(.system(size: isCompactScreen ? 13 : 15, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
    }

    private var progressSection: some View {
        VStack(spacing: 6) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 4)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [extractedColor, extractedColor.opacity(0.8)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * progress, height: 4)

                    Circle()
                        .fill(Color.white)
                        .frame(width: isScrubbing ? 14 : 10, height: isScrubbing ? 14 : 10)
                        .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
                        .offset(x: geometry.size.width * progress - (isScrubbing ? 7 : 5))
                        .animation(.easeOut(duration: 0.15), value: isScrubbing)
                }
                .frame(height: 20)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isScrubbing {
                                isScrubbing = true
                                Haptics.light()
                            }
                            let newProgress = min(max(0, value.location.x / geometry.size.width), 1)
                            scrubPreviewTime = newProgress * audioEngine.duration
                        }
                        .onEnded { value in
                            let finalProgress = min(max(0, value.location.x / geometry.size.width), 1)
                            audioEngine.seek(to: finalProgress * audioEngine.duration)
                            isScrubbing = false
                        }
                )
            }
            .frame(height: 20)

            HStack {
                Text(scrubPreviewText)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer()

                Text(formatTime(audioEngine.duration))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
    }

    private var controlsView: some View {
        HStack(spacing: isCompactScreen ? 6 : 12) {
            controlButton(icon: "shuffle", isActive: audioEngine.isShuffleEnabled) {
                Haptics.light()
                audioEngine.toggleShuffle()
            }

            controlButton(icon: "backward.fill", size: .medium) {
                Haptics.light()
                audioEngine.playPrevious()
            }

            Button {
                Haptics.medium()
                if audioEngine.isPlaying {
                    audioEngine.pause()
                } else {
                    audioEngine.resume()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [extractedColor, extractedColor.opacity(0.8)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: isCompactScreen ? 64 : 74, height: isCompactScreen ? 64 : 74)
                        .shadow(color: extractedColor.opacity(0.4), radius: 12, x: 0, y: 5)

                    Image(systemName: audioEngine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: isCompactScreen ? 24 : 28, weight: .bold))
                        .foregroundStyle(playIconColor)
                        .id(audioEngine.isPlaying ? "playing" : "paused")
                }
                .animation(.easeInOut(duration: 0.2), value: audioEngine.isPlaying)
            }
            .buttonStyle(.plain)

            controlButton(icon: "forward.fill", size: .medium) {
                Haptics.light()
                audioEngine.playNext()
            }

            controlButton(icon: repeatIcon, isActive: audioEngine.repeatMode != .off) {
                Haptics.light()
                audioEngine.cycleRepeatMode()
            }

            if let song = audioEngine.currentSong {
                Button {
                    Haptics.light()
                    fileAccessService.toggleLike(song)
                } label: {
                    ZStack {
                        Capsule()
                            .fill(fileAccessService.isLiked(song) ? Color.red.opacity(0.2) : Color.clear)
                            .frame(width: isCompactScreen ? 38 : 44, height: isCompactScreen ? 28 : 34)

                        Image(systemName: fileAccessService.isLiked(song) ? "heart.fill" : "heart")
                            .font(.system(size: isCompactScreen ? 15 : 17, weight: fileAccessService.isLiked(song) ? .bold : .semibold))
                            .foregroundStyle(fileAccessService.isLiked(song) ? .red : AppTheme.contrastingText(on: extractedUIColor).opacity(0.7))
                    }
                    .frame(width: isCompactScreen ? 56 : 64, height: isCompactScreen ? 56 : 64)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .fixedSize()
    }

    @ViewBuilder
    private func controlButton(icon: String, size: ControlSize = .small, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                if size == .medium {
                    Circle()
                        .fill(controlBackground)
                        .frame(width: isCompactScreen ? 44 : 50, height: isCompactScreen ? 44 : 50)
                } else {
                    Capsule()
                        .fill(isActive ? extractedColor.opacity(0.2) : Color.clear)
                        .frame(width: isCompactScreen ? 38 : 44, height: isCompactScreen ? 28 : 34)
                }

                Image(systemName: icon)
                    .font(.system(size: isCompactScreen ? 15 : 17, weight: isActive ? .bold : .semibold))
                    .foregroundStyle(isActive ? playIconColor : AppTheme.contrastingText(on: extractedUIColor).opacity(0.7))
            }
            .frame(width: isCompactScreen ? 56 : 64, height: isCompactScreen ? 56 : 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private enum ControlSize {
        case small, medium
    }

    private var featureButtonsView: some View {
        let buttonSize: CGFloat = isCompactScreen ? 56 : 64
        let capsuleWidth: CGFloat = isCompactScreen ? 42 : 48
        let capsuleHeight: CGFloat = isCompactScreen ? 32 : 36
        let iconSize: CGFloat = isCompactScreen ? 14 : 16

        return HStack(spacing: isCompactScreen ? 8 : 12) {
            featureButton(icon: "slider.horizontal.3", active: audioEngine.isEQEnabled) {
                Haptics.light()
                showEqualizer = true
            }

            featureButton(icon: currentSongHasLyrics ? "quote.bubble.fill" : "quote.bubble", active: currentSongHasLyrics) {
                Haptics.light()
                showLyrics = true
            }

            featureButton(icon: "list.bullet", active: !audioEngine.nextUpQueue.isEmpty) {
                Haptics.light()
                showQueue = true
            }

            featureButton(icon: "airplayaudio", active: audioEngine.outputPortType == AVAudioSession.Port.airPlay.rawValue) {
                AirPlayRoutePickerView()
                    .frame(width: buttonSize, height: buttonSize)
                    .opacity(0.011)
                    .allowsHitTesting(true)
            }

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
                Divider()
                if let url = audioEngine.currentSong?.url {
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

    // ✅ Overload sin picker (la mayoría de botones de feature)
    @ViewBuilder
    private func featureButton(
        icon: String,
        active: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let buttonSize: CGFloat = isCompactScreen ? 56 : 64
        let capsuleWidth: CGFloat = isCompactScreen ? 42 : 48
        let capsuleHeight: CGFloat = isCompactScreen ? 32 : 36
        let iconSize: CGFloat = isCompactScreen ? 14 : 16

        ZStack {
            Button(action: action) {
                ZStack {
                    Capsule()
                        .fill(active ? extractedColor.opacity(0.2) : Color.clear)
                        .frame(width: capsuleWidth, height: capsuleHeight)

                    Image(systemName: icon)
                        .font(.system(size: iconSize, weight: active ? .bold : .semibold))
                        .foregroundStyle(active ? playIconColor : AppTheme.contrastingText(on: extractedUIColor).opacity(0.7))
                }
                .frame(width: buttonSize, height: buttonSize)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: buttonSize, height: buttonSize)
    }

    // ✅ Overload con picker (AirPlay superpuesto, iOS 16+)
    @ViewBuilder
    private func featureButton<Picker: View>(
        icon: String,
        active: Bool,
        @ViewBuilder picker: () -> Picker
    ) -> some View {
        let buttonSize: CGFloat = isCompactScreen ? 56 : 64
        let capsuleWidth: CGFloat = isCompactScreen ? 42 : 48
        let capsuleHeight: CGFloat = isCompactScreen ? 32 : 36
        let iconSize: CGFloat = isCompactScreen ? 14 : 16

        ZStack {
            Button {
                // El picker nativo maneja el toque
            } label: {
                ZStack {
                    Capsule()
                        .fill(active ? extractedColor.opacity(0.2) : Color.clear)
                        .frame(width: capsuleWidth, height: capsuleHeight)

                    Image(systemName: icon)
                        .font(.system(size: iconSize, weight: active ? .bold : .semibold))
                        .foregroundStyle(active ? playIconColor : AppTheme.contrastingText(on: extractedUIColor).opacity(0.7))
                }
                .frame(width: buttonSize, height: buttonSize)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            picker()
        }
        .frame(width: buttonSize, height: buttonSize)
    }

    private var qualityDetailModal: some View {
        Group {
            if showQualityDetail {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture {
                            showQualityDetail = false
                        }

                    VStack(spacing: 0) {
                        HStack {
                            Spacer()
                            Button {
                                showQualityDetail = false
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.secondary)
                                    .background(Circle().fill(Color(UIColor.systemBackground)))
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
                            .shadow(color: .black.opacity(0.35), radius: 30, x: 0, y: 15)
                            .shadow(color: AppTheme.accent.opacity(0.08), radius: 20, x: 0, y: 5)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                    .padding(.horizontal, 24)
                    .scaleEffect(showQualityDetail ? 1.0 : 0.88)
                    .opacity(showQualityDetail ? 1.0 : 0)
                    .blur(radius: showQualityDetail ? 0 : 8)
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showQualityDetail)
            }
        }
    }

    private var controlBackground: AnyShapeStyle {
        reduceTransparency
            ? AnyShapeStyle(Color(UIColor.secondarySystemBackground))
            : AnyShapeStyle(.ultraThinMaterial)
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
        guard dynamicColor else {
            extractedColor = AppTheme.accent
            return
        }

        guard let artwork = audioEngine.currentSong?.artwork else {
            extractedColor = AppTheme.accent
            return
        }

        let cacheKey = (audioEngine.currentSong?.id.uuidString ?? "none") as NSString
        if let cached = NowPlayingView.colorCache.object(forKey: cacheKey) {
            extractedColor = AppTheme.readableColor(from: cached)
            extractedUIColor = cached
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let dominant = AppTheme.dominantColor(from: artwork) ?? AppTheme.accentUIColor
            NowPlayingView.colorCache.setObject(dominant, forKey: cacheKey)
            DispatchQueue.main.async {
                self.extractedColor = AppTheme.readableColor(from: dominant)
                self.extractedUIColor = dominant
            }
        }
    }
}

struct AirPlayRoutePickerView: UIViewRepresentable {
    typealias UIViewType = AVRoutePickerView

    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = false
        picker.tintColor = AppTheme.accentUIColor
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}