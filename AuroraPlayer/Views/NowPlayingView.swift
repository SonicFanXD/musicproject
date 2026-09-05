import SwiftUI

struct NowPlayingView: View {
    @ObservedObject var audioEngine: AudioEngine
    @Environment(\.dismiss) private var dismiss

    // Configuraciones de personalización
    @AppStorage("com.aurora.showVisualizer") private var showVisualizer = true
    @AppStorage("com.aurora.keepScreenOn") private var keepScreenOn = false
    @AppStorage("com.aurora.dynamicColor") private var dynamicColor = true

    @State private var showLyrics = false
    @State private var showEqualizer = false
    @State private var showQueue = false
    @State private var showQualityDetail = false
    @State private var artworkScale: CGFloat = 1.0
    @State private var progressBarWidth: CGFloat = 0
    @State private var extractedColor: Color = Color.accentColor

    // MARK: - Adaptive sizing for iOS 16 & iPhone 8 Plus
    private var isCompactScreen: Bool {
        UIScreen.main.bounds.height < 800
    }

    private var artworkSize: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        let maxByWidth = screenWidth - 64
        let maxByHeight = screenHeight * (isCompactScreen ? 0.26 : 0.34)
        return min(260, maxByWidth, maxByHeight)
    }

    private var progress: Double {
        guard audioEngine.duration > 0 else { return 0 }
        return min(max(audioEngine.currentTime / audioEngine.duration, 0), 1)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Dynamic background - rendered with optimized drawingGroup for buttery smooth 60fps on iPhone 8 Plus
                backgroundView

                // Content - fixed layout preventing any jank or aspect ratio drift.
                // .fixedSize(horizontal: false, vertical: true) prevents the sheet's
                // drag-to-dismiss gesture from compressing/redesigning the controls.
                VStack(spacing: 0) {
                    Spacer().frame(height: 10)

                    // Artwork with smooth spring animation
                    artworkView
                        .scaleEffect(artworkScale)
                        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: audioEngine.isPlaying)

                    Spacer().frame(height: 16)

                    // Audio visualizer with clean tint color (respeta la configuración del usuario)
                    if audioEngine.isPlaying && showVisualizer {
                        AudioVisualizer(audioEngine: audioEngine, tintColor: extractedColor)
                            .frame(height: 32)
                            .padding(.horizontal, 40)
                    }

                    Spacer().frame(height: 14)

                    // Song info
                    songInfoView

                    Spacer().frame(height: 14)

                    // Progress bar with generous touch area
                    progressView

                    Spacer().frame(height: 18)

                    // Controls
                    controlsView

                    Spacer().frame(height: 14)

                    // Queue button
                    queueButton

                    Spacer()
                }
                .padding(.horizontal, 24)
                .fixedSize(horizontal: false, vertical: true)
            }
            .onAppear {
                extractColorFromArtwork()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    artworkScale = 1.0
                }
                // Mantener pantalla encendida mientras se reproduce (configuración del usuario)
                UIApplication.shared.isIdleTimerDisabled = keepScreenOn && audioEngine.isPlaying
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
            }
            .onChange(of: audioEngine.isPlaying) { isPlaying in
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                    artworkScale = isPlaying ? 1.02 : 1.0
                }
                UIApplication.shared.isIdleTimerDisabled = keepScreenOn && isPlaying
            }
            .onChange(of: audioEngine.currentSong?.id) { _ in
                extractColorFromArtwork()
            }
            .presentationDetents([.large]) // Locks the sheet to full screen — no swipe-drift, no layout shift
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(UIColor.systemBackground).opacity(0.92), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                // Título personalizado consistente con la app
                ToolbarItem(placement: .principal) {
                    Text("Reproduciendo")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [extractedColor, extractedColor.opacity(0.75)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .accessibilityLabel("Reproduciendo")
                }
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
            .sheet(isPresented: $showQualityDetail) {
                AudioQualityDetailView(audioEngine: audioEngine)
                    .presentationDetents([.medium, .large]) // Sheet compacto estilo preview
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Background with hardware acceleration (.drawingGroup)
    private var backgroundView: some View {
        Group {
            if let artwork = audioEngine.currentSong?.artwork {
                GeometryReader { geometry in
                    ZStack {
                        Image(uiImage: artwork)
                            .resizable()
                            .interpolation(.medium) // Medium interpolation is faster than .high on A11
                            .scaledToFit()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .blur(radius: 25)
                            .opacity(0.45)

                        extractedColor.opacity(0.12)
                    }
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .drawingGroup(opaque: false) // Standard color mode — extendedLinear is unnecessary GPU cost on A11
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

    // MARK: - Artwork with GPU optimization
    private var artworkView: some View {
        Group {
            if let artwork = audioEngine.currentSong?.artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .interpolation(.medium) // Medium interpolation ensures zero lag during scale animations on older A11 chips
                    .scaledToFill()
                    .frame(width: artworkSize, height: artworkSize)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: extractedColor.opacity(0.3), radius: 12, x: 0, y: 5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(extractedColor.opacity(0.2), lineWidth: 1)
                    )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
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
                        .font(.system(size: 50, weight: .light))
                        .foregroundStyle(extractedColor.opacity(0.8))
                }
                .shadow(color: extractedColor.opacity(0.2), radius: 10, x: 0, y: 4)
            }
        }
    }

    // MARK: - Song Info
    private var songInfoView: some View {
        VStack(spacing: 6) {
            Text(audioEngine.currentSong?.displayName ?? "Sin canción")
                .font(.system(size: 20, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .lineLimit(2)

            Text(audioEngine.currentSong?.displaySubtitle ?? "—")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 16)

            // Audio quality badge (tappable → abre detalle estilo PowerAmp)
            if let song = audioEngine.currentSong, !song.audioQualityDescription.isEmpty {
                Button {
                    Haptics.light()
                    showQualityDetail = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 10, weight: .semibold))

                        Text(song.audioQualityDescription)
                            .font(.system(size: 10, weight: .medium).monospacedDigit())

                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(extractedColor.opacity(0.6))
                    }
                    .foregroundStyle(extractedColor.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8) // Expanded touch target (invisible)
                    .background {
                        Capsule()
                            .fill(extractedColor.opacity(0.12))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ver detalles de calidad de audio")
            }
        }
        .padding(.horizontal, 6)
    }

    // MARK: - Progress View with expanded touch area
    private var progressView: some View {
        VStack(spacing: 6) {
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
            .padding(.vertical, 18) // Generous touch target expansion (36pt total)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleScrub(value.location.x)
                    }
            )

            HStack {
                Text(formatTime(audioEngine.currentTime))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Spacer()

                Text(formatTime(audioEngine.duration))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Controls (Fixed layout - no redesign on swipe. Expanded touch targets without visual change)
    private var controlsView: some View {
        HStack(spacing: 12) {
            // Shuffle — 64pt invisible touch frame around 46×36 visual capsule
            Button {
                Haptics.light()
                audioEngine.toggleShuffle()
            } label: {
                ZStack {
                    Capsule()
                        .fill(audioEngine.isShuffleEnabled ? extractedColor.opacity(0.2) : Color.clear)
                        .frame(width: 46, height: 36)

                    Image(systemName: "shuffle")
                        .font(.system(size: 16, weight: audioEngine.isShuffleEnabled ? .bold : .semibold))
                        .foregroundStyle(audioEngine.isShuffleEnabled ? extractedColor : .secondary)
                }
                .frame(width: 64, height: 64) // Bigger invisible touch target
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Previous — 64pt invisible touch frame around 48×48 circle
            Button {
                Haptics.light()
                audioEngine.playPrevious()
            } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 48, height: 48)

                    Image(systemName: "backward.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .frame(width: 64, height: 64) // Bigger invisible touch target
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Play/Pause — 84pt invisible touch frame around 66×66 circle
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
                        .fill(extractedColor)
                        .frame(width: 66, height: 66)

                    Image(systemName: audioEngine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                }
                .shadow(color: extractedColor.opacity(0.35), radius: 8, x: 0, y: 3)
                .frame(width: 84, height: 84) // Bigger invisible touch target
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Next — 64pt invisible touch frame around 48×48 circle
            Button {
                Haptics.light()
                audioEngine.playNext()
            } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 48, height: 48)

                    Image(systemName: "forward.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .frame(width: 64, height: 64) // Bigger invisible touch target
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Repeat — 64pt invisible touch frame around 46×36 visual capsule
            Button {
                Haptics.light()
                audioEngine.cycleRepeatMode()
            } label: {
                ZStack {
                    Capsule()
                        .fill(audioEngine.repeatMode != .off ? extractedColor.opacity(0.2) : Color.clear)
                        .frame(width: 46, height: 36)

                    Image(systemName: repeatIcon)
                        .font(.system(size: 16, weight: audioEngine.repeatMode != .off ? .bold : .semibold))
                        .foregroundStyle(audioEngine.repeatMode != .off ? extractedColor : .secondary)
                }
                .frame(width: 64, height: 64) // Bigger invisible touch target
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        // Use fixed ideal size so the row can never be squeezed by sheet dragging
        .frame(maxWidth: .infinity)
        .fixedSize()
    }

    // MARK: - Queue Button
    private var queueButton: some View {
        Button {
            showQueue = true
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(extractedColor.opacity(0.15))
                        .frame(width: 26, height: 26)

                    Image(systemName: "list.bullet")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(extractedColor)
                }

                Text("Cola: \(audioEngine.nextUpQueue.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 6) // Invisible expansion for bigger tap area (44pt+ min)
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

        // Fast dominant color extraction using lightweight thumbnail context
        DispatchQueue.global(qos: .userInitiated).async {
            let size = CGSize(width: 32, height: 32)
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