import SwiftUI

struct PlaylistsView: View {
    @ObservedObject var fileAccessService: FileAccessService
    @ObservedObject var audioEngine: AudioEngine
    @Environment(\.dismiss) private var dismiss

    @State private var showCreatePlaylist = false
    @State private var newPlaylistName = ""
    @State private var newPlaylistDescription = ""

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

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
            .navigationTitle("Listas de Reproducción")
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
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showCreatePlaylist = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .sheet(isPresented: $showCreatePlaylist) {
                createPlaylistSheet
            }
        }
    }

    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.16))
                    .frame(width: 80, height: 80)

                Image(systemName: "music.note.list")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            Text("Tus Listas")
                .font(.system(size: 24, weight: .bold))

            Text("Crea y gestiona tus listas de reproducción personalizadas")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .enhancedGlass(cornerRadius: 24)
    }

    // MARK: - Empty State
    private var emptyPlaylistsState: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("Sin listas de reproducción")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("Crea tu primera lista para organizar tu música")
                .font(.system(size: 14))
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
                NavigationLink {
                    PlaylistDetailView(
                        playlist: playlist,
                        fileAccessService: fileAccessService,
                        audioEngine: audioEngine
                    )
                } label: {
                    playlistCard(playlist)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Playlist Card
    private func playlistCard(_ playlist: Playlist) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Playlist artwork
            ZStack {
                if let artwork = playlist.artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 150, height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.accentColor.opacity(0.3),
                                        Color.accentColor.opacity(0.15)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
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
                            Circle()
                                .fill(.regularMaterial)
                                .frame(width: 32, height: 32)

                            Text("\(playlist.songIDs.count)")
                                .font(.system(size: 12, weight: .semibold))
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
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if !playlist.description.isEmpty {
                    Text(playlist.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text("\(playlist.songIDs.count) canciones")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 150)
    }

    // MARK: - Create Playlist Sheet
    private var createPlaylistSheet: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color.accentColor.opacity(0.16))
                                    .frame(width: 70, height: 70)

                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                            }

                            Text("Nueva Lista")
                                .font(.system(size: 22, weight: .bold))

                            Text("Crea una nueva lista de reproducción personalizada")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .enhancedGlass(cornerRadius: 22)

                        VStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Nombre")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.secondary)

                                TextField("Mi lista", text: $newPlaylistName)
                                    .textFieldStyle(.roundedBorder)
                                    .padding(.horizontal, 4)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Descripción (opcional)")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.secondary)

                                TextField("Descripción de la lista", text: $newPlaylistDescription)
                                    .textFieldStyle(.roundedBorder)
                                    .padding(.horizontal, 4)
                            }
                        }
                        .padding(.horizontal, 4)

                        Button {
                            createPlaylist()
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 18, weight: .semibold))

                                Text("Crear Lista")
                                    .font(.system(size: 17, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color.accentColor)

                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    .white.opacity(0.15),
                                                    .white.opacity(0.05),
                                                    .clear
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                }
                            }
                            .shadow(color: Color.accentColor.opacity(0.5), radius: 16, x: 0, y: 8)
                        }
                        .disabled(newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Crear Lista")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancelar") {
                        showCreatePlaylist = false
                    }
                    .foregroundStyle(.secondary)
                }
            }
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
    @Environment(\.dismiss) private var dismiss

    @State private var showEditPlaylist = false
    @State private var editedName = ""
    @State private var editedDescription = ""

    private var songs: [Song] {
        fileAccessService.songsInPlaylist(playlist)
    }

    var body: some View {
        ZStack {
            // iOS 16 native background
            LinearGradient(
                colors: [
                    Color(UIColor.systemBackground),
                    Color(UIColor.secondarySystemBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Hero Section
                    playlistHeroSection

                    // Songs list
                    VStack(spacing: 12) {
                        ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                            playlistSongRow(song, index: index)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 30)
                }
            }
        }
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(isPresented: $showEditPlaylist) {
            editPlaylistSheet
        }
    }

    private var playlistHeroSection: some View {
        VStack(spacing: 24) {
            // Playlist artwork
            ZStack {
                if let artwork = playlist.artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 200, height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.accentColor.opacity(0.3),
                                        Color.accentColor.opacity(0.15)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 200, height: 200)
                            .shadow(color: .black.opacity(0.25), radius: 18, x: 0, y: 9)

                        Image(systemName: "music.note.list")
                            .font(.system(size: 48))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
            .padding(.top, 20)

            // Playlist info
            VStack(spacing: 12) {
                Text(playlist.name)
                    .font(.title)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)

                if !playlist.description.isEmpty {
                    Text(playlist.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 12) {
                    Text("\(songs.count) canciones")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            Capsule()
                                .fill(.regularMaterial)
                        }
                }
            }
            .padding(.horizontal, 20)

            // Play button
            if !songs.isEmpty {
                Button {
                    if let firstSong = songs.first {
                        audioEngine.play(song: firstSong, from: songs)
                    }
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(.white.opacity(0.2))
                                .frame(width: 36, height: 36)

                        Image(systemName: "play.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                        }

                        Text("Reproducir todo")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.accentColor)

                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            .white.opacity(0.15),
                                            .white.opacity(0.05),
                                            .clear
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                    }
                    .shadow(color: Color.accentColor.opacity(0.5), radius: 16, x: 0, y: 8)
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.bottom, 24)
    }

    private func playlistSongRow(_ song: Song, index: Int) -> some View {
        let isCurrent = audioEngine.currentSong?.id == song.id

        return Button {
            audioEngine.play(song: song, from: songs)
        } label: {
            HStack(spacing: 16) {
                Text("\(index + 1)")
                    .font(.body)
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary.opacity(0.6))
                    .frame(width: 30, alignment: .center)

                VStack(alignment: .leading, spacing: 6) {
                    Text(song.displayName)
                        .font(.body)
                        .foregroundStyle(isCurrent ? Color.accentColor : .primary)
                        .lineLimit(1)

                    Text(song.displaySubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Duration or playing indicator
                if isCurrent {
                    HStack(spacing: 4) {
                        ForEach(0..<3) { _ in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.accentColor)
                                .frame(width: 3, height: 14)
                                .offset(y: CGFloat.random(in: -3...3))
                                .animation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true), value: isCurrent)
                        }
                    }
                } else {
                    Text(formatDuration(song.duration))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }

                // Remove button
                Button {
                    fileAccessService.removeSongFromPlaylist(song, playlist: playlist)
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.accentColor.opacity(0.1))
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.secondary.opacity(0.05))
                }
            }
        }
    }

    private var editPlaylistSheet: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Nombre")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.secondary)

                                TextField("Nombre de la lista", text: $editedName)
                                    .textFieldStyle(.roundedBorder)
                                    .padding(.horizontal, 4)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Descripción")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.secondary)

                                TextField("Descripción", text: $editedDescription)
                                    .textFieldStyle(.roundedBorder)
                                    .padding(.horizontal, 4)
                            }
                        }
                        .padding(.horizontal, 4)

                        Button {
                            savePlaylistChanges()
                        } label: {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18, weight: .semibold))

                                Text("Guardar Cambios")
                                    .font(.system(size: 17, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color.accentColor)

                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    .white.opacity(0.15),
                                                    .white.opacity(0.05),
                                                    .clear
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                }
                            }
                            .shadow(color: Color.accentColor.opacity(0.5), radius: 16, x: 0, y: 8)
                        }
                        .disabled(editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Editar Lista")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancelar") {
                        showEditPlaylist = false
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func savePlaylistChanges() {
        let name = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = editedDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else { return }

        fileAccessService.updatePlaylist(playlist, name: name, description: description)
        showEditPlaylist = false
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}
