import SwiftUI

// MARK: - Album Detail
struct AlbumDetailView: View {
    let album: Album
    @ObservedObject var audioEngine: AudioEngine
    @Environment(\.dismiss) private var dismiss

    private var songs: [Song] {
        album.songs
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
                    heroSection

                    // Songs list with native design
                    VStack(spacing: 12) {
                        ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                            modernSongRow(song, index: index)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 30)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(true)
    }

    private var heroSection: some View {
        VStack(spacing: 24) {
            // Navigation bar with native materials
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .background {
                            Circle()
                                .fill(.regularMaterial)
                        }
                }

                Spacer()

                Text("Álbum")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                // More options button (placeholder)
                Button {

                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .background {
                            Circle()
                                .fill(.regularMaterial)
                        }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            // Large artwork with enhanced native design
            Group {
                if let artwork = album.artwork {
                    ZStack {
                        Image(uiImage: artwork)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 280, height: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                        // Subtle gradient overlay
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .clear,
                                        .black.opacity(0.08),
                                        .black.opacity(0.15)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    .shadow(color: .black.opacity(0.35), radius: 28, x: 0, y: 14)
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(.white.opacity(0.2), lineWidth: 1.5)
                    }
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.secondary.opacity(0.3),
                                        Color.secondary.opacity(0.2)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 280, height: 280)
                            .shadow(color: .black.opacity(0.25), radius: 22, x: 0, y: 12)

                        Image(systemName: "square.stack")
                            .font(.system(size: 64))
                            .foregroundStyle(.secondary.opacity(0.8))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(.white.opacity(0.15), lineWidth: 1.5)
                    }
                }
            }
            .padding(.top, 20)

            // Album info with native typography
            VStack(spacing: 12) {
                Text(album.name)
                    .font(.title)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)

                Text(album.artist)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 8) {
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

            // Enhanced native play button
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
        .padding(.bottom, 24)
    }

    private func modernSongRow(_ song: Song, index: Int) -> some View {
        let isCurrent = audioEngine.currentSong?.id == song.id

        return Button {
            audioEngine.play(song: song, from: songs)
        } label: {
            HStack(spacing: 16) {
                // Track number with native design
                Text("\(index + 1)")
                    .font(.body)
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary.opacity(0.6))
                    .frame(width: 30, alignment: .center)

                // Song info with enhanced typography (no blue accent for album songs)
                VStack(alignment: .leading, spacing: 6) {
                    Text(song.displayName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
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
        .buttonStyle(.plain)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

// MARK: - Artist Detail
struct ArtistDetailView: View {
    let artist: Artist
    @ObservedObject var audioEngine: AudioEngine

    private var songs: [Song] {
        artist.songs
    }

    private var albums: [Album] {
        artist.albums
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
                    artistHeroSection

                    // Albums section (vertical list for consistency with songs)
                    if !albums.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Álbumes")
                                .font(.title2)
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 20)

                            VStack(spacing: 12) {
                                ForEach(albums) { album in
                                    NavigationLink {
                                        AlbumDetailView(album: album, audioEngine: audioEngine)
                                    } label: {
                                        HStack(spacing: 16) {
                                            // Album artwork
                                            Group {
                                                if let artwork = album.artwork {
                                                    Image(uiImage: artwork)
                                                        .resizable()
                                                        .scaledToFill()
                                                        .frame(width: 56, height: 56)
                                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                                } else {
                                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                        .fill(Color.secondary.opacity(0.2))
                                                        .frame(width: 56, height: 56)
                                                        .overlay {
                                                            Image(systemName: "square.stack")
                                                                .font(.system(size: 20))
                                                                .foregroundStyle(.secondary)
                                                        }
                                                }
                                            }

                                            // Album info
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(album.name)
                                                    .font(.body.weight(.medium))
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(1)

                                                Text("\(album.songs.count) canciones")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }

                                            Spacer()

                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background {
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .fill(Color.secondary.opacity(0.05))
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        .padding(.top, 32)
                    }

                    // Songs section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Canciones")
                            .font(.title2)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 20)

                        VStack(spacing: 12) {
                            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                                modernSongRow(song, index: index)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.top, 32)
                    .padding(.bottom, 30)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(true)
    }

    private var artistHeroSection: some View {
        VStack(spacing: 24) {
            // Navigation bar with native materials
            HStack {
                Button {

                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .background {
                            Circle()
                                .fill(.regularMaterial)
                        }
                }

                Spacer()

                Text("Artista")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Button {

                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .background {
                            Circle()
                                .fill(.regularMaterial)
                        }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            // Artist artwork with enhanced circular design
            Group {
                if let artwork = artist.artwork {
                    ZStack {
                        Image(uiImage: artwork)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 200, height: 200)
                            .clipShape(Circle())

                        // Subtle gradient overlay
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .clear,
                                        .black.opacity(0.1),
                                        .black.opacity(0.18)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.2), lineWidth: 2)
                    }
                } else {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.secondary.opacity(0.3),
                                        Color.secondary.opacity(0.2)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 200, height: 200)
                            .shadow(color: .black.opacity(0.25), radius: 18, x: 0, y: 9)

                        Image(systemName: "person.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.secondary.opacity(0.8))
                    }
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.15), lineWidth: 2)
                    }
                }
            }
            .padding(.top, 20)

            // Artist info with native typography
            VStack(spacing: 12) {
                Text(artist.name)
                    .font(.title)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)

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

                    if !albums.isEmpty {
                        Text("\(albums.count) álbumes")
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
            }
            .padding(.horizontal, 20)

            // Enhanced native play button
            if let firstSong = songs.first {
                Button {
                    audioEngine.play(song: firstSong, from: songs)
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

                        Text("Reproducir")
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

    private func modernAlbumCard(_ album: Album) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Album artwork
            Group {
                if let artwork = album.artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 140, height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 6)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.secondary.opacity(0.25),
                                        Color.secondary.opacity(0.15)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 140, height: 140)
                            .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)

                        Image(systemName: "square.stack")
                            .font(.system(size: 35))
                            .foregroundStyle(.secondary.opacity(0.7))
                    }
                }
            }

            // Album info with native typography
            VStack(alignment: .leading, spacing: 4) {
                Text(album.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("\(album.songs.count) canciones")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 140)
    }

    private func modernSongRow(_ song: Song, index: Int) -> some View {
        let isCurrent = audioEngine.currentSong?.id == song.id

        return Button {
            audioEngine.play(song: song, from: songs)
        } label: {
            HStack(spacing: 16) {
                // Track number with native design
                Text("\(index + 1)")
                    .font(.body)
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary.opacity(0.6))
                    .frame(width: 30, alignment: .center)

                // Song info with enhanced typography (no blue accent for album songs)
                VStack(alignment: .leading, spacing: 6) {
                    Text(song.displayName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
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
        .buttonStyle(.plain)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}