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

    // MARK: - Adaptive sizing
    private var isCompactScreen: Bool {
        UIScreen.main.bounds.height < 800
    }

    private var artworkSize: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        let maxByWidth = screenWidth - 64
        let maxByHeight = screenHeight * (isCompactScreen ? 0.28 : 0.36)
        return min(280, maxByWidth, maxByHeight)
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

                // Content - fixed layout to prevent aspect ratio issues & overflow on iPhone 8 Plus
                VStack(spacing: 0) {
                    Spacer().frame(height: 12)

                    // Artwork with dynamic glow
                    artworkView
                        .scaleEffect(artworkScale)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: audioEngine.isPlaying)

                    Spacer().frame(height: 20)

                    // Audio visualizer with dynamic color
                    if audioEngine.isPlaying {
                        AudioVisualizer(audioEngine: audioEngine, tintColor: extractedColor)
                            .frame(height: 36)
                            .padding(.horizontal, 40)
                    }

                    Spacer().frame(height: 16)

                    // Song info
                    songInfoView

                    Spacer().frame(height: 16)

                    // Progress bar
                    progressView

                    Spacer().frame(height: 20)

                    // Controls
                    controlsView

                    Spacer().frame(height: 16)

                    // Queue button
                    queueButton

                    Spacer()
                }
                .padding(.horizontal, 24)
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
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 14) {
                        Button {
                            showEqualizer = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .foregroundStyle(.primary)
                                .font(.system(size: 16, weight: .medium))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }

                        Button {
                            showLyrics = true
                        } label: {
                            Image(systemName: audioEngine.currentSong?.lyrics.isEmpty == false ? "quote.bubble.fill" : "quote.bubble")
                                .foregroundStyle(.primary)
                                .font(.system(size: 16, weight: .medium))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
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
    /// `allowsHitTesting(false)` prevents background from intercepting touch gestures.
    /// `scaledToFit` prevents artwork expansion on non-standard aspect ratios.
    private var backgroundView: some View {
        Group {
            if let artwork = audioEngine.currentSong?.artwork {
                GeometryReader { geometry in
                    ZStack {
                        Image(uiImage: artwork)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .blur(radius: 30)
                            .opacity(0.5)

                        extractedColor.opacity(0.15)
                    }
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
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

    // MARK: - Artwork with dynamic glow
    private var artworkView: some View {
        Group {
            if let artwork = audioEngine.currentSong?.artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: artworkSize, height: artworkSize)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: extractedColor.opacity(0.35), radius: 14, x: 0, y: 6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(extractedColor.opacity(0.2), lineWidth: 1)
                    )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
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
                        .font(.system(size: 60, weight: .light))
                        .foregroundStyle(extractedColor.opacity(0.8))
                }
                .shadow(color: extractedColor.opacity(0.25), radius: 12, x: 0, y: 5)
            }
        }
    }

    // MARK: - Song Info
    private var songInfoView: some View {
        VStack(spacing: 8) {
            Text(audioEngine.currentSong?.displayName ?? "Sin canción")
                .font(.system(size: 22, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .lineLimit(2)

            Text(audioEngine.currentSong?.displaySubtitle ?? "—")
                .font(.system(size: 15, weight: .medium))
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
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background {
                    Capsule()
                        .fill(extractedColor.opacity(0.12))
                }
            }
        }
        .padding(.horizontal, 6)
    }

    // MARK: - Progress View with expanded touch area
    private var progressView: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [extractedColor.opacity(0.8), extractedColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
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
            .padding(.vertical, 14) // Expands the hit-test / touch area significantly without changing visual bar height
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

    // MARK: - Controls (Optimized Shuffle & Repeat buttons + expanded touch target)
    private var controlsView: some View {
        HStack(spacing: 16) {
            // Shuffle Button with clean iOS style active pill/capsule design
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                audioEngine.toggleShuffle()
            } label: {
                ZStack {
                    Capsule()
                        .fill(audioEngine.isShuffleEnabled ? extractedColor.opacity(0.2) : Color.clear)
                        .frame(width: 48, height: 38)

                    Image(systemName: audioEngine.isShuffleEnabled ? "shuffle" : "shuffle")
                        .font(.system(size: 17, weight: audioEngine.isShuffleEnabled ? .bold : .semibold))
                        .foregroundStyle(audioEngine.isShuffleEnabled ? extractedColor : .secondary)
                }
                .frame(width: 52, height: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Previous
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                audioEngine.playPrevious()
            } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 50, height: 50)

                    Image(systemName: "backward.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .frame(width: 56, height: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

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
                        .frame(width: 70, height: 70)

                    Image(systemName: audioEngine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                }
                .shadow(color: extractedColor.opacity(0.4), radius: 10, x: 0, y: 4)
                .frame(width: 78, height: 78)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Next
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                audioEngine.playNext()
            } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 50, height: 50)

                    Image(systemName: "forward.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .frame(width: 56, height: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Repeat Button with clean iOS style active pill/capsule design
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                audioEngine.cycleRepeatMode()
            } label: {
                ZStack {
                    Capsule()
                        .fill(audioEngine.repeatMode != .off ? extractedColor.opacity(0.2) : Color.clear)
                        .frame(width: 48, height: 38)

                    Image(systemName: repeatIcon)
                        .font(.system(size: 17, weight: audioEngine.repeatMode != .off ? .bold : .semibold))
                        .foregroundStyle(audioEngine.repeatMode != .off ? extractedColor : .secondary)
                }
                .frame(width: 52, height: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
                        .frame(width: 28, height: 28)

                    Image(systemName: "list.bullet")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(extractedColor)
                }

                Text("Cola: \(audioEngine.nextUpQueue.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.regularMaterial)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers
    private var repeatIcon: String {
        switch audioEngine.repeatMode {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

    private func handleScrub(_ location: CGFloat) {
        guard progressBarWidth > 0 else { return }
        let percentage = max(0, min(1, location / progressBarWidth))
        let newTime = audioEngine.duration * percentage
        audioEngine.seek(to: newTime)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard !time.isNaN && time.isFinite else { return "0:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func extractColorFromArtwork() {
        guard let artwork = audioEngine.currentSong?.artwork else {
            extractedColor = Color.accentColor
            return
        }

        // Fast dominant color extraction using thumbnail context
        DispatchQueue.global(qos: .userInitiated).async {
            let size = CGSize(width: 40, height: 40)
            UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
            artwork.draw(in: CGRect(origin: .zero, size: size))
            let image = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()

            guard let cgImage = image?.cgImage else { return }

            let width = cgImage.width
            let height = cgImage.height
            let bytesPerPixel = 4
            let bytesPerRow = bytesPerPixel * width
            var pixelData = [UInt8](repeating: 0, count: height * bytesPerRow)

            guard let context = CGContext(
                data: &pixelData,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }

            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

            var totalRed: CGFloat = 0
            var totalGreen: CGFloat = 0
            var totalBlue: CGFloat = 0
            var count: CGFloat = 0

            for y in 0..<height {
                for x in 0..<width {
                    let offset = (y * bytesPerRow) + (x * bytesPerPixel)
                    let r = CGFloat(pixelData[offset])
                    let g = CGFloat(pixelData[offset + 1])
                    let b = CGFloat(pixelData[offset + 2])
                    let a = CGFloat(pixelData[offset + 3])

                    if a > 128 {
                        // Exclude pure black / pure white extremes for rich accent colors
                        let maxVal = max(r, g, b)
                        let minVal = min(r, g, b)
                        if maxVal - minVal > 15 && maxVal < 240 {
                            totalRed += r
                            totalGreen += g
                            totalBlue += b
                            count += 1
                        }
                    }
                }
            }

            DispatchQueue.main.async {
                if count > 0 {
                    let avgR = totalRed / count / 255.0
                    let avgG = totalGreen / count / 255.0
                    let avgB = totalBlue / count / 255.0
                    extractedColor = Color(red: Double(avgR), green: Double(avgG), blue: Double(avgB))
                } else {
                    extractedColor = Color.accentColor
                }
            }
        }
    }
}
