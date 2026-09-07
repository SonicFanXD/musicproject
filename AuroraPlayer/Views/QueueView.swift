import SwiftUI
import UIKit

struct QueueView: View {
    @ObservedObject var audioEngine: AudioEngine
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: QueueTab = .nextUp
    // ✅ Estado local editable de la cola "Siguiente" para reordenar/eliminar
    @State private var editableQueue: [Song] = []

    enum QueueTab: String, CaseIterable {
        case nextUp
        case history

        var localizedTitle: String {
            switch self {
            case .nextUp: return Localization.localized("queue.nextUp")
            case .history: return Localization.localized("queue.history")
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                VStack(spacing: 0) {
                    tabSelector

                    Divider().background(Color.secondary.opacity(0.2))

                    ScrollView {
                        VStack(spacing: 12) {
                            switch selectedTab {
                            case .nextUp: nextUpContent
                            case .history: historyContent
                            }
                        }
                        .padding(.horizontal, 16).padding(.top, 16)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            Text(Localization.localized("queue.title"))
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [AppTheme.accent, AppTheme.accent.opacity(0.75)],
                                        startPoint: .leading, endPoint: .trailing
                                    )
                                )
                                .lineLimit(1).minimumScaleFactor(0.7)
                                .accessibilityLabel(Localization.localized("queue.title"))
                        }

                        ToolbarItem(placement: .topBarTrailing) {
                            HStack(spacing: 8) {
                                if selectedTab == .nextUp && editableQueue.count > 1 {
                                    Button {
                                        Haptics.light()
                                        clearQueue()
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(.red)
                                            .frame(width: 44, height: 44)
                                            .contentShape(Rectangle())
                                    }
                                }
                                Button(Localization.localized("actions.done")) { dismiss() }
                                    .foregroundStyle(AppTheme.accent)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                        }
                    }
                    .onAppear {
                        editableQueue = audioEngine.nextUpQueue
                    }
                    .onChange(of: audioEngine.nextUpQueue) { newQueue in
                        // Sincronizar solo si no estamos editando activamente
                        if editableQueue.map(\.id) != newQueue.map(\.id) {
                            editableQueue = newQueue
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
                        Text(tab.localizedTitle)
                            .font(.system(size: 14, weight: selectedTab == tab ? .semibold : .medium, design: .rounded))
                    }
                    .foregroundStyle(selectedTab == tab ? .white : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background {
                        if selectedTab == tab {
                            Capsule().fill(AppTheme.accent)
                                .shadow(color: AppTheme.accent.opacity(0.3), radius: 6, x: 0, y: 3)
                        } else {
                            // ✅ 60fps: color OPACO (sin blur) para el selector
                            Capsule().fill(Color(UIColor.secondarySystemBackground))
                        }
                    }
                }
                .buttonStyle(PressableButtonStyle(scale: 0.95))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    @ViewBuilder
    private var nextUpContent: some View {
        if let current = audioEngine.currentSong {
            VStack(alignment: .leading, spacing: 8) {
                Text(Localization.localized("queue.nowPlaying"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                HStack(spacing: 12) {
                    artworkMiniature(current.artwork, size: 48, corner: 10)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(current.title)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.accent).lineLimit(1)
                        Text(current.displaySubtitle)
                            .font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                    }

                    Spacer()

                    HStack(spacing: 2.5) {
                        ForEach(0..<3, id: \.self) { bar in
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(AppTheme.accent)
                                .frame(width: 3, height: audioEngine.isPlaying ? (bar % 2 == 0 ? 14 : 9) : 6)
                                .animation(
                                    .easeInOut(duration: 0.45 + Double(bar) * 0.12).repeatForever(autoreverses: true),
                                    value: audioEngine.isPlaying
                                )
                        }
                    }
                }
                .padding(12)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AppTheme.accent.opacity(0.1))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(AppTheme.accent.opacity(0.25), lineWidth: 1)
                }
            }
        }

        if editableQueue.isEmpty {
            emptyState(icon: "music.note.list", title: Localization.localized("queue.emptyQueue"), message: Localization.localized("queue.emptyQueueMessage"))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(Localization.localized("queue.upNext"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                // ✅ Lista editable: reordenar y eliminar con swipe
                ForEach(Array(editableQueue.enumerated()), id: \.element.id) { index, song in
                    queueSongRow(song, index: index + 1)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Haptics.light()
                                removeFromQueue(song)
                            } label: {
                                Label(Localization.localized("queue.remove"), systemImage: "trash")
                            }
                        }
                }
                .onMove { from, to in
                    Haptics.light()
                    moveQueueItem(from: from, to: to)
                }
            }
            .padding(.top, 8)
        }
    }

    // ✅ Acciones de la cola editable
    private func removeFromQueue(_ song: Song) {
        guard let idx = editableQueue.firstIndex(where: { $0.id == song.id }) else { return }
        editableQueue.remove(at: idx)
        audioEngine.removeFromNextUpQueue(song)
    }

    private func moveQueueItem(from source: IndexSet, to destination: Int) {
        editableQueue.move(fromOffsets: source, toOffset: destination)
        audioEngine.reorderNextUpQueue(editableQueue)
    }

    private func clearQueue() {
        editableQueue.removeAll()
        audioEngine.clearNextUpQueue()
    }

    @ViewBuilder
    private var historyContent: some View {
        if audioEngine.playHistory.isEmpty {
            emptyState(icon: "clock.arrow.circlepath", title: Localization.localized("queue.emptyHistory"), message: Localization.localized("queue.emptyQueueMessage"))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(Localization.localized("queue.historyTitle"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                ForEach(Array(audioEngine.playHistory.enumerated()), id: \.element.id) { index, song in
                    historySongRow(song, index: index)
                }
            }
        }
    }

    private func queueSongRow(_ song: Song, index: Int) -> some View {
        Button {
            Haptics.light()
            audioEngine.play(song: song, from: audioEngine.playbackQueue)
        } label: {
            HStack(spacing: 14) {
                artworkMiniature(song.artwork, size: 48, corner: 12)

                VStack(alignment: .leading, spacing: 4) {
                    Text(song.title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary).lineLimit(1)
                    Text(song.displaySubtitle)
                        .font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                }

                Spacer()

                Text(formatDuration(song.duration))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(UIColor.secondarySystemBackground).opacity(0.6))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98))
    }

    private func historySongRow(_ song: Song, index: Int) -> some View {
        Button {
            Haptics.light()
            audioEngine.playFromHistory(song)
        } label: {
            HStack(spacing: 14) {
                artworkMiniature(song.artwork, size: 48, corner: 12)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(4)
                            .background {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [AppTheme.accent, AppTheme.accent.opacity(0.85)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing
                                        )
                                    )
                            }
                            .offset(x: 4, y: 4)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(song.title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary).lineLimit(1)
                    Text(song.displaySubtitle)
                        .font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                }

                Spacer()

                Image(systemName: "play.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(AppTheme.accent)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(UIColor.secondarySystemBackground).opacity(0.6))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98))
    }

    // ✅ Componente reutilizable para miniaturas de artwork
    @ViewBuilder
    private func artworkMiniature(_ artwork: UIImage?, size: CGFloat, corner: CGFloat) -> some View {
        if let artwork = artwork {
            Image(uiImage: artwork)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        } else {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.32))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
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
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}