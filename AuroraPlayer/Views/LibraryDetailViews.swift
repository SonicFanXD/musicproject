import SwiftUI

// MARK: - Album Detail (diseño inmersivo premium con color de carátula)
struct AlbumDetailView: View {
    let album: Album
    @ObservedObject var audioEngine: AudioEngine
    @Environment(\.dismiss) private var dismiss

    // ✅ Color dominante VIVO (histograma HSB) extraído en segundo plano
    @State private var liveDominantColor: UIColor? = nil
    @State private var appearAnimation = false

    private var songs: [Song] { album.songs }
    private var totalDuration: TimeInterval { songs.reduce(0) { $0 + $1.duration } }
    private var hasMultipleDiscs: Bool { Set(songs.compactMap { $0.discNumber }).count > 1 }
    private var songsByDisc: [(disc: Int, songs: [Song])] {
        let grouped = Dictionary(grouping: songs) { $0.discNumber ?? 1 }
        return grouped.keys.sorted().map { ($0, grouped[$0]!.sorted { $0.trackNumber < $1.trackNumber }) }
    }
    // ✅ FIX: color normalizado para legibilidad; usa el vivo si ya se extrajo
    private var tintColor: Color { AppTheme.readableColor(from: liveDominantColor ?? album.dominantColor) }
    // ✅ UIColor crudo para calcular contraste de textos/botones
    private var tintUIColor: UIColor { liveDominantColor ?? album.dominantColor ?? AppTheme.accentUIColor }
    // ✅ Contraste: blanco o negro según luminancia del color de la portada
    private var onTintColor: Color { AppTheme.contrastingText(on: tintUIColor) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                heroSection
                actionButtons
                    .padding(.horizontal, 20).padding(.top, 20)
                VStack(spacing: 10) {
                    sectionHeader(icon: "music.note.list", title: Localization.localized("details.songs"))
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
                .padding(.horizontal, 20).padding(.top, 28)
                // ✅ FIX: padding inferior amplio para que la última canción
                // no quede oculta detrás del PlayerBar flotante.
                .padding(.bottom, 130)
            }
        }
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
        .navigationTitle(album.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(UIColor.systemBackground).opacity(0.92), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            // ✅ Animación de entrada suave
            withAnimation(.easeOut(duration: 0.4)) {
                appearAnimation = true
            }
            // ✅ Extraer el color dominante VIVO de la carátula en hilo de fondo
            guard let artwork = album.artwork else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                let dominant = AppTheme.dominantColor(from: artwork)
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.liveDominantColor = dominant
                    }
                }
            }
        }
    }

    private var heroSection: some View {
        VStack(spacing: 20) {
            // ✅ Artwork con animación de entrada y brillo sutil
            // ✅ 60fps: sombra ÚNICA consolidada (la doble sombra = 2 pasadas
            // de offscreen rendering por frame en A11; visualmente equivalente).
            Group {
                if let artwork = album.artwork {
                    Image(uiImage: artwork)
                        .resizable().interpolation(.high).scaledToFill()
                        .frame(width: 250, height: 250)
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                        .overlay {
                            // ✅ Brillo premium en el borde
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [.white.opacity(0.3), .white.opacity(0.05), .clear],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.2
                                )
                        }
                        .shadow(color: .black.opacity(0.35), radius: 22, x: 0, y: 12)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [tintColor.opacity(0.3), tintColor.opacity(0.1), Color.secondary.opacity(0.15)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 250, height: 250)
                        Image(systemName: "square.stack")
                            .font(.system(size: 65, weight: .light))
                            .foregroundStyle(.secondary.opacity(0.7))
                    }
                    .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
                }
            }
            .padding(.top, 16)
            .scaleEffect(appearAnimation ? 1.0 : 0.9)
            .opacity(appearAnimation ? 1.0 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: appearAnimation)

            // ✅ Info del álbum con mejor jerarquía visual
            VStack(spacing: 8) {
                Text(album.name)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(album.artist)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 24)
            .offset(y: appearAnimation ? 0 : 10)
            .opacity(appearAnimation ? 1.0 : 0)
            .animation(.easeOut(duration: 0.5).delay(0.1), value: appearAnimation)

            // ✅ Estadísticas con diseño mejorado
            HStack(spacing: 12) {
                statPill(icon: "music.note", text: "\(songs.count) \(Localization.localized("library.songCount"))")
                if totalDuration > 60 {
                    statPill(icon: "clock", text: formatLongDuration(totalDuration))
                }
            }
            .offset(y: appearAnimation ? 0 : 10)
            .opacity(appearAnimation ? 1.0 : 0)
            .animation(.easeOut(duration: 0.5).delay(0.15), value: appearAnimation)
        }
        .frame(maxWidth: .infinity).padding(.bottom, 4)
        .background(alignment: .top) {
            GeometryReader { geometry in
                Group {
                    if let artwork = album.artwork {
                        Image(uiImage: artwork)
                            .resizable().scaledToFill().blur(radius: 50).opacity(0.35)
                            .overlay(
                                LinearGradient(
                                    colors: [
                                        tintColor.opacity(0.3),
                                        tintColor.opacity(0.1),
                                        Color(UIColor.systemBackground).opacity(0.6)
                                    ],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                    } else {
                        LinearGradient(
                            colors: [tintColor.opacity(0.2), Color(UIColor.systemBackground)],
                            startPoint: .top, endPoint: .bottom
                        )
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height + 80)
                .clipped().ignoresSafeArea(edges: .top)
                .drawingGroup() // ✅ Optimización GPU para 60fps
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
                    Text(Localization.localized("details.play")).font(.system(size: 16, weight: .bold, design: .rounded))
                }
                .foregroundStyle(onTintColor).frame(maxWidth: .infinity).frame(height: 54)
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
                Text("\(Localization.localized("details.disc")) \(disc)").font(.system(size: 14, weight: .semibold)).foregroundStyle(.secondary)
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
        // ✅ Feedback de presión al tocar (micro-escala, animación GPU)
        .buttonStyle(PressableButtonStyle(scale: 0.98))
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

// MARK: - Header de sección reutilizable (con gradiente sutil)
private func sectionHeader(icon: String, title: String) -> some View {
    HStack(spacing: 8) {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                    startPoint: .top, endPoint: .bottom
                )
            )
        Text(title)
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
        Spacer()
    }.padding(.top, 4)
}

// MARK: - Artist Detail (perfil inmersivo premium)
struct ArtistDetailView: View {
    let artist: Artist
    @ObservedObject var audioEngine: AudioEngine
    @Environment(\.dismiss) private var dismiss

    @State private var appearAnimation = false
    @State private var liveDominantColor: UIColor? = nil

    private var songs: [Song] { artist.songs }
    private var albums: [Album] { artist.albums }
    private var totalDuration: TimeInterval { songs.reduce(0) { $0 + $1.duration } }
    private var tintColor: Color { AppTheme.readableColor(from: liveDominantColor ?? artist.albums.first?.dominantColor) }
    private var tintUIColor: UIColor { liveDominantColor ?? artist.albums.first?.dominantColor ?? AppTheme.accentUIColor }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                artistHeroSection
                artistActionButtons
                    .padding(.horizontal, 20).padding(.top, 18)
                if !albums.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        sectionHeader(icon: "square.stack", title: Localization.localized("details.albums"))
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
                    sectionHeader(icon: "music.note.list", title: Localization.localized("details.songs"))
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                        songRow(song, index: index)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 28)
                // ✅ FIX: padding inferior amplio para el PlayerBar flotante
                .padding(.bottom, 130)
            }
        }
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(UIColor.systemBackground).opacity(0.92), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                appearAnimation = true
            }
            // ✅ Extraer color del primer álbum
            if let artwork = artist.artwork {
                DispatchQueue.global(qos: .userInitiated).async {
                    let dominant = AppTheme.dominantColor(from: artwork)
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            self.liveDominantColor = dominant
                        }
                    }
                }
            }
        }
    }

    private var artistHeroSection: some View {
        VStack(spacing: 18) {
            // ✅ Avatar del artista con animación y efectos mejorados
            Group {
                if let artwork = artist.artwork {
                    Image(uiImage: artwork)
                        .resizable().interpolation(.high).scaledToFill()
                        .frame(width: 160, height: 160)
                        .clipShape(Circle())
                        .overlay {
                            // ✅ Borde con gradiente premium
                            Circle().strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.4), tintColor.opacity(0.6), .white.opacity(0.1)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ),
                                lineWidth: 3
                            )
                        }
                        // ✅ 60fps: sombra única consolidada (antes: doble)
                        .shadow(color: tintColor.opacity(0.25), radius: 18, x: 0, y: 8)
                } else {
                    ZStack {
                        Circle().fill(
                            LinearGradient(
                                colors: [tintColor.opacity(0.4), tintColor.opacity(0.15), Color.secondary.opacity(0.2)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 160, height: 160)
                        Image(systemName: "person.fill")
                            .font(.system(size: 52, weight: .light))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .shadow(color: tintColor.opacity(0.2), radius: 15, x: 0, y: 8)
                }
            }
            .padding(.top, 20)
            .scaleEffect(appearAnimation ? 1.0 : 0.85)
            .opacity(appearAnimation ? 1.0 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: appearAnimation)

            // ✅ Info del artista con mejor jerarquía visual
            VStack(spacing: 8) {
                Text(artist.name)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                HStack(spacing: 10) {
                    statPill(icon: "music.note", text: "\(songs.count) \(Localization.localized("songs"))")
                    if !albums.isEmpty {
                        statPill(icon: "square.stack", text: "\(albums.count) \(Localization.localized("details.albumsStat"))")
                    }
                    if totalDuration > 60 {
                        statPill(icon: "clock", text: formatLongDuration(totalDuration))
                    }
                }
            }
            .padding(.horizontal, 24)
            .offset(y: appearAnimation ? 0 : 10)
            .opacity(appearAnimation ? 1.0 : 0)
            .animation(.easeOut(duration: 0.5).delay(0.1), value: appearAnimation)
        }
        .frame(maxWidth: .infinity).padding(.bottom, 4)
        .background(alignment: .top) {
            GeometryReader { geometry in
                Group {
                    if let artwork = artist.artwork {
                        Image(uiImage: artwork)
                            .resizable().scaledToFill().blur(radius: 50).opacity(0.3)
                            .overlay(
                                LinearGradient(
                                    colors: [
                                        tintColor.opacity(0.25),
                                        tintColor.opacity(0.1),
                                        Color(UIColor.systemBackground).opacity(0.5)
                                    ],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                    } else {
                        LinearGradient(
                            colors: [tintColor.opacity(0.2), Color(UIColor.systemBackground)],
                            startPoint: .top, endPoint: .bottom
                        )
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height + 80)
                .clipped().ignoresSafeArea(edges: .top)
                .drawingGroup() // ✅ Optimización GPU para 60fps
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
                    Text(Localization.localized("details.play")).font(.system(size: 16, weight: .bold, design: .rounded))
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
                Text("\(album.songs.count) \(Localization.localized("library.songCount"))")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 150)
        // ✅ Micro-escala al presionar la tarjeta (feedback premium, GPU)
        .contentShape(Rectangle())
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
                        .strokeBorder(tintColor.opacity(0.2), lineWidth: 0.5)
                }
            }
        }
        // ✅ Feedback de presión al tocar (micro-escala, animación GPU)
        .buttonStyle(PressableButtonStyle(scale: 0.98))
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