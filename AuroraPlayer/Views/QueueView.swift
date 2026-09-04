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
            .navigationTitle("Cola de Reproducción")
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

    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(QueueTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 15, weight: selectedTab == tab ? .semibold : .regular))
                        .foregroundStyle(selectedTab == tab ? Color.accentColor : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background {
                            if selectedTab == tab {
                                RoundedRectangle(cornerRadius: 0, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.1))
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .background {
            Color.secondary.opacity(0.05)
        }
    }

    @ViewBuilder
    private var nextUpContent: some View {
        if audioEngine.nextUpQueue.isEmpty {
            emptyState(
                icon: "music.note.list",
                title: "No hay canciones en cola",
                message: "Las próximas canciones aparecerán aquí"
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Próximas \(audioEngine.nextUpQueue.count) canciones")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                ForEach(Array(audioEngine.nextUpQueue.enumerated()), id: \.element.id) { index, song in
                    queueSongRow(song, index: index + 1)
                }
            }
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
        HStack(spacing: 12) {
            Text("\(index)")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .center)

            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(song.artist)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(formatDuration(song.duration))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }

    private func historySongRow(_ song: Song, index: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "clock")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .center)

            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(song.artist)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                audioEngine.playFromHistory(song)
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        }
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