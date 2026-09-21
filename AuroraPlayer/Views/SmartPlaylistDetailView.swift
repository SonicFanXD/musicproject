import SwiftUI

/// ✅ DETALLE DE UNA PLAYLIST AUTOMÁTICA (3.0): muestra las canciones que calculó
/// SmartPlaylist en el momento de abrir el sheet. No persiste nada ni modifica
/// las playlists del usuario.
struct SmartPlaylistDetailView: View {
    let playlist: SmartPlaylist
    let songs: [Song]
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var fileAccessService: FileAccessService
    // ✅ Observar el idioma: los textos cambian al instante.
    @ObservedObject private var localization = Localization.shared
    // ✅ 3.0: estadísticas en las filas (se desactivan desde Ajustes).
    @AppStorage("com.aurora.showPlaylistStats") private var showPlaylistStats = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: 18) {
                        headerSection
                        if songs.isEmpty {
                            emptyState
                        } else {
                            songList
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(playlist.name)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.accentGradient)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityLabel(playlist.name)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [playlist.colorHint.opacity(0.9), playlist.colorHint.opacity(0.45)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 128, height: 128)
                    .shadow(color: playlist.colorHint.opacity(0.35), radius: 14, y: 6)

                Image(systemName: playlist.icon)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.94))
            }

            VStack(spacing: 4) {
                Text(playlist.name)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(localizedSongCount(songs.count))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            if !songs.isEmpty {
                Button {
                    Haptics.light()
                    playAll()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text(Localization.localized("smart.playAll"))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background {
                        Capsule().fill(AppTheme.accentGradient)
                    }
                    .shadow(color: AppTheme.accent.opacity(0.35), radius: 10, y: 5)
                }
                .buttonStyle(PressableButtonStyle(scale: 0.96))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Lista

    private var songList: some View {
        LazyVStack(spacing: 0) {
            ForEach(songs) { song in
                songRow(song)
            }
        }
    }

    private func songRow(_ song: Song) -> some View {
        let isCurrent = audioEngine.currentSong?.id == song.id

        return Button {
            Haptics.light()
            audioEngine.play(song: song, from: songs)
        } label: {
            HStack(spacing: 12) {
                artworkView(song)

                VStack(alignment: .leading, spacing: 3) {
                    Text(song.displayName)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(isCurrent ? AppTheme.accent : .primary)
                        .lineLimit(1)

                    Text(song.displaySubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let stats = statsLine(for: song) {
                        Text(stats)
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: isCurrent && audioEngine.isPlaying ? "speaker.wave.2.fill" : "play.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isCurrent ? AppTheme.accent : Color.secondary.opacity(0.6))
                    .frame(width: 30, height: 30)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppTheme.accentGradient(opacity: 0.08))
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(UIColor.secondarySystemBackground).opacity(0.6))
                }
            }
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98))
        .padding(.vertical, 3)
    }

    private func artworkView(_ song: Song) -> some View {
        Group {
            if let image = song.artwork {
                Image(uiImage: AppTheme.thumbnail(from: image, size: CGSize(width: 96, height: 96)))
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.accentGradient(opacity: 0.18))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AppTheme.accentGradient(opacity: 0.6))
                    }
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Estado vacío

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(AppTheme.accentGradient)

            Text(Localization.localized("smart.empty"))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Acciones

    private func playAll() {
        guard let first = songs.first else { return }
        audioEngine.play(song: first, from: songs)
    }

    /// ✅ 3.0: "12 reproducciones · 47 min" SOLO en playlists (aquí y en las del
    /// usuario). La biblioteca y los detalles de álbum/artista no las muestran.
    private func statsLine(for song: Song) -> String? {
        guard showPlaylistStats else { return nil }
        return Localization.playStats(
            plays: fileAccessService.playCount(for: song.id),
            seconds: fileAccessService.playTime(for: song.id)
        )
    }
}
