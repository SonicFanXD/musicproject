import SwiftUI

// MARK: - Album Detail (diseño inmersivo premium con color de carátula)
struct AlbumDetailView: View {
    let album: Album
    @ObservedObject var audioEngine: AudioEngine
    @Environment(\.dismiss) private var dismiss

    private var songs: [Song] { album.songs }
    private var totalDuration: TimeInterval { songs.reduce(0) { $0 + $1.duration } }
    private var hasMultipleDiscs: Bool { Set(songs.compactMap { $0.discNumber }).count > 1 }
    private var songsByDisc: [(disc: Int, songs: [Song])] {
        let grouped = Dictionary(grouping: songs) { $0.discNumber ?? 1 }
        return grouped.keys.sorted().map { ($0, grouped[$0]!.sorted { $0.trackNumber < $1.trackNumber }) }
    }
    private var tintColor: Color { Color(album.dominantColor ?? UIColor.systemPurple) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                heroSection
                actionButtons
                    .padding(.horizontal, 20).padding(.top, 20)
                VStack(spacing: 10) {
                    sectionHeader(icon: "music.note.list", title: "Canciones")
                    if hasMultipleDiscs {
                        ForEach(songsByDisc, id: \.disc) { discGroup in
                            discSection(disc: discGroup.disc, songs: discGroup.songs)
                        }
                    } else {
                        ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                            songRow(song, index: index)
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 28).padding(.bottom, 30)
            }
        }
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
        .navigationTitle(album.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(UIColor.systemBackground).opacity(0.92), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private var heroSection: some View {
        VStack(spacing: 18) {
            Group {
                if let artwork = album.artwork {
                    Image(uiImage: artwork)
                        .resizable().interpolation(.high).scaledToFill()
                        .frame(width: 240, height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [.white.opacity(0.25), .white.opacity(0.05)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        }
                        .shadow(color: .black.opacity(0.35), radius: 28, x: 0, y: 16)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [tintColor.opacity(0.25), Color.secondary.opacity(0.2)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 240, height: 240)
                        Image(systemName: "square.stack")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary.opacity(0.8))
                    }
                    .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
                }
            }
            .padding(.top, 16)

            VStack(spacing: 6) {
                Text(album.name)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center).foregroundStyle(.primary).lineLimit(2)
                Text(album.artist)
                    .font(.system(size: 17, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.horizontal, 24)

            HStack(spacing: 10) {
                statPill(icon: "music.note", text: "\(songs.count) canciones")
                if totalDuration > 60 {
                    statPill(icon: "clock", text: formatLongDuration(totalDuration))
                }
            }
        }
        .frame(maxWidth: .infinity).padding(.bottom, 4)
        .background(alignment: .top) {
            GeometryReader { geometry in
                Group {
                    if let artwork = album.artwork {
                        Image(uiImage: artwork)
                            .resizable().scaledToFill().blur(radius: 44).opacity(0.4)
                            .overlay(
                                LinearGradient(
                                    colors: [tintColor.opacity(0.25), Color(UIColor.systemBackground).opacity(0.55)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                    } else {
                        LinearGradient(
                            colors: [tintColor.opacity(0.18), Color(UIColor.systemBackground)],
                            startPoint: .top, endPoint: .bottom
                        )
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height + 80)
                .clipped().ignoresSafeArea(edges: .top)
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                Haptics.medium()
                if let firstSong = songs.first {
                    audioEngine.play(song: firstSong, from: songs)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill").font(.system(size: 16, weight: .bold))
                    Text("Reproducir").font(.system(size: 16, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 54)
                .background {
                    Capsule().fill(
                        LinearGradient(colors: [tintColor, tintColor.opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                }
                .contentShape(Capsule())
                .shadow(color: tintColor.opacity(0.5), radius: 14, x: 0, y: 7)
            }
            .buttonStyle(PressableButtonStyle(scale: 0.97))

            Button {
                Haptics.medium()
                if !audioEngine.isShuffleEnabled { audioEngine.toggleShuffle() }
                if let randomSong = songs.randomElement() {
                    audioEngine.play(song: randomSong, from: songs)
                }
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 17, weight: .bold)).foregroundStyle(tintColor)
                    .frame(width: 54, height: 54)
                    .background {
                        Circle().fill(
                            LinearGradient(colors: [tintColor.opacity(0.18), tintColor.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    }
                    .frame(width: 62, height: 62).contentShape(Circle())
            }
            .buttonStyle(PressableButtonStyle(scale: 0.9))
        }
    }

    private func discSection(disc: Int, songs: [Song]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "opticaldisc").font(.system(size: 12, weight: .semibold)).foregroundStyle(tintColor.opacity(0.8))
                Text("Disco \(disc)").font(.system(size: 14, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4).padding(.top, 6)
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                songRow(song, index: index)
            }
        }
    }

    private func songRow(_ song: Song, index: Int) -> some View {
        let isCurrent = audioEngine.currentSong?.id == song.id
        return Button {
            Haptics.light()
            audioEngine.play(song: song, from: songs)
        } label: {
            HStack(spacing: 14) {
                if isCurrent {
                    HStack(spacing: 2.5) {
                        ForEach(0..<3, id: \.self) { bar in
                            RoundedRectangle(cornerRadius: 1).fill(tintColor)
                                .frame(width: 2.5, height: bar % 2 == 0 ? 13 : 8)
                                .animation(.easeInOut(duration: 0.45 + Double(bar) * 0.12).repeatForever(autoreverses: true), value: isCurrent)
                        }
                    }.frame(width: 24)
                } else {
                    Text("\(index + 1)")
                        .font(.system(size: 14, weight: .medium).monospacedDigit())
                        .foregroundStyle(Color.secondary.opacity(0.5)).frame(width: 24)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(song.title)
                        .font(.system(size: 15, weight: isCurrent ? .bold : .semibold, design: .rounded))
                        .foregroundStyle(isCurrent ? tintColor : .primary).lineLimit(1)
                    Text(song.displaySubtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }

                Spacer()

                Text(formatDuration(song.duration))
                    .font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isCurrent ? tintColor.opacity(0.08) : Color.clear)
            }
            .contentShape(Rectangle())
            .overlay {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(tintColor.opacity(0.2), lineWidth: 0.5)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func statPill(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
            Text(text).font(.system(size: 13, weight: .medium).monospacedDigit())
        }
        .foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 6)
        .background { Capsule().fill(.regularMaterial) }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
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
}

// MARK: - Header de sección reutilizable
private func sectionHeader(icon: String, title: String) -> some View {
    HStack(spacing: 8) {
        Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.accentColor)
        Text(title).font(.system(size: 20, weight: .bold)).foregroundStyle(.primary)
        Spacer()
    }.padding(.top, 4)
}

// MARK: - Artist Detail (perfil inmersivo premium)
struct ArtistDetailView: View {
    let artist: Artist
    @ObservedObject var audioEngine: AudioEngine
    @Environment(\.dismiss) private var dismiss

    private var songs: [Song] { artist.songs }
    private var albums: [Album] { artist.albums }
    private var totalDuration: TimeInterval { songs.reduce(0) { $0 + $1.duration } }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                artistHeroSection
                artistActionButtons
                    .padding(.horizontal, 20).padding(.top, 18)
                if !albums.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        sectionHeader(icon: "square.stack", title: "Álbumes")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(albums) { album in
                                    NavigationLink {
                                        AlbumDetailView(album: album, audioEngine: audioEngine)
                                    } label: {
                                        albumCard(album)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20).padding(.vertical, 4)
                        }
                    }
                    .padding(.top, 28)
                }
                VStack(spacing: 10) {
                    sectionHeader(icon: "music.note.list", title: "Canciones")
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                        songRow(song, index: index)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 28).padding(.bottom, 30)
            }
        }
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(UIColor.systemBackground).opacity(0.92), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private var artistHeroSection: some View {
        VStack(spacing: 16) {
            Group {
                if let artwork = artist.artwork {
                    Image(uiImage: artwork)
                        .resizable().interpolation(.high).scaledToFill()
                        .frame(width: 150, height: 150).clipShape(Circle())
                        .overlay {
                            Circle().strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 3)
                        }
                        .shadow(color: Color.accentColor.opacity(0.25), radius: 18, x: 0, y: 8)
                } else {
                    ZStack {
                        Circle().fill(
                            LinearGradient(colors: [Color.accentColor.opacity(0.3), Color.secondary.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 150, height: 150)
                        Image(systemName: "person.fill").font(.system(size: 48)).foregroundStyle(.secondary.opacity(0.8))
                    }
                }
            }
            .padding(.top, 20)

            VStack(spacing: 6) {
                Text(artist.name)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center).foregroundStyle(.primary).lineLimit(2)
                HStack(spacing: 8) {
                    statPill(icon: "music.note", text: "\(songs.count) canciones")
                    if !albums.isEmpty {
                        statPill(icon: "square.stack", text: "\(albums.count) álbumes")
                    }
                    if totalDuration > 60 {
                        statPill(icon: "clock", text: formatLongDuration(totalDuration))
                    }
                }
            }
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity).padding(.bottom, 4)
        .background(alignment: .top) {
            GeometryReader { geometry in
                Group {
                    if let artwork = artist.artwork {
                        Image(uiImage: artwork)
                            .resizable().scaledToFill().blur(radius: 46).opacity(0.35)
                            .overlay(Color(UIColor.systemBackground).opacity(0.45))
                    } else {
                        LinearGradient(colors: [Color.accentColor.opacity(0.18), Color(UIColor.systemBackground)], startPoint: .top, endPoint: .bottom)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height + 80)
                .clipped().ignoresSafeArea(edges: .top)
            }
        }
    }

    private var artistActionButtons: some View {
        HStack(spacing: 12) {
            Button {
                Haptics.medium()
                if let firstSong = songs.first {
                    audioEngine.play(song: firstSong, from: songs)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill").font(.system(size: 16, weight: .bold))
                    Text("Reproducir").font(.system(size: 16, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 54)
                .background {
                    Capsule().fill(
                        LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                }
                .contentShape(Capsule())
                .shadow(color: Color.accentColor.opacity(0.45), radius: 14, x: 0, y: 7)
            }
            .buttonStyle(PressableButtonStyle(scale: 0.97))

            Button {
                Haptics.medium()
                if !audioEngine.isShuffleEnabled { audioEngine.toggleShuffle() }
                if let randomSong = songs.randomElement() {
                    audioEngine.play(song: randomSong, from: songs)
                }
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 17, weight: .bold)).foregroundStyle(Color.accentColor)
                    .frame(width: 54, height: 54)
                    .background {
                        Circle().fill(
                            LinearGradient(colors: [Color.accentColor.opacity(0.18), Color.accentColor.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    }
                    .frame(width: 62, height: 62).contentShape(Circle())
            }
            .buttonStyle(PressableButtonStyle(scale: 0.9))
        }
    }

    private func albumCard(_ album: Album) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if let artwork = album.artwork {
                    Image(uiImage: artwork)
                        .resizable().scaledToFill()
                        .frame(width: 150, height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.22), radius: 12, x: 0, y: 6)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(colors: [Color.accentColor.opacity(0.22), Color.secondary.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .frame(width: 150, height: 150)
                        Image(systemName: "square.stack").font(.system(size: 34)).foregroundStyle(.secondary.opacity(0.7))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(album.name)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary).lineLimit(1)
                Text("\(album.songs.count) canciones")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 150)
    }

    private func songRow(_ song: Song, index: Int) -> some View {
        let isCurrent = audioEngine.currentSong?.id == song.id
        return Button {
            Haptics.light()
            audioEngine.play(song: song, from: songs)
        } label: {
            HStack(spacing: 14) {
                if isCurrent {
                    HStack(spacing: 2.5) {
                        ForEach(0..<3, id: \.self) { bar in
                            RoundedRectangle(cornerRadius: 1).fill(Color.accentColor)
                                .frame(width: 2.5, height: bar % 2 == 0 ? 13 : 8)
                                .animation(.easeInOut(duration: 0.45 + Double(bar) * 0.12).repeatForever(autoreverses: true), value: isCurrent)
                        }
                    }.frame(width: 24)
                } else {
                    Text("\(index + 1)")
                        .font(.system(size: 14, weight: .medium).monospacedDigit())
                        .foregroundStyle(Color.secondary.opacity(0.5)).frame(width: 24)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(song.title)
                        .font(.system(size: 15, weight: isCurrent ? .bold : .semibold, design: .rounded))
                        .foregroundStyle(isCurrent ? Color.accentColor : .primary).lineLimit(1)
                    Text(song.album.isEmpty ? song.displaySubtitle : song.album)
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }

                Spacer()

                Text(formatDuration(song.duration))
                    .font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isCurrent ? Color.accentColor.opacity(0.08) : Color.clear)
            }
            .contentShape(Rectangle())
            .overlay {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 0.5)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func statPill(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
            Text(text).font(.system(size: 13, weight: .medium).monospacedDigit())
        }
        .foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 6)
        .background { Capsule().fill(.regularMaterial) }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
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
}