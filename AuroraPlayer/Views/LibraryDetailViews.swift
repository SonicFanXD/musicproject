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
            // Modern gradient background
            LinearGradient(
                colors: [
                    Color(UIColor.systemBackground),
                    Color(UIColor.secondarySystemBackground).opacity(0.5)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Hero Section with glass morphism
                    heroSection

                    // Songs list with modern cards
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
            // Navigation bar
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
                                .fill(.ultraThinMaterial)
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
                                .fill(.ultraThinMaterial)
                        }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            // Large artwork with shadow and glow
            ZStack {
                // Glow effect
                if let artwork = album.artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 280, height: 280)
                        .blur(radius: 40)
                        .opacity(0.4)
                }

                // Main artwork
                Group {
                    if let artwork = album.artwork {
                        Image(uiImage: artwork)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 280, height: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .shadow(color: .black.opacity(0.3), radius: 30, x: 0, y: 15)
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.secondary.opacity(0.3),
                                            Color.secondary.opacity(0.15)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 280, height: 280)
                                .shadow(color: .black.opacity(0.2), radius: 25, x: 0, y: 12)

                            Image(systemName: "square.stack")
                                .font(.system(size: 60))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [
                                            Color.secondary.opacity(0.8),
                                            Color.secondary.opacity(0.5)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        }
                    }
                }
            }
            .padding(.top, 20)

            // Album info with modern typography
            VStack(spacing: 12) {
                Text(album.name)
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)

                Text(album.artist)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 8) {
                    Text("\(songs.count) canciones")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            Capsule()
                                .fill(.ultraThinMaterial)
                        }
                }
            }
            .padding(.horizontal, 20)

            // Modern play button with gradient
            Button {
                if let firstSong = songs.first {
                    audioEngine.play(song: firstSong, from: songs)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 18, weight: .semibold))
                    
                    Text("Reproducir todo")
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.accentColor,
                                    Color.accentColor.opacity(0.8)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: Color.accentColor.opacity(0.4), radius: 12, x: 0, y: 6)
                }
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
                // Track number with design
                Text("\(index + 1)")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary.opacity(0.6))
                    .frame(width: 30, alignment: .center)

                // Song info
                VStack(alignment: .leading, spacing: 6) {
                    Text(song.title)
                        .font(.system(size: 17, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? Color.accentColor : .primary)
                        .lineLimit(1)

                    if !song.album.isEmpty {
                        Text(song.album)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
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
                        .font(.system(size: 14, weight: .medium))
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
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
        }
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
            // Modern gradient background
            LinearGradient(
                colors: [
                    Color(UIColor.systemBackground),
                    Color(UIColor.secondarySystemBackground).opacity(0.5)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Hero Section
                    artistHeroSection

                    // Albums section
                    if !albums.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Álbumes")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 20)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(albums) { album in
                                        NavigationLink {
                                            AlbumDetailView(album: album, audioEngine: audioEngine)
                                        } label: {
                                            modernAlbumCard(album)
                                        }
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                        .padding(.top, 32)
                    }

                    // Songs section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Canciones")
                            .font(.system(size: 22, weight: .bold))
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
            // Navigation bar
            HStack {
                Button {
                    
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .background {
                            Circle()
                                .fill(.ultraThinMaterial)
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
                                .fill(.ultraThinMaterial)
                        }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            // Artist artwork with circular design
            ZStack {
                // Glow effect
                if let artwork = artist.artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 200, height: 200)
                        .clipShape(Circle())
                        .blur(radius: 30)
                        .opacity(0.4)
                }

                // Main artwork
                Group {
                    if let artwork = artist.artwork {
                        Image(uiImage: artwork)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 200, height: 200)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.3), radius: 25, x: 0, y: 12)
                    } else {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.secondary.opacity(0.3),
                                            Color.secondary.opacity(0.15)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 200, height: 200)
                                .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)

                            Image(systemName: "person.fill")
                                .font(.system(size: 50))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [
                                            Color.secondary.opacity(0.8),
                                            Color.secondary.opacity(0.5)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        }
                    }
                }
            }
            .padding(.top, 20)

            // Artist info
            VStack(spacing: 12) {
                Text(artist.name)
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)

                HStack(spacing: 12) {
                    Text("\(songs.count) canciones")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            Capsule()
                                .fill(.ultraThinMaterial)
                        }

                    if !albums.isEmpty {
                        Text("\(albums.count) álbumes")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background {
                                Capsule()
                                    .fill(.ultraThinMaterial)
                            }
                    }
                }
            }
            .padding(.horizontal, 20)

            // Play button
            if let firstSong = songs.first {
                Button {
                    audioEngine.play(song: firstSong, from: songs)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 18, weight: .semibold))
                        
                        Text("Reproducir")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.accentColor,
                                        Color.accentColor.opacity(0.8)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .shadow(color: Color.accentColor.opacity(0.4), radius: 12, x: 0, y: 6)
                    }
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

            // Album info
            VStack(alignment: .leading, spacing: 4) {
                Text(album.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("\(album.songs.count) canciones")
                    .font(.system(size: 13))
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
                // Track number
                Text("\(index + 1)")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary.opacity(0.6))
                    .frame(width: 30, alignment: .center)

                // Song info
                VStack(alignment: .leading, spacing: 6) {
                    Text(song.title)
                        .font(.system(size: 17, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? Color.accentColor : .primary)
                        .lineLimit(1)

                    if !song.album.isEmpty {
                        Text(song.album)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
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
                        .font(.system(size: 14, weight: .medium))
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
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}