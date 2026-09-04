import SwiftUI

struct NowPlayingView: View {
    @ObservedObject var audioEngine: AudioEngine

    @Environment(\.dismiss) private var dismiss

    @State private var showQueue = false
    @State private var showLyrics = false

    private var progress: Double {
        guard audioEngine.duration > 0 else {
            return 0
        }

        return min(
            max(
                audioEngine.currentTime / audioEngine.duration,
                0
            ),
            1
        )
    }

    var body: some View {
        ZStack {
            background

            ScrollView {
                VStack(spacing: 0) {
                    topBar

                    artwork

                    songInformation

                    progressSection

                    playbackControls

                    secondaryControls

                    Spacer(minLength: 30)
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
        }
        .ignoresSafeArea(edges: .bottom)
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
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height
                        )
                        .blur(radius: 60)
                        .opacity(0.40)
                        .scaleEffect(1.25)

                    LinearGradient(
                        colors: [
                            .black.opacity(0.35),
                            .black.opacity(0.62),
                            .black.opacity(0.94)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .ignoresSafeArea()
            }
        } else {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.35),
                    Color.black.opacity(0.92)
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
                    .font(
                        .system(
                            size: 17,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background {
                        Circle()
                            .fill(.white.opacity(0.12))
                    }
                    .overlay {
                        Circle()
                            .stroke(
                                .white.opacity(0.20),
                                lineWidth: 1
                            )
                    }
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                Text("REPRODUCIENDO")
                    .font(
                        .caption.weight(.bold)
                    )
                    .tracking(1.6)
                    .foregroundStyle(
                        .white.opacity(0.70)
                    )

                if !audioEngine.currentRouteName.isEmpty {
                    Text(audioEngine.currentRouteName)
                        .font(.caption2)
                        .foregroundStyle(
                            .white.opacity(0.45)
                        )
                }
            }

            Spacer()

            Menu {
                Button {
                    showQueue = true
                } label: {
                    Label(
                        "Cola de reproducción",
                        systemImage: "list.bullet"
                    )
                }

                Button {
                    showLyrics = true
                } label: {
                    Label(
                        "Letras",
                        systemImage: "text.quote"
                    )
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(
                        .system(
                            size: 18,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background {
                        Circle()
                            .fill(.white.opacity(0.12))
                    }
                    .overlay {
                        Circle()
                            .stroke(
                                .white.opacity(0.20),
                                lineWidth: 1
                            )
                    }
            }
        }
        .padding(.top, 12)
    }

    // MARK: - Artwork

    private var artwork: some View {
        Group {
            if let image = audioEngine.currentSong?.artwork {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(
                        maxWidth: 350,
                        minHeight: 280,
                        maxHeight: 350
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 26,
                            style: .continuous
                        )
                    )
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: 26,
                            style: .continuous
                        )
                        .stroke(
                            .white.opacity(0.20),
                            lineWidth: 1
                        )
                    }
                    .shadow(
                        color: .black.opacity(0.40),
                        radius: 25,
                        y: 15
                    )
            } else {
                ZStack {
                    RoundedRectangle(
                        cornerRadius: 26,
                        style: .continuous
                    )
                    .fill(.white.opacity(0.10))

                    Image(systemName: "music.note")
                        .font(
                            .system(size: 70)
                        )
                        .foregroundStyle(
                            .white.opacity(0.45)
                        )
                }
                .frame(
                    maxWidth: 350,
                    minHeight: 280,
                    maxHeight: 350
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 26,
                        style: .continuous
                    )
                    .stroke(
                        .white.opacity(0.18),
                        lineWidth: 1
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    // MARK: - Song Information

    private var songInformation: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(
                audioEngine.currentSong?.title
                    ?? "Sin canción"
            )
            .font(
                .system(
                    size: 26,
                    weight: .bold
                )
            )
            .foregroundStyle(.white)
            .lineLimit(2)

            Text(
                audioEngine.currentSong?.artist
                    ?? "—"
            )
            .font(
                .system(
                    size: 17,
                    weight: .medium
                )
            )
            .foregroundStyle(
                .white.opacity(0.65)
            )
            .lineLimit(1)

            if let album = audioEngine.currentSong?.album,
               !album.isEmpty {
                Text(album)
                    .font(.caption)
                    .foregroundStyle(
                        .white.opacity(0.45)
                    )
                    .lineLimit(1)
            }
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .padding(.top, 24)
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(
                            .white.opacity(0.18)
                        )
                        .frame(height: 5)

                    Capsule()
                        .fill(.white)
                        .frame(
                            width: max(
                                4,
                                geometry.size.width * progress
                            ),
                            height: 5
                        )
                }
            }
            .frame(height: 5)

            HStack {
                Text(
                    formatTime(
                        audioEngine.currentTime
                    )
                )
                .font(.caption)
                .foregroundStyle(
                    .white.opacity(0.65)
                )

                Spacer()

                Text(
                    formatTime(
                        audioEngine.duration
                    )
                )
                .font(.caption)
                .foregroundStyle(
                    .white.opacity(0.65)
                )
            }
        }
        .padding(.top, 24)
    }

    // MARK: - Playback Controls

    private var playbackControls: some View {
        HStack {
            Button {
                audioEngine.playPrevious()
            } label: {
                Image(systemName: "backward.fill")
                    .font(
                        .system(
                            size: 23,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(.white)
                    .frame(
                        width: 60,
                        height: 60
                    )
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                if audioEngine.isPlaying {
                    audioEngine.pause()
                } else {
                    audioEngine.resume()
                }
            } label: {
                Image(
                    systemName: audioEngine.isPlaying
                        ? "pause.fill"
                        : "play.fill"
                )
                .font(
                    .system(
                        size: 30,
                        weight: .bold
                    )
                )
                .foregroundStyle(.black)
                .frame(
                    width: 78,
                    height: 78
                )
                .background {
                    Circle()
                        .fill(.white)
                }
                .shadow(
                    color: .black.opacity(0.35),
                    radius: 16,
                    y: 8
                )
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                audioEngine.playNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(
                        .system(
                            size: 23,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(.white)
                    .frame(
                        width: 60,
                        height: 60
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 20)
    }

    // MARK: - Secondary Controls

    private var secondaryControls: some View {
        HStack(spacing: 10) {
            secondaryButton(
                icon: "text.quote",
                title: "Letras"
            ) {
                showLyrics = true
            }

            secondaryButton(
                icon: "list.bullet",
                title: "Cola"
            ) {
                showQueue = true
            }

            secondaryButton(
                icon: audioEngine.isShuffleEnabled
                    ? "shuffle.circle.fill"
                    : "shuffle",
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
        .padding(.top, 28)
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
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(
                        .system(
                            size: 17,
                            weight: .semibold
                        )
                    )

                Text(title)
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(
                active
                    ? Color.accentColor
                    : .white
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
                .fill(
                    active
                        ? Color.accentColor.opacity(0.18)
                        : .white.opacity(0.08)
                )
            }
            .overlay {
                RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
                .stroke(
                    .white.opacity(0.16),
                    lineWidth: 1
                )
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Time

    private func formatTime(
        _ seconds: TimeInterval
    ) -> String {
        guard seconds.isFinite, seconds >= 0 else {
            return "0:00"
        }

        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60

        return String(
            format: "%d:%02d",
            minutes,
            remainingSeconds
        )
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
                    ForEach(
                        audioEngine.playbackQueue
                    ) { song in
                        Button {
                            // ✅ CORREGIDO: ahora usa la etiqueta "song:"
                            audioEngine.play(song: song, from: audioEngine.playbackQueue)
                        } label: {
                            HStack(spacing: 12) {
                                artwork(for: song)

                                VStack(
                                    alignment: .leading,
                                    spacing: 4
                                ) {
                                    Text(song.title)
                                        .font(
                                            .subheadline.weight(
                                                .semibold
                                            )
                                        )
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)

                                    Text(song.artist)
                                        .font(.caption)
                                        .foregroundStyle(
                                            .secondary
                                        )
                                        .lineLimit(1)
                                }

                                Spacer()

                                if audioEngine.currentSong?.id == song.id {
                                    Image(
                                        systemName: "waveform"
                                    )
                                    .foregroundStyle(
                                        .tint
                                    )
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 8)
                            .opaqueGlass(
                                cornerRadius: 14,
                                tint: .white
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(
                            EdgeInsets(
                                top: 4,
                                leading: 12,
                                bottom: 4,
                                trailing: 12
                            )
                        )
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Cola")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .topBarTrailing
                ) {
                    Button("Listo") {
                        dismiss()
                    }
                }
            }
            .toolbarBackground(
                .ultraThinMaterial,
                for: .navigationBar
            )
        }
    }

    @ViewBuilder
    private func artwork(for song: Song) -> some View {
        if let image = song.artwork {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(
                    width: 48,
                    height: 48
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 10,
                        style: .continuous
                    )
                )
        } else {
            ZStack {
                RoundedRectangle(
                    cornerRadius: 10,
                    style: .continuous
                )
                .fill(.thinMaterial)

                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
            }
            .frame(
                width: 48,
                height: 48
            )
        }
    }
}

// MARK: - Lyrics View

struct LyricsView: View {
    @ObservedObject var audioEngine: AudioEngine

    @Environment(\.dismiss) private var dismiss

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
                            .frame(
                                width: 42,
                                height: 42
                            )
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text("LETRAS")
                        .font(
                            .caption.weight(.bold)
                        )
                        .tracking(1.5)
                        .foregroundStyle(
                            .white.opacity(0.65)
                        )

                    Spacer()

                    Color.clear
                        .frame(
                            width: 42,
                            height: 42
                        )
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)

                ScrollView {
                    VStack(spacing: 18) {
                        Text(
                            audioEngine.currentSong?.title
                                ?? "Sin canción"
                        )
                        .font(
                            .system(
                                size: 28,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                        Text(
                            audioEngine.currentSong?.artist
                                ?? "—"
                        )
                        .font(.headline)
                        .foregroundStyle(
                            .white.opacity(0.65)
                        )

                        if let lyrics = audioEngine.currentSong?.lyrics,
                           !lyrics.isEmpty {
                            Text(lyrics)
                                .font(
                                    .system(
                                        size: 20,
                                        weight: .medium
                                    )
                                )
                                .foregroundStyle(.white)
                                .multilineTextAlignment(
                                    .center
                                )
                                .lineSpacing(9)
                                .padding(.horizontal, 12)
                                .padding(.top, 20)
                        } else {
                            VStack(spacing: 12) {
                                Image(
                                    systemName: "text.quote"
                                )
                                .font(
                                    .system(size: 40)
                                )
                                .foregroundStyle(
                                    .white.opacity(0.35)
                                )

                                Text(
                                    "No hay letras disponibles"
                                )
                                .font(.headline)
                                .foregroundStyle(
                                    .white.opacity(0.65)
                                )
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
}