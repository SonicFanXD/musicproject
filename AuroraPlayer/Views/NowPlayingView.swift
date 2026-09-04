import SwiftUI

struct NowPlayingView: View {
    @ObservedObject var audioEngine: AudioEngine
    @Environment(\.dismiss) private var dismiss
    @State private var showQueue = false
    @State private var showLyrics = false

    private var progress: Double {
        guard audioEngine.duration > 0 else { return 0 }
        return min(max(audioEngine.currentTime / audioEngine.duration, 0), 1)
    }

    private var isBitPerfect: Bool {
        audioEngine.sourceSampleRate > 0
            && audioEngine.outputSampleRate > 0
            && abs(audioEngine.sourceSampleRate - audioEngine.outputSampleRate) < 1
    }

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.height < 760
            let artworkSide = min(
                proxy.size.width - 64,
                proxy.size.height * (isCompact ? 0.30 : 0.38)
            )

            ZStack {
                background

                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 6)
                    artwork(side: artworkSide)
                    Spacer(minLength: isCompact ? 12 : 20)
                    songInformation
                    Spacer(minLength: isCompact ? 12 : 18)
                    progressSection
                    Spacer(minLength: isCompact ? 10 : 16)
                    qualitySection
                    Spacer(minLength: isCompact ? 14 : 22)
                    playbackControls
                    Spacer(minLength: isCompact ? 12 : 20)
                    secondaryControls
                    Spacer(minLength: 4)
                }
                .padding(.horizontal, 20)
            }
        }
        .sheet(isPresented: $showQueue) {
            QueueView(audioEngine: audioEngine)
        }
        .sheet(isPresented: $showLyrics) {
            LyricsView(audioEngine: audioEngine)
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var background: some View {
        if let artwork = audioEngine.currentSong?.artwork {
            GeometryReader { geometry in
                ZStack {
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .blur(radius: 60)
                        .opacity(0.34)
                        .scaleEffect(1.25)

                    LinearGradient(
                        colors: [
                            .black.opacity(0.32),
                            .black.opacity(0.58),
                            .black.opacity(0.92)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .ignoresSafeArea()
            }
            .id(audioEngine.currentSong?.id)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.5), value: audioEngine.currentSong?.id)
        } else {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.32),
                    Color.black.opacity(0.90)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background {
                        Circle().fill(.white.opacity(0.10))
                    }
                    .overlay {
                        Circle().stroke(.white.opacity(0.18), lineWidth: 1)
                    }
            }
            .buttonStyle(GlassPressButtonStyle())

            Spacer()

            VStack(spacing: 2) {
                Text("REPRODUCIENDO")
                    .font(.caption2.weight(.bold))
                    .tracking(1.6)
                    .foregroundStyle(.white.opacity(0.65))

                if !audioEngine.currentRouteName.isEmpty {
                    Text(audioEngine.currentRouteName)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.42))
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: audioEngine.currentRouteName)

            Spacer()

            Menu {
                Button {
                    showQueue = true
                } label: {
                    Label("Cola de reproducción", systemImage: "list.bullet")
                }

                Button {
                    showLyrics = true
                } label: {
                    Label("Letras", systemImage: "text.quote")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background {
                        Circle().fill(.white.opacity(0.10))
                    }
                    .overlay {
                        Circle().stroke(.white.opacity(0.18), lineWidth: 1)
                    }
            }
            .buttonStyle(GlassPressButtonStyle())
        }
        .padding(.top, 10)
    }

    // MARK: - Artwork

    private func artwork(side: CGFloat) -> some View {
        Group {
            if let image = audioEngine.currentSong?.artwork {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(.white.opacity(0.18), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.35), radius: 20, y: 12)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.white.opacity(0.08))

                    Image(systemName: "music.note")
                        .font(.system(size: side * 0.28))
                        .foregroundStyle(.white.opacity(0.42))
                }
                .frame(width: side, height: side)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .id(audioEngine.currentSong?.id)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .animation(.spring(response: 0.42, dampingFraction: 0.85), value: audioEngine.currentSong?.id)
    }

    // MARK: - Song Information

    private var songInformation: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(audioEngine.currentSong?.title ?? "Sin canción")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)

            Text(audioEngine.currentSong?.artist ?? "—")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)

            if let album = audioEngine.currentSong?.album, !album.isEmpty {
                Text(album)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(audioEngine.currentSong?.id)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .animation(.easeOut(duration: 0.3), value: audioEngine.currentSong?.id)
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(spacing: 7) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.16))
                        .frame(height: 5)

                    Capsule()
                        .fill(.white)
                        .frame(width: max(4, geometry.size.width * progress), height: 5)
                        .animation(.linear(duration: 0.4), value: progress)
                }
            }
            .frame(height: 5)

            HStack {
                Text(formatTime(audioEngine.currentTime))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))
                    .monospacedDigit()

                Spacer()

                Text(formatTime(audioEngine.duration))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Quality

    private var qualitySection: some View {
        HStack(spacing: 8) {
            if let format = audioEngine.currentSong?.formatDescription, !format.isEmpty {
                qualityChip(icon: "waveform", text: format, tint: .white)
            }

            if audioEngine.currentSong != nil {
                if isBitPerfect {
                    qualityChip(icon: "checkmark.seal.fill", text: "Bit perfecto", tint: .green)
                } else if audioEngine.outputSampleRate > 0 {
                    qualityChip(
                        icon: "arrow.triangle.2.circlepath",
                        text: "Salida \(Int(audioEngine.outputSampleRate / 1000)) kHz",
                        tint: .orange
                    )
                }
            }

            Spacer(minLength: 0)
        }
        .animation(.easeInOut(duration: 0.2), value: isBitPerfect)
        .transition(.opacity)
    }

    private func qualityChip(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
            Text(text)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint == .white ? .white.opacity(0.82) : tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            Capsule().fill(.white.opacity(0.09))
        }
        .overlay {
            Capsule().stroke(.white.opacity(0.15), lineWidth: 1)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    // MARK: - Playback Controls

    private var playbackControls: some View {
        HStack {
            Button {
                audioEngine.playPrevious()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
            }
            .buttonStyle(GlassPressButtonStyle())

            Spacer()

            Button {
                if audioEngine.isPlaying {
                    audioEngine.pause()
                } else {
                    audioEngine.resume()
                }
            } label: {
                Image(systemName: audioEngine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 72, height: 72)
                    .background {
                        Circle().fill(.white)
                    }
                    .shadow(color: .black.opacity(0.28), radius: 14, y: 7)
            }
            .buttonStyle(.plain)
            .scaleEffect(audioEngine.isPlaying ? 1.0 : 0.94)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: audioEngine.isPlaying)

            Spacer()

            Button {
                audioEngine.playNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
            }
            .buttonStyle(GlassPressButtonStyle())
        }
    }

    // MARK: - Secondary Controls

    private var secondaryControls: some View {
        HStack(spacing: 10) {
            secondaryButton(icon: "text.quote", title: "Letras") {
                showLyrics = true
            }

            secondaryButton(icon: "list.bullet", title: "Cola") {
                showQueue = true
            }

            secondaryButton(
                icon: audioEngine.isShuffleEnabled ? "shuffle.circle.fill" : "shuffle",
                title: "Aleatorio",
                active: audioEngine.isShuffleEnabled
            ) {
                audioEngine.toggleShuffle()
            }

            secondaryButton(
                icon: repeatIcon,
                title: "Repetir",
                active: audioEngine.repeatMode != .off
            ) {
                audioEngine.cycleRepeatMode()
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

    private func secondaryButton(
        icon: String,
        title: String,
        active: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))

                Text(title)
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(active ? Color.accentColor : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(active ? Color.accentColor.opacity(0.16) : .white.opacity(0.07))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            }
            .animation(.easeInOut(duration: 0.2), value: active)
        }
        .buttonStyle(GlassPressButtonStyle())
    }

    // MARK: - Time

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

// MARK: - Queue View

struct QueueView: View {
    @ObservedObject var audioEngine: AudioEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                List {
                    ForEach(Array(audioEngine.playbackQueue.enumerated()), id: \.element.id) { index, song in
                        Button {
                            audioEngine.play(song: song, from: audioEngine.playbackQueue)
                        } label: {
                            HStack(spacing: 12) {
                                artwork(for: song)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(song.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)

                                    Text(song.artist)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                if audioEngine.currentSong?.id == song.id {
                                    Image(systemName: "waveform")
                                        .foregroundStyle(.tint)
                                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 8)
                            .opaqueGlass(cornerRadius: 14, tint: .white)
                            .animation(.easeInOut(duration: 0.2), value: audioEngine.currentSong?.id)
                        }
                        .buttonStyle(RowPressButtonStyle())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        .rowAppear(index: index)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Cola")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") {
                        dismiss()
                    }
                }
            }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        }
    }

    @ViewBuilder
    private func artwork(for song: Song) -> some View {
        if let image = song.artwork {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.thinMaterial)

                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
            }
            .frame(width: 48, height: 48)
        }
    }
}

// MARK: - Lyrics View

struct LyricsView: View {
    @ObservedObject var audioEngine: AudioEngine
    @Environment(\.dismiss) private var dismiss

    @State private var displayedLyrics: String = ""
    @State private var currentWordIndex: Int = 0
    @State private var fullLyrics: String = ""
    @State private var words: [String] = []
    @State private var timer: Timer? = nil

    var body: some View {
        ZStack {
            if let artwork = audioEngine.currentSong?.artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .blur(radius: 55)
                    .opacity(0.35)

                Color.black
                    .opacity(0.74)
                    .ignoresSafeArea()
            } else {
                Color.black
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                    }
                    .buttonStyle(GlassPressButtonStyle())

                    Spacer()

                    Text("LETRAS")
                        .font(.caption.weight(.bold))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.65))

                    Spacer()

                    Color.clear
                        .frame(width: 42, height: 42)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)

                ScrollView {
                    VStack(spacing: 18) {
                        Text(audioEngine.currentSong?.title ?? "Sin canción")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)

                        Text(audioEngine.currentSong?.artist ?? "—")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.65))

                        if let lyrics = audioEngine.currentSong?.lyrics, !lyrics.isEmpty {
                            Text(displayedLyrics)
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .lineSpacing(9)
                                .padding(.horizontal, 12)
                                .padding(.top, 20)
                                .animation(.easeOut(duration: 0.12), value: displayedLyrics)
                                .onAppear {
                                    fullLyrics = lyrics
                                    words = lyrics.components(separatedBy: " ")
                                    displayedLyrics = ""
                                    currentWordIndex = 0
                                    startWordAnimation()
                                }
                                .onDisappear {
                                    stopWordAnimation()
                                }
                                .onChange(of: audioEngine.currentSong?.id) { _ in
                                    if let newLyrics = audioEngine.currentSong?.lyrics, !newLyrics.isEmpty {
                                        fullLyrics = newLyrics
                                        words = newLyrics.components(separatedBy: " ")
                                        displayedLyrics = ""
                                        currentWordIndex = 0
                                        startWordAnimation()
                                    } else {
                                        displayedLyrics = ""
                                        stopWordAnimation()
                                    }
                                }
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "text.quote")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.white.opacity(0.35))

                                Text("No hay letras disponibles")
                                    .font(.headline)
                                    .foregroundStyle(.white.opacity(0.65))
                            }
                            .padding(.top, 80)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 30)
                }
            }
        }
    }

    // MARK: - Word-by-word animation

    private func startWordAnimation() {
        stopWordAnimation()
        displayedLyrics = ""
        currentWordIndex = 0

        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
            if currentWordIndex < words.count {
                let word = words[currentWordIndex]
                if currentWordIndex > 0 {
                    displayedLyrics += " "
                }
                displayedLyrics += word
                currentWordIndex += 1
            } else {
                stopWordAnimation()
            }
        }
    }

    private func stopWordAnimation() {
        timer?.invalidate()
        timer = nil
    }
}