import SwiftUI

struct NowPlayingView: View {
    @ObservedObject var audioEngine: AudioEngine
    @Environment(\.dismiss) private var dismiss

    @State private var showLyrics = false
    @State private var showAudioInfo = false
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

                    // Audio quality indicator
                    audioQualityButton

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
                    Button {
                        showLyrics = true
                    } label: {
                        Image(systemName: "quote.bubble")
                            .foregroundStyle(.primary)
                    }
                    .disabled(audioEngine.currentSong?.lyrics.isEmpty ?? true)
                }
            }
            .sheet(isPresented: $showLyrics) {
                LyricsView(song: audioEngine.currentSong, audioEngine: audioEngine)
            }
            .sheet(isPresented: $showAudioInfo) {
                AudioInfoView(audioEngine: audioEngine)
            }
        }
    }

    // MARK: - Background View (Modern mesh gradient)
    private var backgroundView: some View {
        Group {
            if let artwork = audioEngine.currentSong?.artwork {
                GeometryReader { geometry in
                    ZStack {
                        // Base blurred artwork with modern gradient
                        Image(uiImage: artwork)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .blur(radius: 45)
                            .opacity(0.5)
                            .clipped()
                        
                        // Gradient overlay for depth
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.2),
                                Color.black.opacity(0.4),
                                Color.black.opacity(0.6)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        
                        // Accent color mesh gradient
                        RadialGradient(
                            colors: [
                                Color.accentColor.opacity(0.15),
                                Color.clear
                            ],
                            center: .bottomLeading,
                            startRadius: 0,
                            endRadius: 400
                        )
                    }
                }
                .ignoresSafeArea()
            } else {
                // Modern gradient background for no artwork
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(UIColor.systemBackground),
                            Color(UIColor.secondarySystemBackground)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    
                    RadialGradient(
                        colors: [
                            Color.accentColor.opacity(0.1),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 300
                    )
                }
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - Artwork View (Modern with glow and glass effect)
    private var artworkView: some View {
        Group {
            if let artwork = audioEngine.currentSong?.artwork {
                ZStack {
                    // Glow effect layers
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 320, height: 320)
                        .blur(radius: 25)
                        .opacity(0.4)
                    
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 320, height: 320)
                        .blur(radius: 15)
                        .opacity(0.6)
                    
                    // Main artwork with glass effect
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 320, height: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .shadow(color: .black.opacity(0.4), radius: 40, x: 0, y: 20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(.white.opacity(0.15), lineWidth: 1)
                        )
                }
            } else {
                ZStack {
                    // Glow effect for placeholder
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 320, height: 320)
                        .blur(radius: 20)
                        .opacity(0.5)
                    
                    // Main placeholder with gradient
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.secondary.opacity(0.3),
                                    Color.secondary.opacity(0.15)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 320, height: 320)
                        .shadow(color: .black.opacity(0.25), radius: 30, x: 0, y: 15)
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(.white.opacity(0.1), lineWidth: 1)
                        )

                    Image(systemName: "music.note")
                        .font(.system(size: 80))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color.secondary.opacity(0.8),
                                    Color.secondary.opacity(0.5)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
        }
    }

    // MARK: - Song Info View (Enhanced with better typography)
    private var songInfoView: some View {
        VStack(spacing: 12) {
            Text(audioEngine.currentSong?.title ?? "Sin canción")
                .font(.system(size: 26, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)

            Text(audioEngine.currentSong?.artist ?? "—")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 20)

            if let album = audioEngine.currentSong?.album, !album.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "opticaldisc")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                    
                    Text(album)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Progress View (Optimized for performance)
    private var progressView: some View {
        VStack(spacing: 12) {
            // Simplified progress bar for better performance
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.secondary.opacity(0.25))
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

            // Time labels
            HStack {
                Text(formatTime(audioEngine.currentTime))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Spacer()

                Text(formatTime(audioEngine.duration))
                    .font(.system(size: 13, weight: .medium))
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

    // MARK: - Controls View (Optimized for performance)
    private var controlsView: some View {
        HStack(spacing: 28) {
            // Shuffle
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                audioEngine.toggleShuffle()
            } label: {
                Image(systemName: audioEngine.isShuffleEnabled ? "shuffle.circle.fill" : "shuffle")
                    .font(.system(size: 22))
                    .foregroundStyle(audioEngine.isShuffleEnabled ? Color.accentColor : .secondary)
                    .frame(width: 44, height: 44)
            }

            // Previous
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                audioEngine.playPrevious()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.primary)
                    .frame(width: 48, height: 48)
            }

            // Play/Pause - simplified for performance
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                if audioEngine.isPlaying {
                    audioEngine.pause()
                } else {
                    audioEngine.resume()
                }
            } label: {
                Image(systemName: audioEngine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 68))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 68, height: 68)
            }

            // Next
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                audioEngine.playNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.primary)
                    .frame(width: 48, height: 48)
            }

            // Repeat
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                audioEngine.cycleRepeatMode()
            } label: {
                Image(systemName: repeatIcon)
                    .font(.system(size: 22))
                    .foregroundStyle(audioEngine.repeatMode != .off ? Color.accentColor : .secondary)
                    .frame(width: 44, height: 44)
            }
        }
    }

    // MARK: - Audio Quality Button (Enhanced)
    private var audioQualityButton: some View {
        Button {
            showAudioInfo = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                
                Text(audioQualityInfo)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    )
            }
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
        let sampleRate = Int(audioEngine.sourceSampleRate / 1000)
        let channels = audioEngine.outputChannelCount
        return "\(sampleRate)kHz · \(channels)ch"
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
        .opaqueGlass(cornerRadius: 26, tint: .accentColor)
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
