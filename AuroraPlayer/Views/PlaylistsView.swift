import SwiftUI

struct PlaylistsView: View {
    @ObservedObject var fileAccessService: FileAccessService
    @ObservedObject var audioEngine: AudioEngine
    @M3EDismiss private var dismiss

    @State private var showCreatePlaylist = false
    @State private var newPlaylistName = ""
    @State private var newPlaylistDescription = ""
    /// ✅ M3E: detalle como pantalla completa (sin NavigationStack).
    @State private var selectedPlaylist: Playlist? = nil

    var body: some View {
        ZStack {
            AppBackground()

                VStack(spacing: 0) {
                    // ✅ AURORA DESIGN: header de sheet del sistema (primer uso en el
                    // proyecto): fila fija de 44pt con chevron.down para cerrar, título
                    // centrado y slot trailing, en vez del toolbar con título + borde.
                    // Mide exactamente lo que medía la barra a la que sustituye, así
                    // que el contenido de abajo no se mueve ni cambia su spacing.
                    M3ENavigationBar(
                        title: Localization.localized("playlists.title"),
                        leading: {
                            Button { dismiss() } label: {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel(Localization.localized("design.close"))
                        },
                        trailing: { headerCreateButton }
                    )

                    ScrollView {
                        VStack(spacing: 20) {
                            headerSection

                            if fileAccessService.playlists.isEmpty {
                                emptyPlaylistsState
                            } else {
                                playlistsGrid
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        .m3eScreen(item: $selectedPlaylist) { playlist in
            PlaylistDetailView(
                playlist: playlist,
                fileAccessService: fileAccessService,
                audioEngine: audioEngine
            )
        }
        .fullScreenCover(isPresented: $showCreatePlaylist) {
            createPlaylistSheet
        }
    }

    /// ✅ AURORA DESIGN: el "+" que antes vivía en el toolbar, ahora en el slot
    /// trailing del header. Es el MISMO botón y mide 44pt, lo mismo que el hueco
    /// fantasma del header, así que el título sigue perfectamente centrado.
    private var headerCreateButton: some View {
        Button {
            showCreatePlaylist = true
        } label: {
            Image(systemName: "plus")
                .foregroundStyle(AppTheme.accentGradient)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
    }

    // MARK: - Header Section (diseño premium estilo NowPlayingView)
    private var headerSection: some View {
        VStack(spacing: 16) {
            ZStack {
                // ✅ FASE 3 (M3E): superficie SÓLIDA, sin vidrio. Mismo Shape y
                // mismo tamaño; el borde de acento conserva la jerarquía
                // tonal que antes daba el material.
                Circle()
                    .fill(M3EColor.surfaceContainerHigh)
                    .frame(width: 88, height: 88)
                    .overlay {
                        Circle()
                            .stroke(AppTheme.accentGradient, lineWidth: 2)
                    }
                    .shadow(color: AppTheme.accent.opacity(0.15), radius: 12, y: 6)

                Image(systemName: "music.note.list")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(AppTheme.accentGradient)
            }

            Text(Localization.localized("playlists.yourPlaylists"))
                // ✅ REMAKE: `headlineSmallEmphasized` del catálogo M3E.
                .font(M3ETypography.headlineSmallEmphasized)
                .tracking(-0.6)

            Text(Localization.localized("playlists.subtitle"))
                .font(M3ETypography.bodyLarge)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .enhancedGlass(cornerRadius: 28)
    }

    // MARK: - Empty State
    private var emptyPlaylistsState: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text(Localization.localized("playlists.empty"))
                .font(M3ETypography.titleMediumEmphasized)
                .foregroundStyle(.secondary)

            Text(Localization.localized("playlists.emptySubtitle2"))
                .font(M3ETypography.bodyMedium)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Playlists Grid
    private var playlistsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16)
        ], spacing: 20) {
            ForEach(fileAccessService.playlists) { playlist in
                Button {
                    Haptics.light()
                    selectedPlaylist = playlist
                } label: {
                    playlistCard(playlist)
                }
                .buttonStyle(PressableButtonStyle(scale: AuroraPressScale.chip))
            }
        }
    }

    // MARK: - Playlist Card
    private func playlistCard(_ playlist: Playlist) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Playlist artwork
            ZStack {
                if let artwork = playlist.artwork {
                    // ✅ ANTI-JETSAM: card de 150pt → basta thumbnail de 300px.
                    Image(uiImage: AppTheme.thumbnail(from: artwork, size: CGSize(width: 300, height: 300)))
                        .resizable()
                        .scaledToFill()
                        .frame(width: 150, height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            // ✅ Mismo acento de dos colores que la card de la
                            // biblioteca (antes era un solo color con opacidad).
                            .fill(AppTheme.accentGradient(opacity: 0.3))
                            .frame(width: 150, height: 150)

                        Image(systemName: "music.note.list")
                            .font(.system(size: 40))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }

                // Song count badge
                VStack {
                    HStack {
                        Spacer()

                        ZStack {
                            // ✅ 60fps: fondo OPACO (no material blur) — el grid de
                            // playlists puede tener varias tarjetas con blur simultáneo
                            Circle()
                                .fill(M3EColor.surfaceContainerHigh.opacity(0.8))
                                .frame(width: 32, height: 32)

                            Text("\(playlist.songIDs.count)")
                                .font(M3ETypography.labelMedium)
                                .foregroundStyle(.primary)
                        }
                    }
                    Spacer()
                }
                .padding(12)
            }

            // Playlist info
            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(M3ETypography.titleMediumEmphasized)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if !playlist.description.isEmpty {
                    Text(playlist.description)
                        .font(M3ETypography.bodyMedium)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(localizedSongCount(playlist.songIDs.count))
                    .font(M3ETypography.labelMedium)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 150)
    }

    // MARK: - Create Playlist Sheet
    private var createPlaylistSheet: some View {
        ZStack {
            AppBackground()

                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(Localization.localized("playlists.name"))
                                    .font(M3ETypography.labelLargeEmphasized)
                                    .foregroundStyle(.secondary)

                                TextField(Localization.localized("playlists.placeholderName"), text: $newPlaylistName)
                                    .textFieldStyle(.plain)
                                    .padding(.horizontal, 14)
                                    .frame(height: 48)
                                    .background(
                                        M3EColor.surfaceContainerHigh,
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    )
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text(Localization.localized("playlists.descriptionOptional"))
                                    .font(M3ETypography.labelLargeEmphasized)
                                    .foregroundStyle(.secondary)

                                TextField(Localization.localized("playlists.placeholderDescription"), text: $newPlaylistDescription)
                                    .textFieldStyle(.plain)
                                    .padding(.horizontal, 14)
                                    .frame(height: 48)
                                    .background(
                                        M3EColor.surfaceContainerHigh,
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    )
                            }
                        }
                        .padding(.horizontal, 4)

                        M3EFilledButton(action: createPlaylist) {
                            HStack(spacing: 10) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 18, weight: .semibold))

                                Text(Localization.localized("playlists.createPlaylist"))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .disabled(newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                }
                .scrollIndicators(.hidden)
            }
            // ✅ M3E: cabecera propia del diálogo a pantalla completa (sin
            // NavigationStack ni toolbar del sistema).
            .safeAreaInset(edge: .top, spacing: 0) {
                M3ENavigationBar(
                    title: Localization.localized("playlists.newPlaylist"),
                    leading: {
                        Button { showCreatePlaylist = false } label: {
                            Image(systemName: "close")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(M3EColor.onSurfaceVariant)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel(Localization.localized("design.close"))
                    },
                    trailing: {
                        Button(Localization.localized("actions.done")) {
                            createPlaylist()
                        }
                        .font(M3ETypography.labelLargeEmphasized)
                        .foregroundStyle(
                            newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? M3EColor.onSurfaceVariant
                                : M3EColor.primary
                        )
                        .disabled(newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .frame(height: 44)
                    }
                )
            }
    }

    private func createPlaylist() {
        let name = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = newPlaylistDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else { return }

        _ = fileAccessService.createPlaylist(name: name, description: description)

        newPlaylistName = ""
        newPlaylistDescription = ""
        showCreatePlaylist = false
    }
}

// MARK: - Playlist Detail View
struct PlaylistDetailView: View {
    let playlist: Playlist
    @ObservedObject var fileAccessService: FileAccessService
    @ObservedObject var audioEngine: AudioEngine
    @M3EDismiss private var dismiss

    @State private var showEditPlaylist = false
    @State private var editedName = ""
    @State private var editedDescription = ""
    @State private var showDeleteConfirmation = false

    private var songs: [Song] {
        fileAccessService.songsInPlaylist(playlist)
    }

    var body: some View {
        ZStack {
            // iOS 16 native background
            LinearGradient(
                colors: [
                    M3EColor.surface,
                    M3EColor.surfaceContainerLow
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                // ✅ PERF: `songsInPlaylist` es una consulta que recorre la
                // biblioteca; antes se ejecutaba en el body, tres veces en el hero
                // y en CADA closure de fila (play y context menu). Ahora es UNA
                // lectura por render y se pasa como valor al hero y a las filas.
                let songs = self.songs
                VStack(spacing: 0) {
                    // Hero Section
                    playlistHeroSection(songs)

                    // Songs list
                    VStack(spacing: 12) {
                        ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                            PlaylistSongRow(
                                song: song,
                                index: index,
                                isCurrent: audioEngine.currentSong?.id == song.id,
                                isPlaying: audioEngine.isPlaying,
                                isLiked: fileAccessService.isLiked(song),
                                onPlay: { audioEngine.play(song: song, from: songs) },
                                onPlayNext: { audioEngine.playNext(song) },
                                onAddToQueue: { audioEngine.addToQueue(song) },
                                onToggleLike: { fileAccessService.toggleLike(song) },
                                onRemove: { fileAccessService.removeSongFromPlaylist(song, playlist: playlist) }
                            )
                            // ✅ PERF: sin `.equatable()` el body del detalle (que
                            // observa el motor) re-evaluaría todas las filas visibles
                            // en cada @Published. Con esto solo se repinta la que cambió.
                            .equatable()
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 30)
                }
            }
        }
        // ✅ M3E: top app bar propia (sin NavigationStack ni toolbar del sistema).
        .safeAreaInset(edge: .top, spacing: 0) {
            M3ENavigationBar(
                title: playlist.name,
                leading: {
                    Button {
                        Haptics.light()
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                            Text(Localization.localized("design.back"))
                                .font(M3ETypography.labelLargeEmphasized)
                        }
                        .foregroundStyle(M3EColor.primary)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel(Localization.localized("design.back"))
                },
                trailing: {
                    Menu {
                        Button {
                            editedName = playlist.name
                            editedDescription = playlist.description
                            showEditPlaylist = true
                        } label: {
                            Label(Localization.localized("playlists.editPlaylist"), systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label(Localization.localized("playlists.deletePlaylist"), systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(M3EColor.onSurfaceVariant)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                }
            )
        }
        .fullScreenCover(isPresented: $showEditPlaylist) {
            editPlaylistSheet
        }
        .alert(String(format: Localization.localized("playlists.deleteConfirm"), playlist.name), isPresented: $showDeleteConfirmation) {
            Button(Localization.localized("actions.cancel"), role: .cancel) {}
            Button(Localization.localized("queue.remove"), role: .destructive) {
                fileAccessService.deletePlaylist(playlist)
                dismiss()
            }
        } message: {
            Text(Localization.localized("playlists.deleteConfirmMessage"))
        }
    }

    /// ✅ PERF: recibe la lista ya resuelta por el body (una sola consulta
    /// por render en vez de cinco). El contenido del hero no cambia.
    private func playlistHeroSection(_ songs: [Song]) -> some View {
        VStack(spacing: 18) {
            // Artwork con marco sutil
            ZStack {
                if let artwork = playlist.artwork {
                    // ✅ ANTI-JETSAM: hero de 220pt → miniatura de 440px cacheada.
                    Image(uiImage: AppTheme.thumbnail(from: artwork, size: CGSize(width: 440, height: 440)))
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(width: 220, height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.3), radius: 22, x: 0, y: 12)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        AppTheme.accent.opacity(0.3),
                                        AppTheme.accent.opacity(0.15)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 220, height: 220)

                        Image(systemName: "music.note.list")
                            .font(.system(size: 52))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .shadow(color: .black.opacity(0.2), radius: 18, x: 0, y: 9)
                }
            }
            .padding(.top, 16)

            // Playlist info
            VStack(spacing: 6) {
                Text(playlist.name)
                    .font(M3ETypography.headlineSmallEmphasized)
                    .tracking(-0.4)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if !playlist.description.isEmpty {
                    Text(playlist.description)
                        .font(M3ETypography.bodyLarge)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }

                HStack(spacing: 10) {
                    statPill(icon: "music.note", text: localizedSongCount(songs.count))

                    let totalDuration = songs.reduce(0) { $0 + $1.duration }
                    if totalDuration > 60 {
                        statPill(icon: "clock", text: formatLongDuration(totalDuration))
                    }
                }
            }
            .padding(.horizontal, 20)

            // Botones: Reproducir + Aleatorio
            if !songs.isEmpty {
                HStack(spacing: 12) {
                    Button {
                        Haptics.medium()
                        if let firstSong = songs.first {
                            audioEngine.play(song: firstSong, from: songs)
                        }
                    } label: {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text(Localization.localized("details.play"))
                        .font(M3ETypography.labelLargeEmphasized)
                }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18) // Expanded touch target (15→18)
                        .background {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(LinearGradient(
                                    colors: [AppTheme.accent, AppTheme.accent.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                        }
                        .contentShape(Rectangle())
                        .shadow(color: AppTheme.accent.opacity(0.35), radius: 10, x: 0, y: 5)
                    }
                    // ✅ M3E: rebote elástico al toque (antes: `.plain`, cero feedback).
                    .buttonStyle(PressableButtonStyle(scale: AuroraPressScale.button, pressedOpacity: 0.85))

                    Button {
                        Haptics.medium()
                        if !audioEngine.isShuffleEnabled {
                            audioEngine.toggleShuffle()
                        }
                        if let randomSong = songs.randomElement() {
                            audioEngine.play(song: randomSong, from: songs)
                        }
                    } label: {
                        Image(systemName: "shuffle")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AppTheme.accentGradient)
                            .frame(width: 52, height: 52)
                            .background {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(AppTheme.accentGradient(opacity: 0.14))
                            }
                            .frame(width: 60, height: 60) // Bigger invisible touch target
                            .contentShape(Rectangle())
                    }
                    // ✅ M3E: mismo rebote que el primario, en escala de chip.
                    .buttonStyle(PressableButtonStyle(scale: AuroraPressScale.button, pressedOpacity: 0.85))
                }
                .padding(.horizontal, 20)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
        .background(alignment: .top) {
            // ✅ M3E: cabecera con gradiente tonal. Sin carátula desenfocada:
            // el único blur de fondo permitido es el de NowPlaying.
            GeometryReader { geometry in
                LinearGradient(
                    colors: [AppTheme.accent.opacity(0.18), M3EColor.surface],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: geometry.size.width, height: geometry.size.height + 80)
                .clipped()
                .ignoresSafeArea(edges: .top)
            }
        }
    }

    private func statPill(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(M3ETypography.labelMedium)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        // ✅ M3E: píldora de estadística sólida (sin material sobre la cabecera
        // con carátula desenfocada).
        .background(Capsule().fill(M3EColor.surfaceContainerHigh))
    }

    private func formatLongDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        if minutes >= 60 {
            let hours = minutes / 60
            let rem = minutes % 60
            return rem > 0 ? "\(hours) h \(rem) min" : "\(hours) h"
        }
        return "\(minutes) min"
    }

    private var editPlaylistSheet: some View {
        ZStack {
            AppBackground()

                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(Localization.localized("playlists.name"))
                    .font(M3ETypography.labelLargeEmphasized)
                    .foregroundStyle(.secondary)

                TextField(Localization.localized("playlists.placeholderName"), text: $editedName)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(
                        M3EColor.surfaceContainerHigh,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(Localization.localized("playlists.description"))
                    .font(M3ETypography.labelLargeEmphasized)
                    .foregroundStyle(.secondary)

                TextField(Localization.localized("playlists.placeholderDescription"), text: $editedDescription)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(
                        M3EColor.surfaceContainerHigh,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
            }
                        }
                        .padding(.horizontal, 4)

                        M3EFilledButton(action: savePlaylistChanges) {
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18, weight: .semibold))

                                Text(Localization.localized("playlists.saveChanges"))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .disabled(editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                }
                .scrollIndicators(.hidden)
            }
            // ✅ M3E: cabecera propia del diálogo (sin NavigationStack).
            .safeAreaInset(edge: .top, spacing: 0) {
                M3ENavigationBar(
                    title: Localization.localized("playlists.editPlaylist"),
                    leading: {
                        Button { showEditPlaylist = false } label: {
                            Image(systemName: "close")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(M3EColor.onSurfaceVariant)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel(Localization.localized("design.close"))
                    },
                    trailing: {
                        Button(Localization.localized("actions.done")) {
                            savePlaylistChanges()
                        }
                        .font(M3ETypography.labelLargeEmphasized)
                        .foregroundStyle(
                            editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? M3EColor.onSurfaceVariant
                                : M3EColor.primary
                        )
                        .disabled(editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .frame(height: 44)
                    }
                )
            }
    }

    private func savePlaylistChanges() {
        let name = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = editedDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else { return }

        fileAccessService.updatePlaylist(playlist, name: name, description: description)
        showEditPlaylist = false
    }

}
