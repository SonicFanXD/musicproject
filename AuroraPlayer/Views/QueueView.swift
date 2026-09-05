import SwiftUI

struct QueueView: View {
    @ObservedObject var audioEngine: AudioEngine
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: QueueTab = .nextUp

    enum QueueTab: String, CaseIterable {
        case nextUp = "Siguiente"
        case history = "Historial"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                VStack(spacing: 0) {
                    // Tab selector
                    tabSelector

                    Divider()
                        .background(Color.secondary.opacity(0.2))

                    // Content
                    ScrollView {
                        VStack(spacing: 12) {
                            switch selectedTab {
                            case .nextUp:
                                nextUpContent
                            case .history:
                                historyContent
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(UIColor.systemBackground).opacity(0.92), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                // Título personalizado consistente con la app
                ToolbarItem(placement: .principal) {
                    Text("Cola de Reproducción")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.75)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityLabel("Cola de Reproducción")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") {
                        dismiss()
                    }
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 44, height: 44) // Bigger invisible touch target
                    .contentShape(Rectangle())
                }
            }
        }
    }

    private var tabSelector: some View {
        HStack(spacing: 6) {
            ForEach(QueueTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab == .nextUp ? "list.number" : "clock.arrow.circlepath")
                                .font(.system(size: 12, weight: .semibold))
                            Text(tab.rawValue)
                                .font(.subheadline.weight(selectedTab == tab ? .semibold : .regular))
                        }
                        .foregroundStyle(selectedTab == tab ? .white : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14) // Expanded touch target (10→14)
                    .background {
                        if selectedTab == tab {
                            Capsule()
                                .fill(Color.accentColor)
                                .shadow(color: Color.accentColor.opacity(0.3), radius: 6, x: 0, y: 3)
                        } else {
                            Capsule()
                                .fill(Color.secondary.opacity(0.1))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var nextUpContent: some View {
        // Canción actual destacada
        if let current = audioEngine.currentSong {
            VStack(alignment: .leading, spacing: 8) {
                Text("Reproduciendo ahora")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                HStack(spacing: 12) {
                    // Miniatura con ecualizador animado
                    ZStack {
                        if let artwork = current.artwork {
                            Image(uiImage: artwork)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        } else {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.accentColor.opacity(0.15))
                                .frame(width: 48, height: 48)

                            Image(systemName: "music.note")
                                .font(.system(size: 18))
                                .foregroundStyle(Color.accentColor)
                        }

                        if audioEngine.isPlaying {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.black.opacity(0.35))
                                .frame(width: 48, height: 48)

                            Image(systemName: audioEngine.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                        }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(current.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .lineLimit(1)

                        Text(current.displaySubtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Indicador animado
                    HStack(spacing: 2.5) {
                        ForEach(0..<3, id: \.self) { bar in
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color.accentColor)
                                .frame(width: 3, height: audioEngine.isPlaying ? (bar % 2 == 0 ? 14 : 9) : 6)
                                .animation(
                                    .easeInOut(duration: 0.45 + Double(bar) * 0.12)
                                        .repeatForever(autoreverses: true),
                                    value: audioEngine.isPlaying
                                )
                        }
                    }
                }
                .padding(12)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.accentColor.opacity(0.1))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 1)
                }
            }
        }

        if audioEngine.nextUpQueue.isEmpty {
            emptyState(
                icon: "music.note.list",
                title: "No hay canciones en cola",
                message: "Las próximas canciones aparecerán aquí"
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("A continuación")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                ForEach(Array(audioEngine.nextUpQueue.enumerated()), id: \.element.id) { index, song in
                    queueSongRow(song, index: index + 1)
                }
            }
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var historyContent: some View {
        if audioEngine.playHistory.isEmpty {
            emptyState(
                icon: "clock.arrow.circlepath",
                title: "Sin historial",
                message: "Las canciones reproducidas aparecerán aquí"
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Historial de reproducción")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                ForEach(Array(audioEngine.playHistory.enumerated()), id: \.element.id) { index, song in
                    historySongRow(song, index: index)
                }
            }
        }
    }

    private func queueSongRow(_ song: Song, index: Int) -> some View {
        // Next-up songs are tappable to play immediately in the current queue context
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            audioEngine.play(song: song, from: audioEngine.playbackQueue)
        } label: {
            HStack(spacing: 12) {
                // Miniatura de artwork
                ZStack {
                    if let artwork = song.artwork {
                        Image(uiImage: artwork)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.secondary.opacity(0.15))
                            .frame(width: 44, height: 44)

                        Image(systemName: "music.note")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(song.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(song.displaySubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(formatDuration(song.duration))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .padding(12) // Expanded touch target (10→12)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.regularMaterial)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func historySongRow(_ song: Song, index: Int) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            audioEngine.playFromHistory(song)
        } label: {
            HStack(spacing: 12) {
                // Miniatura con ícono de replay
                ZStack(alignment: .bottomTrailing) {
                    if let artwork = song.artwork {
                        Image(uiImage: artwork)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.secondary.opacity(0.15))
                            .frame(width: 44, height: 44)

                        Image(systemName: "music.note")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                    }

                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background {
                            Circle().fill(Color.accentColor)
                        }
                        .offset(x: 4, y: 4)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(song.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(song.displaySubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "play.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(12) // Expanded touch target (10→12)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.regularMaterial)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.5))

            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}