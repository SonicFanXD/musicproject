import SwiftUI

struct NowPlayingView: View {
    @ObservedObject var audioEngine: AudioEngine
    @Environment(\.dismiss) private var dismiss

    @State private var showLyrics = false
    @State private var showAudioInfo = false
    @State private var showEqualizer = false
    @State private var showQueue = false
    @State private var artworkScale: CGFloat = 1.0
    @State private var progressBarWidth: CGFloat = 0

    private var progress: Double {
        guard audioEngine.duration > 0 else { return 0 }
        return min(max(audioEngine.currentTime / audioEngine.duration, 0), 1)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Optimized background with single layer blur
                backgroundView

                // Content
                VStack(spacing: 0) {
                    Spacer()

                    // Artwork with subtle animation
                    artworkView
                        .scaleEffect(artworkScale)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: audioEngine.isPlaying)

                    // Audio visualizer
                    if audioEngine.isPlaying {
                        AudioVisualizer(audioEngine: audioEngine)
                            .frame(height: 40)
                            .padding(.horizontal, 20)
                    }

                    Spacer().frame(height: 32)

                    // Song info
                    songInfoView

                    Spacer().frame(height: 24)

                    // Progress bar with custom styling
                    progressView

                    Spacer().frame(height: 32)

                    // Controls
                    controlsView

                    Spacer().frame(height: 32)

                    // Enhanced audiophile quality details
                    audiophileQualitySection

                    // Queue button
                    queueButton

                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 24)
            }
            .onAppear {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    artworkScale = 1.0
                }
            }
            .onChange(of: audioEngine.isPlaying) { isPlaying in
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    artworkScale = isPlaying ? 1.02 : 1.0
                }
            }
            .navigationTitle("Reproduciendo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .foregroundStyle(.primary)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            showEqualizer = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .foregroundStyle(.primary)
                        }

                        Button {
                            showLyrics = true
                        } label: {
                            Image(systemName: "quote.bubble")
                                .foregroundStyle(.primary)
                        }
                        .disabled(audioEngine.currentSong?.lyrics.isEmpty ?? true)
                    }
                }
            }
            .sheet(isPresented: $showLyrics) {
                LyricsView(song: audioEngine.currentSong, audioEngine: audioEngine)
            }
            .sheet(isPresented: $showAudioInfo) {
                AudioInfoView(audioEngine: audioEngine)
            }
            .sheet(isPresented: $showEqualizer) {
                EqualizerView(audioEngine: audioEngine)
            }
            .sheet(isPresented: $showQueue) {
                QueueView(audioEngine: audioEngine)
            }
        }
    }

    // MARK: - Background View (iOS 16 native design)
    private var backgroundView: some View {
        Group {
            if let artwork = audioEngine.currentSong?.artwork {
                GeometryReader { geometry in
                    ZStack {
                        // Base blurred artwork
                        Image(uiImage: artwork)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .blur(radius: 60)
                            .opacity(0.6)
                            .clipped()

                        // Gradient overlay for depth
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.3),
                                Color.black.opacity(0.5),
                                Color.black.opacity(0.7)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                }
                .ignoresSafeArea()
            } else {
                // Native gradient background for no artwork
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(UIColor.systemBackground),
                            Color(UIColor.secondarySystemBackground)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - Artwork View (Enhanced iOS 16 native design)
    private var artworkView: some View {
        Group {
            if let artwork = audioEngine.currentSong?.artwork {
                ZStack {
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 320, height: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                    // Subtle gradient overlay for depth
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .clear,
                                    .black.opacity(0.05),
                                    .black.opacity(0.1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 12)
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.secondary.opacity(0.25),
                                    Color.secondary.opacity(0.15)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 320, height: 320)
                        .shadow(color: .black.opacity(0.25), radius: 18, x: 0, y: 10)

                    Image(systemName: "music.note")
                        .font(.system(size: 80))
                        .foregroundStyle(.secondary.opacity(0.8))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(.white.opacity(0.15), lineWidth: 1)
                }
            }
        }
    }

    // MARK: - Song Info View (Enhanced audiophile typography)
    private var songInfoView: some View {
        VStack(spacing: 14) {
            Text(audioEngine.currentSong?.displayName ?? "Sin canción")
                .font(.system(size: 26, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)

            Text(audioEngine.currentSong?.displaySubtitle ?? "—")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 20)

            if let album = audioEngine.currentSong?.album, !album.isEmpty {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 20, height: 20)

                        Image(systemName: "opticaldisc")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }

                    Text(album)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Progress View (iOS 16 native design)
    private var progressView: some View {
        VStack(spacing: 12) {
            // Native progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 6)

                    // Progress fill
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width * progress, height: 6)
                }
                .onAppear {
                    progressBarWidth = geometry.size.width
                }
                .onChange(of: geometry.size.width) { newWidth in
                    progressBarWidth = newWidth
                }
            }
            .frame(height: 6)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleScrub(value.location.x)
                    }
            )

            // Time labels with native typography
            HStack {
                Text(formatTime(audioEngine.currentTime))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Spacer()

                Text(formatTime(audioEngine.duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
    
    // MARK: - Handle Scrubbing
    private func handleScrub(_ location: CGFloat) {
        guard progressBarWidth > 0 else { return }
        let percentage = max(0, min(1, location / progressBarWidth))
        let newTime = audioEngine.duration * percentage
        audioEngine.seek(to: newTime)
    }

    // MARK: - Controls View (Enhanced iOS 16 native design)
    private var controlsView: some View {
        HStack(spacing: 32) {
            // Shuffle
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                audioEngine.toggleShuffle()
            } label: {
                ZStack {
                    Circle()
                        .fill(audioEngine.isShuffleEnabled ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
                        .frame(width: 50, height: 50)

                    Image(systemName: audioEngine.isShuffleEnabled ? "shuffle.circle.fill" : "shuffle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(audioEngine.isShuffleEnabled ? Color.accentColor : .secondary)
                }
            }

            // Previous
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                audioEngine.playPrevious()
            } label: {
                ZStack {
                    Circle()
                        .fill(.regularMaterial)
                        .frame(width: 56, height: 56)

                    Image(systemName: "backward.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
            }

            // Play/Pause
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                if audioEngine.isPlaying {
                    audioEngine.pause()
                } else {
                    audioEngine.resume()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 76, height: 76)

                    Image(systemName: audioEngine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .shadow(color: Color.accentColor.opacity(0.5), radius: 16, x: 0, y: 8)
            }

            // Next
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                audioEngine.playNext()
            } label: {
                ZStack {
                    Circle()
                        .fill(.regularMaterial)
                        .frame(width: 56, height: 56)

                    Image(systemName: "forward.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
            }

            // Repeat
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                audioEngine.cycleRepeatMode()
            } label: {
                ZStack {
                    Circle()
                        .fill(audioEngine.repeatMode != .off ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
                        .frame(width: 50, height: 50)

                    Image(systemName: repeatIcon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(audioEngine.repeatMode != .off ? Color.accentColor : .secondary)
                }
            }
        }
    }

    // MARK: - Audiophile Quality Section (Enhanced audio file details)
    private var audiophileQualitySection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                // Format badge
                HStack(spacing: 6) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 32, height: 32)

                        Image(systemName: "waveform")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Formato")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        Text(audioEngine.currentSong?.formatDescription.isEmpty == false ?
                             audioEngine.currentSong!.formatDescription : "Desconocido")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }

                Spacer()

                // Sample rate badge
                HStack(spacing: 6) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.orange.opacity(0.15))
                            .frame(width: 32, height: 32)

                        Image(systemName: "hertz")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.orange)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sample Rate")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        Text("\(Int(audioEngine.sourceSampleRate / 1000)) kHz")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }

                Spacer()

                // Channels badge
                HStack(spacing: 6) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.green.opacity(0.15))
                            .frame(width: 32, height: 32)

                        Image(systemName: "speaker.wave.2")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.green)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Canales")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        Text("\(audioEngine.outputChannelCount)ch")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .enhancedGlass(cornerRadius: 16)

            // Detailed technical info button
            Button {
                showAudioInfo = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentColor)

                    Text("Detalles técnicos completos")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .nativeThinGlass(cornerRadius: 14)
            }
        }
    }

    // MARK: - Queue Button (Enhanced iOS 16 native design)
    private var queueButton: some View {
        Button {
            showQueue = true
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 28, height: 28)

                    Image(systemName: "list.bullet")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }

                Text("Cola: \(audioEngine.nextUpQueue.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .enhancedGlass(cornerRadius: 18)
        }
    }

    private var repeatIcon: String {
        switch audioEngine.repeatMode {
        case .off:
            return "repeat"
        case .all:
            return "repeat.circle.fill"
        case .one:
            return "repeat.1.circle.fill"
        }
    }

    private var audioQualityInfo: String {
        audioEngine.audioQualityInfo.isEmpty ? "\(Int(audioEngine.sourceSampleRate / 1000))kHz · \(audioEngine.outputChannelCount)ch" : audioEngine.audioQualityInfo
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

// MARK: - Audio Info View
struct AudioInfoView: View {
    @ObservedObject var audioEngine: AudioEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: 24) {
                        headerSection

                        VStack(spacing: 20) {
                            audioQualitySection
                            formatInfoSection
                            playbackInfoSection
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Información de Audio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") {
                        dismiss()
                    }
                    .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.18))
                    .frame(width: 75, height: 75)

                Image(systemName: "waveform")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            Text("Calidad de Audio")
                .font(.system(size: 24, weight: .bold))

            Text("Información técnica de la reproducción actual")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .nativeGlass(cornerRadius: 26)
    }

    private var audioQualitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "speaker.wave.2")
                    .foregroundStyle(Color.accentColor)

                Text("Calidad de Salida")
                    .font(.system(size: 18, weight: .semibold))
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                infoRow(title: "Sample Rate", value: "\(Int(audioEngine.outputSampleRate / 1000)) kHz")
                divider
                infoRow(title: "Canales", value: "\(audioEngine.outputChannelCount) canales")
                divider
                infoRow(title: "Sample Rate Fuente", value: "\(Int(audioEngine.sourceSampleRate / 1000)) kHz")
            }
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
        }
    }

    private var formatInfoSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "doc.text")
                    .foregroundStyle(Color.accentColor)

                Text("Formato")
                    .font(.system(size: 18, weight: .semibold))
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                if let song = audioEngine.currentSong {
                    infoRow(title: "Formato", value: song.formatDescription.isEmpty ? "Desconocido" : song.formatDescription)
                    divider
                    infoRow(title: "Duración", value: formatTime(audioEngine.duration))
                    divider
                    infoRow(title: "Álbum", value: song.album.isEmpty ? "Desconocido" : song.album)
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
        }
    }

    private var playbackInfoSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "play.circle")
                    .foregroundStyle(Color.accentColor)

                Text("Reproducción")
                    .font(.system(size: 18, weight: .semibold))
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                infoRow(title: "Estado", value: audioEngine.isPlaying ? "Reproduciendo" : "Pausado")
                divider
                infoRow(title: "Tiempo Actual", value: formatTime(audioEngine.currentTime))
                divider
                infoRow(title: "Tiempo Total", value: formatTime(audioEngine.duration))
            }
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
        }
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
    }

    private var divider: some View {
        Divider()
            .opacity(0.14)
            .padding(.leading, 72)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}
