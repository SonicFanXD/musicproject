import SwiftUI
import CoreImage

// MARK: - Album Detail (dise�o inmersivo premium con color de car�tula)
struct AlbumDetailView: View {
    let album: Album
    @ObservedObject var audioEngine: AudioEngine
    @Environment(\.dismiss) private var dismiss

    // ? Color dominante VIVO (histograma HSB) extra�do en segundo plano
    @State private var liveDominantColor: UIColor? = nil
    @State private var appearAnimation = false
    // ? OPT: blur precalculado UNA vez (en background) en vez de re-renderizar .blur(50) en cada frame
    @State private var heroBlurredArtwork: UIImage? = nil

    // ? OPT: cachear c�mputos costosos que se leen m�ltiples veces por frame
    @State private var cachedSongs: [Song] = []
    @State private var cachedTotalDuration: TimeInterval = 0
    @State private var cachedHasMultipleDiscs: Bool = false
    @State private var cachedSongsByDisc: [(disc: Int, songs: [Song])] = []
    private var songs: [Song] { cachedSongs }
    private var totalDuration: TimeInterval { cachedTotalDuration }
    private var hasMultipleDiscs: Bool { cachedHasMultipleDiscs }
    private var songsByDisc: [(disc: Int, songs: [Song])] { cachedSongsByDisc }
    // ? FIX: color normalizado para legibilidad; usa el vivo si ya se extrajo
    private var tintColor: Color { AppTheme.readableColor(from: liveDominantColor ?? album.dominantColor) }
    // ? UIColor crudo para calcular contraste de textos/botones
    private var tintUIColor: UIColor { liveDominantColor ?? album.dominantColor ?? AppTheme.accentUIColor }
    // ? Contraste: blanco o negro seg�n luminancia del color de la portada
    private var onTintColor: Color { AppTheme.contrastingText(on: tintUIColor) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                heroSection
                actionButtons
                    .padding(.horizontal, 20).padding(.top, 20)
                LazyVStack(spacing: 10) {
                    sectionHeader(icon: "music.note.list", title: Localization.localized("details.songs"), tintColor: tintColor)
                    if hasMultipleDiscs {
                        ForEach(cachedSongsByDisc, id: \.disc) { discGroup in
                            discSection(disc: discGroup.disc, songs: discGroup.songs)
                        }
                    } else {
                        ForEach(Array(cachedSongs.enumerated()), id: \.element.id) { index, song in
                            AlbumSongRow(song: song, index: index, isCurrent: audioEngine.currentSong?.id == song.id, tintColor: tintColor) {
                                audioEngine.play(song: song, from: cachedSongs)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 28)
                // ? FIX: padding inferior amplio para que la �ltima canci�n
                // no quede oculta detr�s del PlayerBar flotante.
                .padding(.bottom, 130)
            }
        }
        .background(AppBackground().ignoresSafeArea())
        .navigationTitle(album.name)
        .navigationBarTitleDisplayMode(.inline)
        // ? Sin banda gris: el hero inmersivo fluye bajo la barra de navegaci�n
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            // ? Cachear c�mputos una sola vez
            if cachedSongs.isEmpty {
                cachedSongs = album.songs
                cachedTotalDuration = cachedSongs.reduce(0) { $0 + $1.duration }
                cachedHasMultipleDiscs = Set(cachedSongs.compactMap { $0.discNumber }).count > 1
                let grouped = Dictionary(grouping: cachedSongs) { $0.discNumber ?? 1 }
                cachedSongsByDisc = grouped.keys.sorted().map { ($0, grouped[$0]!.sorted { $0.trackNumber < $1.trackNumber }) }
            }
            // ? Animaci�n de entrada suave
            withAnimation(.easeOut(duration: 0.4)) {
                appearAnimation = true
            }
            // ? OPT: precalcular el blur del hero UNA vez en background
            prepareBlurredArtwork(from: album.artwork)
            // ? Extraer el color dominante VIVO de la car�tula en hilo de fondo
            guard liveDominantColor == nil, let artwork = album.artwork else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                // ? Cach� compartida: mismo color que NowPlaying para este �lbum
                let dominant = AppTheme.cachedDominantColor(from: artwork, key: album.id)
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.liveDominantColor = dominant
                    }
                }
            }
        }
    }

    // ? OPT: gaussian blur costoso ? se calcula UNA vez en hilo de fondo y se cachea
    private func prepareBlurredArtwork(from artwork: UIImage?) {
        guard heroBlurredArtwork == nil, let artwork = artwork else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let blurred = artwork.applyingGaussianBlur(radius: 40)
            DispatchQueue.main.async { self.heroBlurredArtwork = blurred }
        }
    }

    private var heroSection: some View {
        VStack(spacing: 22) {
            // ? Artwork con animaci�n de entrada y brillo sutil
            // ? 60fps: sombra �NICA consolidada (la doble sombra = 2 pasadas
            // de offscreen rendering por frame en A11; visualmente equivalente).
            Group {
                if let artwork = album.artwork {
                    Image(uiImage: artwork)
                        .resizable().interpolation(.high).scaledToFill()
                        .frame(width: 260, height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                        .overlay {
                            // ? Brillo premium en el borde (estilo NowPlayingView)
                            RoundedRectangle(cornerRadius: 32, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [.white.opacity(0.35), .white.opacity(0.08), .clear],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                        }
                        .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 14)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [tintColor.opacity(0.35), tintColor.opacity(0.12), Color.secondary.opacity(0.18)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 260, height: 260)
                        Image(systemName: "square.stack")
                            .font(.system(size: 70, weight: .light))
                            .foregroundStyle(.secondary.opacity(0.7))
                    }
                    .shadow(color: .black.opacity(0.25), radius: 22, x: 0, y: 12)
                }
            }
            .padding(.top, 16)
            .scaleEffect(appearAnimation ? 1.0 : 0.9)
            .opacity(appearAnimation ? 1.0 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: appearAnimation)

            // ? Info del �lbum con mejor jerarqu�a visual
            VStack(spacing: 10) {
                Text(album.name)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
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

            // ? Estad�sticas con dise�o mejorado
            HStack(spacing: 14) {
                statPill(icon: "music.note", text: "\(songs.count) \(Localization.localized("library.songCount"))")
                if totalDuration > 60 {
                    statPill(icon: "clock", text: formatLongDuration(totalDuration))
                }
                if let releaseDate = album.releaseDate {
                    statPill(icon: "calendar", text: formatYear(releaseDate))
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
                        Image(uiImage: heroBlurredArtwork ?? artwork)
                            .resizable().scaledToFill().opacity(0.35)
                            .overlay(
                                LinearGradient(
                                    colors: [
                                        tintColor.opacity(0.3),
                                        tintColor.opacity(0.1),
                                        Color(UIColor.secondarySystemBackground).opacity(0.6)
                                    ],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                    } else {
                        LinearGradient(
                            colors: [tintColor.opacity(0.2), Color(UIColor.secondarySystemBackground)],
                            startPoint: .top, endPoint: .bottom
                        )
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height + 80)
                .clipped().ignoresSafeArea(edges: .top)
                .drawingGroup() // ? Optimizaci�n GPU para 60fps
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
                    .font(.system(size: 18, weight: .bold)).foregroundStyle(tintColor)
                    .frame(width: 56, height: 56)
                    .background {
                        Circle().fill(
                            LinearGradient(colors: [tintColor.opacity(0.2), tintColor.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    }
                    .frame(width: 64, height: 64)
                    .background {
                        Circle().fill(AnyShapeStyle(.ultraThinMaterial))
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(PressableButtonStyle(scale: 0.9))
        }
        .padding(.horizontal, 4)
    }

    private func discSection(disc: Int, songs: [Song]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "opticaldisc").font(.system(size: 13, weight: .semibold)).foregroundStyle(tintColor.opacity(0.9))
                Text("\(Localization.localized("details.disc")) \(disc)").font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4).padding(.top, 6)
            .nativeGlassCapsule()
            .padding(.horizontal, 8)
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                AlbumSongRow(song: song, index: index, isCurrent: audioEngine.currentSong?.id == song.id, tintColor: tintColor) {
                    audioEngine.play(song: song, from: songs)
                }
            }
        }
    }

    private func statPill(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
            Text(text).font(.system(size: 13, weight: .medium).monospacedDigit())
        }
        .foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 6)
        .nativeGlassCapsule()
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

    // ✅ Formatear año de salida del álbum
    private func formatYear(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter.string(from: date)
    }
}

// MARK: - Song Row optimizado (View struct para diffing correcto y 60fps)
struct AlbumSongRow: View {
    let song: Song
    let index: Int
    let isCurrent: Bool
    let tintColor: Color
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            HStack(spacing: 14) {
                if isCurrent {
                    EqualizerBars(color: tintColor)
                } else {
                    Text("\(index + 1)")
                        .font(.system(size: 14, weight: .medium).monospacedDigit())
                        .foregroundStyle(Color.secondary.opacity(0.5)).frame(width: 24)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(song.title)
                        .font(.system(size: 15, weight: isCurrent ? .bold : .semibold, design: .rounded))
                        .foregroundStyle(isCurrent ? tintColor : .primary).lineLimit(1)
                    Text(song.album.isEmpty ? song.displaySubtitle : song.album)
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }

                Spacer()

                Text(formatDuration(song.duration))
                    .font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isCurrent ? tintColor.opacity(0.12) : Color.clear)
            }
            .contentShape(Rectangle())
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isCurrent ? Color.clear : AnyShapeStyle(.ultraThinMaterial))
            }
            .overlay {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(tintColor.opacity(0.3), lineWidth: 1)
                }
            }
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98))
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

// MARK: - Equalizer Bars (animaci�n optimizada sin bloqueo de hilo)
struct EqualizerBars: View {
    let color: Color
    @State private var animate = false

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<3, id: \.self) { bar in
                RoundedRectangle(cornerRadius: 1).fill(color)
                    .frame(width: 2.5, height: animate ? (bar % 2 == 0 ? 13 : 8) : (bar % 2 == 0 ? 8 : 13))
            }
        }
        .frame(width: 24)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

// MARK: - Header de secci�n reutilizable (con gradiente sutil y color din�mico)
private func sectionHeader(icon: String, title: String, tintColor: Color? = nil) -> some View {
    let gradientColor = tintColor ?? AppTheme.accent
    return HStack(spacing: 8) {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(
                LinearGradient(
                    colors: [gradientColor, gradientColor.opacity(0.7)],
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
    // ? OPT: blur precalculado UNA vez (en background)
    @State private var heroBlurredArtwork: UIImage? = nil

    // ? OPT: cachear c�mputos
    @State private var cachedAlbums: [Album] = []
    @State private var cachedSongs: [Song] = []
    @State private var cachedTotalDuration: TimeInterval = 0
    private var songs: [Song] { cachedSongs }
    private var albums: [Album] { cachedAlbums }
    private var totalDuration: TimeInterval { cachedTotalDuration }
    private var tintColor: Color { AppTheme.readableColor(from: liveDominantColor ?? artist.albums.first?.dominantColor) }
    private var tintUIColor: UIColor { liveDominantColor ?? artist.albums.first?.dominantColor ?? AppTheme.accentUIColor }
    // ? Contraste para botones (igual que AlbumDetailView)
    private var onTintColor: Color { AppTheme.contrastingText(on: tintUIColor) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                artistHeroSection
                artistActionButtons
                    .padding(.horizontal, 20).padding(.top, 18)
                if !albums.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        sectionHeader(icon: "square.stack", title: Localization.localized("details.albums"), tintColor: tintColor)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(cachedAlbums) { album in
                                    NavigationLink {
                                        AlbumDetailView(album: album, audioEngine: audioEngine)
                                    } label: {
                                        ArtistAlbumCard(album: album)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20).padding(.vertical, 4)
                        }
                    }
                    .padding(.top, 28)
                }
                LazyVStack(spacing: 10) {
                    sectionHeader(icon: "music.note.list", title: Localization.localized("details.songs"), tintColor: tintColor)
                    ForEach(Array(cachedSongs.enumerated()), id: \.element.id) { index, song in
                        ArtistSongRow(song: song, index: index, isCurrent: audioEngine.currentSong?.id == song.id, tintColor: tintColor) {
                            audioEngine.play(song: song, from: cachedSongs)
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 28)
                // ? FIX: padding inferior amplio para el PlayerBar flotante
                .padding(.bottom, 130)
            }
        }
        .background(AppBackground().ignoresSafeArea())
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
        // ? Sin banda gris (coherente con AlbumDetailView)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            // ? Cachear c�mputos una sola vez
            if cachedAlbums.isEmpty {
                cachedAlbums = artist.albums
                cachedSongs = artist.songs
                cachedTotalDuration = cachedSongs.reduce(0) { $0 + $1.duration }
            }
            withAnimation(.easeOut(duration: 0.4)) {
                appearAnimation = true
            }
            // ? OPT: precalcular el blur del hero UNA vez en background
            prepareBlurredArtwork(from: artist.artwork)
            // ? Extraer color del primer �lbum
            guard liveDominantColor == nil, let artwork = artist.artwork else { return }
                DispatchQueue.global(qos: .userInitiated).async {
                    // ? Cach� compartida por id de artista
                    let dominant = AppTheme.cachedDominantColor(from: artwork, key: "artist-" + artist.id)
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            self.liveDominantColor = dominant
                        }
                    }
                }
            }
        }

    // ? OPT: gaussian blur costoso ? se calcula UNA vez en hilo de fondo y se cachea
    private func prepareBlurredArtwork(from artwork: UIImage?) {
        guard heroBlurredArtwork == nil, let artwork = artwork else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let blurred = artwork.applyingGaussianBlur(radius: 40)
            DispatchQueue.main.async { self.heroBlurredArtwork = blurred }
        }
    }

    private var artistHeroSection: some View {
        VStack(spacing: 22) {
            // ? Avatar del artista con animaci�n y efectos mejorados
            Group {
                if let artwork = artist.artwork {
                    Image(uiImage: artwork)
                        .resizable().interpolation(.high).scaledToFill()
                        .frame(width: 170, height: 170)
                        .clipShape(Circle())
                        .overlay {
                            // ? Borde con gradiente premium (estilo NowPlayingView)
                            Circle().strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.45), tintColor.opacity(0.7), .white.opacity(0.15)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ),
                                lineWidth: 3.5
                            )
                        }
                        // ? 60fps: sombra �nica consolidada (antes: doble)
                        .shadow(color: tintColor.opacity(0.3), radius: 22, x: 0, y: 10)
                } else {
                    ZStack {
                        Circle().fill(
                            LinearGradient(
                                colors: [tintColor.opacity(0.45), tintColor.opacity(0.18), Color.secondary.opacity(0.25)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 170, height: 170)
                        Image(systemName: "person.fill")
                            .font(.system(size: 56, weight: .light))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .shadow(color: tintColor.opacity(0.25), radius: 18, x: 0, y: 10)
                }
            }
            .padding(.top, 20)
            .scaleEffect(appearAnimation ? 1.0 : 0.85)
            .opacity(appearAnimation ? 1.0 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: appearAnimation)

            // ? Info del artista con mejor jerarqu�a visual
            VStack(spacing: 10) {
                Text(artist.name)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                HStack(spacing: 14) {
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
                        Image(uiImage: heroBlurredArtwork ?? artwork)
                            .resizable().scaledToFill().opacity(0.3)
                            .overlay(
                                LinearGradient(
                                    colors: [
                                        tintColor.opacity(0.25),
                                        tintColor.opacity(0.1),
                                        Color(UIColor.secondarySystemBackground).opacity(0.5)
                                    ],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                    } else {
                        LinearGradient(
                            colors: [tintColor.opacity(0.2), Color(UIColor.secondarySystemBackground)],
                            startPoint: .top, endPoint: .bottom
                        )
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height + 80)
                .clipped().ignoresSafeArea(edges: .top)
                .drawingGroup() // ? Optimizaci�n GPU para 60fps
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
                    .font(.system(size: 18, weight: .bold)).foregroundStyle(tintColor)
                    .frame(width: 56, height: 56)
                    .background {
                        Circle().fill(
                            LinearGradient(colors: [tintColor.opacity(0.2), tintColor.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    }
                    .frame(width: 64, height: 64)
                    .background {
                        Circle().fill(AnyShapeStyle(.ultraThinMaterial))
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(PressableButtonStyle(scale: 0.9))
        }
        .padding(.horizontal, 4)
    }

    private func statPill(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
            Text(text).font(.system(size: 13, weight: .medium).monospacedDigit())
        }
        .foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 6)
        .nativeGlassCapsule()
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

// MARK: - Album Card optimizado para Artist Detail
struct ArtistAlbumCard: View {
    let album: Album

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if let artwork = album.artwork {
                    Image(uiImage: artwork)
                        .resizable().scaledToFill()
                        .frame(width: 150, height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.25), radius: 14, x: 0, y: 7)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(
                                LinearGradient(colors: [AppTheme.accent.opacity(0.25), Color.secondary.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .frame(width: 150, height: 150)
                        Image(systemName: "square.stack").font(.system(size: 36)).foregroundStyle(.secondary.opacity(0.7))
                    }
                    .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 6)
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
        // ? Micro-escala al presionar la tarjeta (feedback premium, GPU)
        .contentShape(Rectangle())
    }
}

// MARK: - Song Row optimizado para Artist Detail
struct ArtistSongRow: View {
    let song: Song
    let index: Int
    let isCurrent: Bool
    let tintColor: Color
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            HStack(spacing: 14) {
                if isCurrent {
                    EqualizerBars(color: tintColor)
                } else {
                    Text("\(index + 1)")
                        .font(.system(size: 14, weight: .medium).monospacedDigit())
                        .foregroundStyle(Color.secondary.opacity(0.5)).frame(width: 24)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(song.title)
                        .font(.system(size: 15, weight: isCurrent ? .bold : .semibold, design: .rounded))
                        .foregroundStyle(isCurrent ? tintColor : .primary).lineLimit(1)
                    Text(song.album.isEmpty ? song.displaySubtitle : song.album)
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }

                Spacer()

                Text(formatDuration(song.duration))
                    .font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isCurrent ? tintColor.opacity(0.12) : Color.clear)
            }
            .contentShape(Rectangle())
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isCurrent ? Color.clear : AnyShapeStyle(.ultraThinMaterial))
            }
            .overlay {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(tintColor.opacity(0.3), lineWidth: 1)
                }
            }
        }
        // ? Feedback de presi�n al tocar (micro-escala, animaci�n GPU)
        .buttonStyle(PressableButtonStyle(scale: 0.98))
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
// MARK: - Blur en background (OPT: evita re-renderizar .blur(50) en cada frame)
extension UIImage {
    private static let blurContext = CIContext(options: [.useSoftwareRenderer: false])

    func applyingGaussianBlur(radius: Double) -> UIImage {
        guard let ciImage = CIImage(image: self) else { return self }
        let filter = CIFilter(name: "CIGaussianBlur")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter?.outputImage,
              let cg = Self.blurContext.createCGImage(output.clampedToExtent(), from: ciImage.extent.insetBy(dx: -radius, dy: -radius)) else { return self }
        return UIImage(cgImage: cg, scale: scale, orientation: imageOrientation)
    }
}
