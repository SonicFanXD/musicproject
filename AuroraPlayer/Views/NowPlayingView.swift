import SwiftUI

struct NowPlayingView: View {
    @ObservedObject var audioEngine: AudioEngine
    @Environment(\.dismiss) private var dismiss

    @State private var showLyrics = false
    @State private var showEqualizer = false
    @State private var showQueue = false
    @State private var artworkScale: CGFloat = 1.0
    @State private var progressBarWidth: CGFloat = 0
    @State private var extractedColor: Color = Color.accentColor
    @State private var dragOffset: CGFloat = 0

    // MARK: - Adaptive sizing
    private var isCompactScreen: Bool {
        UIScreen.main.bounds.height < 800
    }

    private var artworkSize: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        let maxByWidth = screenWidth - 64
        let maxByHeight = screenHeight * (isCompactScreen ? 0.30 : 0.38)
        return min(300, maxByWidth, maxByHeight)
    }

    private var progress: Double {
        guard audioEngine.duration > 0 else { return 0 }
        return min(max(audioEngine.currentTime / audioEngine.duration, 0), 1)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Dynamic background based on artwork
                backgroundView

                // Content
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer().frame(height: 20)

                        // Artwork with dynamic glow
                        artworkView
                            .scaleEffect(artworkScale)
                            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: audioEngine.isPlaying)

                        Spacer().frame(height: 28)

                        // Audio visualizer with dynamic color
                        if audioEngine.isPlaying {
                            AudioVisualizer(audioEngine: audioEngine, tintColor: extractedColor)
                                .frame(height: 40)
                                .padding(.horizontal, 40)
                        }

                        Spacer().frame(height: 24)

                        // Song info
                        songInfoView

                        Spacer().frame(height: 20)

                        // Progress bar
                        progressView

                        Spacer().frame(height: 28)

                        // Controls
                        controlsView

                        Spacer().frame(height: 20)

                        // Queue button
                        queueButton

                        Spacer().frame(height: 30)
                    }
                    .padding(.horizontal, 24)
                }
            }
            .onAppear {
                extractColorFromArtwork()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    artworkScale = 1.0
                }
            }
            .onChange(of: audioEngine.isPlaying) { isPlaying in
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    artworkScale = isPlaying ? 1.03 : 1.0
                }
            }
            .onChange(of: audioEngine.currentSong?.id) { _ in
                extractColorFromArtwork()
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
                            .font(.system(size: 16, weight: .semibold))
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 18) {
                        Button {
                            showEqualizer = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .foregroundStyle(.primary)
                                .font(.system(size: 16, weight: .medium))
                        }

                        Button {
                            showLyrics = true
                        } label: {
                            Image(systemName: audioEngine.currentSong?.lyrics.isEmpty == false ? "quote.bubble.fill" : "quote.bubble")
                                .foregroundStyle(.primary)
                                .font(.system(size: 16, weight: .medium))
                        }
                    }
                }
            }
            .sheet(isPresented: $showLyrics) {
                LyricsView(song: audioEngine.currentSong, audioEngine: audioEngine)
            }
            .sheet(isPresented: $showEqualizer) {
                EqualizerView(audioEngine: audioEngine)
            }
            .sheet(isPresented: $showQueue) {
                QueueView(audioEngine: audioEngine)
            }
        }
    }

    // MARK: - Background with dynamic color
    private var backgroundView: some View {
        Group {
            if let artwork = audioEngine.currentSong?.artwork {
                GeometryReader { geometry in
                    ZStack {
                        Image(uiImage: artwork)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .blur(radius: 60)
                            .opacity(0.5)

                        // Color overlay based on extracted color
                        extractedColor.opacity(0.15)
                    }
                }
                .ignoresSafeArea()
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
            }
        }
    }

    // MARK: - Artwork with dynamic glow
    private var artworkView: some View {
        Group {
            if let artwork = audioEngine.currentSong?.artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: artworkSize, height: artworkSize)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: extractedColor.opacity(0.4), radius: 20, x: 0, y: 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(extractedColor.opacity(0.2), lineWidth: 1)
                    )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    extractedColor.opacity(0.3),
                                    extractedColor.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: artworkSize, height: artworkSize)

                    Image(systemName: "music.note")
                        .font(.system(size: 70, weight: .light))
                        .foregroundStyle(extractedColor.opacity(0.8))
                }
            }
        }
    }

    // MARK: - Song Info
    private var songInfoView: some View {
        VStack(spacing: 10) {
            Text(audioEngine.currentSong?.displayName ?? "Sin canción")
                .font(.system(size: 24, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .lineLimit(2)

            Text(audioEngine.currentSong?.displaySubtitle ?? "—")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 16)

            // Audio quality badge with dynamic color
            if let song = audioEngine.currentSong, !song.audioQualityDescription.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 11, weight: .semibold))

                    Text(song.audioQualityDescription)
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                }
                .foregroundStyle(extractedColor.opacity(0.9))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background {
                    Capsule()
                        .fill(extractedColor.opacity(0.12))
                }
            }
        }
        .padding(.horizontal, 6)
    }

    // MARK: - Progress View
    private var progressView: some View {
        VStack(spacing: 10) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 5)

                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [extractedColor.opacity(0.8), extractedColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * progress, height: 5)
                }
                .onAppear {
                    progressBarWidth = geometry.size.width
                }
                .onChange(of: geometry.size.width) { newWidth in
                    progressBarWidth = newWidth
                }
            }
            .frame(height: 5)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleScrub(value.location.x)
                    }
            )

            HStack {
                Text(formatTime(audioEngine.currentTime))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Spacer()

                Text(formatTime(audioEngine.duration))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Controls
    private var controlsView: some View {
        HStack(spacing: 20) {
            // Shuffle
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                audioEngine.toggleShuffle()
            } label: {
                ZStack {
                    Circle()
                        .fill(audioEngine.isShuffleEnabled ? extractedColor.opacity(0.15) : Color.secondary.opacity(0.08))
                        .frame(width: 44, height: 44)

                    Image(systemName: audioEngine.isShuffleEnabled ? "shuffle.circle.fill" : "shuffle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(audioEngine.isShuffleEnabled ? extractedColor : .secondary)
                }
            }

            // Previous
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                audioEngine.playPrevious()
            } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 52, height: 52)

                    Image(systemName: "backward.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.primary)
                }
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
                        .fill(extractedColor)
                        .frame(width: 72, height: 72)

                    Image(systemName: audioEngine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                }
                .shadow(color: extractedColor.opacity(0.4), radius: 12, x: 0, y: 5)
            }

            // Next
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                audioEngine.playNext()
            } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 52, height: 52)

                    Image(systemName: "forward.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }

            // Repeat
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                audioEngine.cycleRepeatMode()
            } label: {
                ZStack {
                    Circle()
                        .fill(audioEngine.repeatMode != .off ? extractedColor.opacity(0.15) : Color.secondary.opacity(0.08))
                        .frame(width: 44, height: 44)

                    Image(systemName: repeatIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(audioEngine.repeatMode != .off ? extractedColor : .secondary)
                }
            }
        }
    }

    // MARK: - Queue Button
    private var queueButton: some View {
        Button {
            showQueue = true
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(extractedColor.opacity(0.15))
                        .frame(width: 30, height: 30)

                    Image(systemName: "list.bullet")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(extractedColor)
                }

                Text("Cola: \(audioEngine.nextUpQueue.count)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.regularMaterial)
            }
        }
    }

    // MARK: - Helpers
    private var repeatIcon: String {
        switch audioEngine.repeatMode {
        case .off: return "repeat"
        case .all: return "repeat.circle.fill"
        case .one: return "repeat.1.circle.fill"
        }
    }

    private func handleScrub(_ location: CGFloat) {
        guard progressBarWidth > 0 else { return }
        let percentage = max(0, min(1, location / progressBarWidth))
        let newTime = audioEngine.duration * percentage
        audioEngine.seek(to: newTime)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    private func extractColorFromArtwork() {
        guard let artwork = audioEngine.currentSong?.artwork else {
            extractedColor = Color.accentColor
            return
        }

        // Use the existing ColorExtractor from Models.swift
        if let uiColor = ColorExtractor.dominantColor(from: artwork) {
            extractedColor = Color(uiColor)
        } else {
            extractedColor = Color.accentColor
        }
    }
}

// MARK: - Equalizer View
struct EqualizerView: View {
    @ObservedObject var audioEngine: AudioEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: 24) {
                        headerSection

                        VStack(spacing: 16) {
                            ForEach(EQPreset.allCases, id: \.self) { preset in
                                presetButton(preset)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                }
            }
            .navigationTitle("Equalizador")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") { dismiss() }
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

                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            Text("Equalizador")
                .font(.system(size: 24, weight: .bold))

            Text("Ajusta el sonido a tu gusto")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .nativeGlass(cornerRadius: 26)
    }

    private func presetButton(_ preset: EQPreset) -> some View {
        Button {
            audioEngine.setEQPreset(preset)
        } label: {
            HStack {
                Text(preset.displayName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(audioEngine.eqPreset == preset ? .white : .primary)

                Spacer()

                if audioEngine.eqPreset == preset {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(audioEngine.eqPreset == preset ? Color.accentColor : Color.secondary.opacity(0.08))
            }
        }
        .buttonStyle(.plain)
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
                    Button("Listo") { dismiss() }
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