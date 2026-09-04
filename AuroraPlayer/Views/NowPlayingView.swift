import SwiftUI

struct NowPlayingView: View {
    @ObservedObject var audioEngine: AudioEngine
    @Environment(\.dismiss) private var dismiss

    @State private var showLyrics = false
    @State private var showAudioInfo = false

    private var progress: Double {
        guard audioEngine.duration > 0 else { return 0 }
        return min(max(audioEngine.currentTime / audioEngine.duration, 0), 1)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Blurred background
                if let artwork = audioEngine.currentSong?.artwork {
                    GeometryReader { geometry in
                        Image(uiImage: artwork)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .blur(radius: 80)
                            .opacity(0.4)
                            .clipped()
                    }
                    .ignoresSafeArea()
                } else {
                    Color(UIColor.systemBackground)
                        .ignoresSafeArea()
                }

                // Content
                VStack(spacing: 0) {
                    Spacer()

                    // Artwork
                    if let artwork = audioEngine.currentSong?.artwork {
                        Image(uiImage: artwork)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 280, height: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.secondary.opacity(0.2))
                                .frame(width: 280, height: 280)

                            Image(systemName: "music.note")
                                .font(.system(size: 70))
                                .foregroundStyle(.secondary)
                        }
                        .shadow(color: .black.opacity(0.2), radius: 15, x: 0, y: 8)
                    }

                    Spacer().frame(height: 30)

                    // Song info
                    VStack(spacing: 8) {
                        Text(audioEngine.currentSong?.title ?? "Sin canción")
                            .font(.title.bold())
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.primary)

                        Text(audioEngine.currentSong?.artist ?? "—")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    Spacer().frame(height: 20)

                    // Progress
                    VStack(spacing: 8) {
                        ProgressView(value: progress)
                            .progressViewStyle(LinearProgressViewStyle(tint: Color.accentColor))
                            .tint(Color.accentColor)

                        HStack {
                            Text(formatTime(audioEngine.currentTime))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()

                            Spacer()

                            Text(formatTime(audioEngine.duration))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .padding(.horizontal, 20)

                    Spacer().frame(height: 30)

                    // Controls
                    HStack(spacing: 25) {
                        Button {
                            audioEngine.toggleShuffle()
                        } label: {
                            Image(systemName: audioEngine.isShuffleEnabled ? "shuffle.circle.fill" : "shuffle")
                                .font(.title2)
                                .foregroundStyle(audioEngine.isShuffleEnabled ? Color.accentColor : .secondary)
                                .frame(width: 44, height: 44)
                        }

                        Button {
                            audioEngine.playPrevious()
                        } label: {
                            Image(systemName: "backward.fill")
                                .font(.title)
                                .foregroundStyle(.primary)
                                .frame(width: 44, height: 44)
                        }

                        Button {
                            if audioEngine.isPlaying {
                                audioEngine.pause()
                            } else {
                                audioEngine.resume()
                            }
                        } label: {
                            Image(systemName: audioEngine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 64))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 64, height: 64)
                        }

                        Button {
                            audioEngine.playNext()
                        } label: {
                            Image(systemName: "forward.fill")
                                .font(.title)
                                .foregroundStyle(.primary)
                                .frame(width: 44, height: 44)
                        }

                        Button {
                            audioEngine.cycleRepeatMode()
                        } label: {
                            Image(systemName: repeatIcon)
                                .font(.title2)
                                .foregroundStyle(audioEngine.repeatMode != .off ? Color.accentColor : .secondary)
                                .frame(width: 44, height: 44)
                        }
                    }

                    Spacer().frame(height: 30)

                    // Audio info button
                    Button {
                        showAudioInfo = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "waveform")
                                .font(.caption)
                            Text(audioQualityInfo)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.ultraThinMaterial)
                        }
                    }

                    Spacer().frame(height: 20)
                }
                .padding(.horizontal, 20)
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
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showLyrics = true
                    } label: {
                        Image(systemName: "quote.bubble")
                    }
                    .disabled(audioEngine.currentSong?.lyrics.isEmpty ?? true)
                }
            }
            .sheet(isPresented: $showLyrics) {
                LyricsView(song: audioEngine.currentSong)
            }
            .sheet(isPresented: $showAudioInfo) {
                AudioInfoView(audioEngine: audioEngine)
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

// MARK: - Lyrics View
struct LyricsView: View {
    let song: Song?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let lyrics = song?.lyrics, !lyrics.isEmpty {
                            Text(lyrics)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .lineSpacing(8)
                                .padding(20)
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "quote.bubble")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.tertiary)

                                Text("No hay letras disponibles")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.secondary)

                                Text("Esta canción no tiene información de letras en su metadata.")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        }
                    }
                }
            }
            .navigationTitle("Letras")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") {
                        dismiss()
                    }
                }
            }
        }
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
                    VStack(spacing: 20) {
                        headerSection

                        VStack(spacing: 16) {
                            audioQualitySection
                            formatInfoSection
                            playbackInfoSection
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
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
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.16))
                    .frame(width: 70, height: 70)

                Image(systemName: "waveform")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            Text("Calidad de Audio")
                .font(.system(size: 22, weight: .bold))

            Text("Información técnica de la reproducción actual")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .opaqueGlass(cornerRadius: 24, tint: .accentColor)
    }

    private var audioQualitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "speaker.wave.2")
                    .foregroundStyle(Color.accentColor)

                Text("Calidad de Salida")
                    .font(.headline)
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
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            }
        }
    }

    private var formatInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "doc.text")
                    .foregroundStyle(Color.accentColor)

                Text("Formato")
                    .font(.headline)
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
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            }
        }
    }

    private var playbackInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "play.circle")
                    .foregroundStyle(Color.accentColor)

                Text("Reproducción")
                    .font(.headline)
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
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            }
        }
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
    }

    private var divider: some View {
        Divider()
            .opacity(0.12)
            .padding(.leading, 66)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}
