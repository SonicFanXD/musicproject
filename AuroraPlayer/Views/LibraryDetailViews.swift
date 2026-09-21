import SwiftUI
import CoreImage

// MARK: - Acento de las vistas de detalle (SIEMPRE de DOS colores)
/// ✅ Regla única para Album/Artist detail:
/// · Con "Acento desde portada" ACTIVO → color de ESTA carátula (álbum o
///   artista) + su secundario REAL, extraído con la misma caché que el primario.
/// · Con el modo DESACTIVADO → acento manual con su segunda parada al 40%,
///   idéntico a `AppTheme.accentGradient` (consistencia con el resto de la app).
/// ✅ Nunca `[color, color.opacity(x)]` de un solo color: siempre DOS tonos reales,
/// como los chips, botones y cabeceras del resto de la interfaz.
private struct DetailAccent {
    let primary: Color
    let secondary: Color

    static func resolve(
        artworkColor: UIColor?,
        artworkSecondaryColor: UIColor?,
        fromArtwork: Bool
    ) -> DetailAccent {
        guard fromArtwork, let artworkColor else {
            let accent = AppTheme.accent
            return DetailAccent(primary: accent, secondary: accent.opacity(0.4))
        }
        let primary = AppTheme.readableColor(from: artworkColor)
        let secondary = artworkSecondaryColor.map { AppTheme.readableColor(from: $0) }
        return DetailAccent(primary: primary, secondary: secondary ?? primary.opacity(0.7))
    }

    /// Dos paradas con la opacidad que pida cada sitio (fondos, bordes, washes).
    func colors(primaryOpacity: Double = 1, secondaryOpacity: Double = 1) -> [Color] {
        [primary.opacity(primaryOpacity), secondary.opacity(secondaryOpacity)]
    }

    /// ✅ Superficies CON TEXTO BLANCO encima (pastilla de Play, donde el texto es
    /// blanco fijo): si el secundario de la carátula difiere MUCHO en brillo del
    /// primario, media pastilla quedaría ilegible. En ese caso se conserva el TONO
    /// del secundario y se ancla su brillo al del primario: el degradado sigue
    /// siendo de DOS colores reales, pero la legibilidad del texto blanco queda
    /// exactamente como antes de este cambio.
    func textSafeGradient(primaryOpacity: Double = 1, secondaryOpacity: Double = 1) -> LinearGradient {
        LinearGradient(
            colors: Self.textSafeColors(primary: primary, secondary: secondary,
                                        primaryOpacity: primaryOpacity, secondaryOpacity: secondaryOpacity),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private static func textSafeColors(
        primary: Color,
        secondary: Color,
        primaryOpacity: Double,
        secondaryOpacity: Double
    ) -> [Color] {
        var secondaryStop = secondary
        var h1: CGFloat = 0, s1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 1
        var h2: CGFloat = 0, s2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 1
        let primaryUI = UIColor(primary)
        let secondaryUI = UIColor(secondary)
        if primaryUI.getHue(&h1, saturation: &s1, brightness: &b1, alpha: &a1),
           secondaryUI.getHue(&h2, saturation: &s2, brightness: &b2, alpha: &a2),
           abs(b1 - b2) > 0.3 {
            secondaryStop = Color(UIColor(hue: h2, saturation: s2, brightness: b1, alpha: a2))
        }
        return [primary.opacity(primaryOpacity), secondaryStop.opacity(secondaryOpacity)]
    }

    func gradient(
        start: UnitPoint = .topLeading,
        end: UnitPoint = .bottomTrailing,
        primaryOpacity: Double = 1,
        secondaryOpacity: Double = 1
    ) -> LinearGradient {
        LinearGradient(
            colors: colors(primaryOpacity: primaryOpacity, secondaryOpacity: secondaryOpacity),
            startPoint: start,
            endPoint: end
        )
    }
}

// MARK: - Offset de scroll compartido por las vistas de detalle
/// Publica el minY del hero en el espacio "detailScroll". Se usa SOLO para
/// transform/opacity del fondo del hero y para la opacidad del título de la
/// barra: nunca para recalcular blur, sombras o materiales.
private struct DetailScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Progreso 0…1 del desplazamiento del hero (0 = sin desplazar, 1 = 180pt arriba).
private func detailHeroProgress(for offset: CGFloat) -> CGFloat {
    min(max(-min(offset, 0) / 180, 0), 1)
}

/// Opacidad del título de la barra: emerge cuando el hero está a punto de salir.
private func detailTitleReveal(for progress: CGFloat) -> CGFloat {
    min(max((progress - 0.5) / 0.4, 0), 1)
}

// MARK: - Album Detail (dise�o inmersivo premium con color de car�tula)
struct AlbumDetailView: View {
    let album: Album
    @ObservedObject var audioEngine: AudioEngine
    // ✅ Inyectado (mismo patrón que NowPlayingView/PlayerBar): lo necesitan las
    // acciones rápidas de las filas (añadir a la cola y me gusta).
    @ObservedObject var fileAccessService: FileAccessService
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
    // ✅ CALIDAD MAYORITARIA del álbum: bits + kHz calculados por mayoría.
    // Puede haber canciones con distinto sample rate en el mismo álbum; el
    // kHz mostrado es el de la MAYORÍA de canciones, y los bits el más común
    // entre esas canciones (ver computeMajorityQuality()).
    @State private var cachedQuality: (bits: Int, khz: Double)? = nil
    // ✅ PARALLAX / BARRA EMERGENTE: offset vertical del scroll (0 = arriba del
    // todo). Alimenta únicamente transform y opacidad del fondo del hero.
    @State private var scrollOffset: CGFloat = 0

    // ✅ Acento de DOS colores: primario + secundario real de la carátula.
    // El secundario solo se usa con "Acento desde portada" activo.
    @ObservedObject private var theme = ThemeManager.shared
    @State private var liveSecondaryColor: UIColor? = nil
    private var songs: [Song] { cachedSongs }
    private var totalDuration: TimeInterval { cachedTotalDuration }
    private var hasMultipleDiscs: Bool { cachedHasMultipleDiscs }
    private var songsByDisc: [(disc: Int, songs: [Song])] { cachedSongsByDisc }
    // ? FIX: color normalizado para legibilidad; usa el vivo si ya se extrajo
    /// ✅ Acento de la vista, SIEMPRE de dos colores (primario + secundario real
    /// de la carátula). Con "Acento desde portada" activo usa el color de ESTE
    /// álbum y su secundario; con el modo desactivado, el acento manual con su
    /// segunda parada al 40%, igual que el resto de la app.
    private var accent: DetailAccent {
        DetailAccent.resolve(
            artworkColor: liveDominantColor ?? album.dominantColor,
            artworkSecondaryColor: liveSecondaryColor,
            fromArtwork: theme.accentFromArtwork
        )
    }

    /// ✅ Acento sólido (textos, iconos y resaltados de fila): el mismo primario
    /// del gradiente, para que la pantalla entera respete el modo activo.
    private var tintColor: Color { accent.primary }

    /// ✅ Secundario de la carátula del álbum (segundo color dominante) para el
    /// gradiente. Solo se calcula con el modo portada activo y queda en la caché
    /// compartida, así que volver a la vista no repite el trabajo.
    private func loadSecondaryArtworkColorIfNeeded() {
        guard theme.accentFromArtwork, liveSecondaryColor == nil, let artwork = album.artwork else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            let dominant = AppTheme.cachedDominantColor(from: artwork, key: album.id)
            let secondary = dominant.flatMap {
                AppTheme.cachedSecondaryDominantColor(from: artwork, key: "album-secondary-" + album.id, primary: $0)
            }
            DispatchQueue.main.async {
                guard let secondary, self.liveSecondaryColor == nil else { return }
                withAnimation(.easeInOut(duration: 0.3)) { self.liveSecondaryColor = secondary }
            }
        }
    }
    // ? UIColor crudo para calcular contraste de textos/botones
    /// ✅ Estado real del motor para ESTE álbum (ver el pill de bit-perfect).
    private var isAlbumBitPerfect: Bool {
        guard let current = audioEngine.currentSong else { return false }
        return audioEngine.isBitPerfect && songs.contains { $0.id == current.id }
    }

    private var tintUIColor: UIColor { liveDominantColor ?? album.dominantColor ?? AppTheme.accentUIColor }
    // ? Contraste: blanco o negro seg�n luminancia del color de la portada
    private var onTintColor: Color { AppTheme.contrastingText(on: tintUIColor) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                heroSection
                    // ✅ Rastreo del scroll: solo publica el minY del hero en el
                    // espacio "detailScroll". Sin cálculos por frame.
                    .background(
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: DetailScrollOffsetKey.self,
                                value: geometry.frame(in: .named("detailScroll")).minY
                            )
                        }
                    )
                actionButtons
                    .padding(.horizontal, 20).padding(.top, 12)
                LazyVStack(spacing: 10) {
                    sectionHeader(icon: "music.note.list", title: Localization.localized("details.songs"), accent: accent)
                    if hasMultipleDiscs {
                        ForEach(cachedSongsByDisc, id: \.disc) { discGroup in
                            discSection(disc: discGroup.disc, songs: discGroup.songs)
                        }
                    } else {
                        ForEach(Array(cachedSongs.enumerated()), id: \.element.id) { index, song in
                            AlbumSongRow(
                                song: song,
                                index: index,
                                isCurrent: audioEngine.currentSong?.id == song.id,
                                isPlaying: audioEngine.isPlaying,
                                tintColor: tintColor,
                                isLiked: fileAccessService.isLiked(song),
                                onAddToQueue: { audioEngine.addToQueue(song) },
                                onToggleLike: { Haptics.light(); fileAccessService.toggleLike(song) }
                            ) {
                                audioEngine.play(song: song, from: cachedSongs)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 20)
                // ? FIX: padding inferior amplio para que la �ltima canci�n
                // no quede oculta detr�s del PlayerBar flotante.
                .padding(.bottom, 130)
            }
        }
        .coordinateSpace(name: "detailScroll")
        // ✅ Cuantizado a 1pt: el scroll repinta un par de veces menos por frame
        // (una subida de 40pt ya no genera 40 renders).
        .onPreferenceChange(DetailScrollOffsetKey.self) { offset in
            if abs(offset - scrollOffset) > 1 { scrollOffset = offset }
        }
        .background(AppBackground().ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        // ✅ BARRERA EMERGENTE (estilo Apple Music): el título aparece solo
        // cuando el hero ya casi salió de pantalla. Solo opacidad, sin recalculos.
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(album.name)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                    .opacity(detailTitleReveal(for: detailHeroProgress(for: scrollOffset)))
            }
        }
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
                cachedQuality = Self.computeMajorityQuality(cachedSongs)
            }
            // ? Animaci�n de entrada suave
            withAnimation(.easeOut(duration: 0.4)) {
                appearAnimation = true
            }
            // ? OPT: precalcular el blur del hero UNA vez en background
            prepareBlurredArtwork(from: album.artwork)
            // ? Extraer el color dominante VIVO de la car�tula en hilo de fondo
            loadSecondaryArtworkColorIfNeeded()
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
        VStack(spacing: 14) {
            // ? Artwork con animaci�n de entrada y brillo sutil
            // ? 60fps: sombra �NICA consolidada (la doble sombra = 2 pasadas
            // de offscreen rendering por frame en A11; visualmente equivalente).
            Group {
                if let artwork = album.artwork {
                    // ✅ ANTI-JETSAM: 200pt de display → miniatura de 400px
                    // cacheada en vez de decodificar la carátula completa.
                    Image(uiImage: AppTheme.thumbnail(from: artwork, size: CGSize(width: 400, height: 400)))
                        .resizable().interpolation(.high).scaledToFill()
                        .frame(width: 200, height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [.white.opacity(0.35), .white.opacity(0.08), .clear],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                        }
                        .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: 10)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: accent.colors(primaryOpacity: 0.35, secondaryOpacity: 0.2) + [Color.secondary.opacity(0.18)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 200, height: 200)
                        Image(systemName: "square.stack")
                            .font(.system(size: 54, weight: .light))
                            .foregroundStyle(.secondary.opacity(0.7))
                    }
                    .shadow(color: .black.opacity(0.25), radius: 14, x: 0, y: 8)
                }
            }
            .padding(.top, 8)
            .scaleEffect(appearAnimation ? 1.0 : 0.9)
            .opacity(appearAnimation ? 1.0 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: appearAnimation)

            // ? Info del �lbum con mejor jerarqu�a visual
            VStack(spacing: 6) {
                Text(album.name)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(album.artist)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 24)
            .offset(y: appearAnimation ? 0 : 10)
            .opacity(appearAnimation ? 1.0 : 0)
            .animation(.easeOut(duration: 0.5).delay(0.1), value: appearAnimation)

            // ? Estad�sticas con dise�o mejorado
            FlowLayout(horizontalSpacing: 10, verticalSpacing: 8) {
                statPill(icon: "music.note", text: localizedSongCount(songs.count))
                if totalDuration > 60 {
                    statPill(icon: "clock", text: formatLongDuration(totalDuration))
                }
                if let releaseDate = album.releaseDate {
                    statPill(icon: "calendar", text: formatYear(releaseDate))
                }
                // ✅ CALIDAD MAYORITARIA (bits · kHz): si el álbum mezcla
                // canciones con distinto sample rate, se muestra el de la
                // mayoría — p. ej. "24-bit · 44.1 kHz" o "44.1 kHz".
                if let q = cachedQuality {
                    // ✅ Helper compartido: mismo "44.1 kHz" en todos lados.
                    let khzText = AlbumDetailView.khzLabel(q.khz)
                    let text = q.bits > 0 ? "\(q.bits)-bit · \(khzText)" : khzText
                    statPill(icon: "waveform", text: text)
                }
                // ✅ BIT-PERFECT REAL (no una promesa del formato del archivo):
                // aparece solo si lo que suena es una canción DE ESTE álbum y la
                // salida está en bit-perfect ahora mismo (misma tasa que el
                // archivo, sin EQ/mono/protección y por cable).
                if isAlbumBitPerfect {
                    statPill(icon: "checkmark.seal.fill", text: "Bit-perfect", highlighted: true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
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
                                    colors: accent.colors(primaryOpacity: 0.3, secondaryOpacity: 0.12)
                                        + [Color(UIColor.secondarySystemBackground).opacity(0.6)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                    } else {
                        LinearGradient(
                            colors: accent.colors(primaryOpacity: 0.2, secondaryOpacity: 0.1) + [Color(UIColor.secondarySystemBackground)],
                            startPoint: .top, endPoint: .bottom
                        )
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height + 80)
                // ✅ PARALLAX BARATO: esta capa YA está rasterizada por el
                // .drawingGroup() de abajo (el blur se calculó una sola vez en
                // background), así que aquí solo se le aplican transform y
                // opacidad — no se recalcula ni el blur ni ningún material.
                .scaleEffect(1 + detailHeroProgress(for: scrollOffset) * 0.14)
                .opacity(1 - detailHeroProgress(for: scrollOffset) * 0.55)
                .clipped().ignoresSafeArea(edges: .top)
                .drawingGroup() // ? Optimizaci�n GPU para 60fps
            }
        }
    }

    // ✅ CALIDAD MAYORITARIA del álbum: el kHz que tienen la MAYORÍA de las
    // canciones; los bits, el valor más común ENTRE esas canciones. Así un
    // álbum con 9 temas a 44.1 kHz y 1 a 96 kHz muestra "44.1 kHz", no "96".
    // Retorna nil si ninguna canción reporta sample rate.
    private static func computeMajorityQuality(_ songs: [Song]) -> (bits: Int, khz: Double)? {
        let withRate = songs.filter { $0.sampleRate > 0 }
        guard !withRate.isEmpty else { return nil }
        guard let majority = Dictionary(grouping: withRate, by: { $0.sampleRate })
            .max(by: { $0.value.count < $1.value.count }) else { return nil }
        let bitsDict = Dictionary(grouping: majority.value.compactMap { $0.bitDepth > 0 ? $0.bitDepth : nil }, by: { $0 })
        let bits: Int
        if bitsDict.isEmpty {
            bits = 0  // No hay bitDepth disponible para las canciones del grupo mayoritario
        } else {
            bits = bitsDict.max { $0.value.count < $1.value.count }?.key ?? 0
        }
        return (bits, majority.key)
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
                    Image(systemName: "play.fill").font(.system(size: 15, weight: .bold))
                    Text(Localization.localized("details.play")).font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .foregroundStyle(onTintColor).frame(maxWidth: .infinity).frame(height: 48)
                .background {
                    Capsule().fill(
                        accent.textSafeGradient()
                    )
                }
                .contentShape(Capsule())
                .shadow(color: tintColor.opacity(0.5), radius: 10, x: 0, y: 5)
            }
            .buttonStyle(PressableButtonStyle(scale: 0.97))

            Button {
                Haptics.medium()
                if !audioEngine.isShuffleEnabled { audioEngine.toggleShuffle() }
                if let randomSong = songs.randomElement() {
                    audioEngine.play(song: randomSong, from: songs)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "shuffle").font(.system(size: 15, weight: .bold))
                    Text(Localization.localized("details.shuffle")).font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .foregroundStyle(tintColor)
                // ✅ GEMELO del botón de reproducir: misma altura (48) y mismo eje
                // que el primario, con jerarquía secundaria (relleno suave +
                // borde de acento en vez del sólido). Antes era un círculo de
                // 56pt que quedaba desalineado respecto a la cápsula de 46pt.
                .frame(maxWidth: .infinity).frame(height: 48)
                // ✅ Se MANTIENE el material de vidrio (identidad de la app) y el
                // acento va como velo encima; antes eran dos círculos apilados
                // (material + color), ahora una sola cápsula con el mismo vidrio.
                .background {
                    Capsule().fill(AnyShapeStyle(.ultraThinMaterial))
                }
                .overlay {
                    Capsule().fill(accent.gradient(primaryOpacity: 0.22, secondaryOpacity: 0.12))
                }
                .overlay {
                    Capsule().strokeBorder(tintColor.opacity(0.35), lineWidth: 1)
                }
                .contentShape(Capsule())
            }
            .accessibilityLabel(Localization.localized("details.shuffle"))
            .buttonStyle(PressableButtonStyle(scale: 0.97))
        }
        .padding(.horizontal, 4)
    }

    private func discSection(disc: Int, songs: [Song]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "opticaldisc").font(.system(size: 13, weight: .semibold)).foregroundStyle(tintColor.opacity(0.9))
                Text("\(Localization.localized("details.disc")) \(disc)").font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
            }
            // ✅ FIX: padding simétrico para que el texto quede centrado
            // dentro de la cápsula de vidrio (antes era solo .top, quedaba descentrado)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .nativeGlassCapsule()
            .padding(.horizontal, 4)
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                // ✅ FIX multi-disco: la cola es el ÁLBUM COMPLETO (cachedSongs
                // viene ordenado disco 1 → disco 2 → pistas). Antes se pasaba
                // solo `songs` (el disco actual) → al terminar ese disco la
                // repetición volvía a empezar el mismo disco en vez de seguir
                // con el siguiente. Ahora al tocar una canción se reproduce
                // todo el álbum en corrido desde esa posición.
                AlbumSongRow(
                    song: song,
                    index: index,
                    isCurrent: audioEngine.currentSong?.id == song.id,
                    isPlaying: audioEngine.isPlaying,
                    tintColor: tintColor,
                    isLiked: fileAccessService.isLiked(song),
                    onAddToQueue: { audioEngine.addToQueue(song) },
                    onToggleLike: { Haptics.light(); fileAccessService.toggleLike(song) }
                ) {
                    audioEngine.play(song: song, from: cachedSongs)
                }
            }
        }
    }

    private func statPill(icon: String, text: String, highlighted: Bool = false) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold))
            // lineLimit(1) + fixedSize: el texto NUNCA se parte ni corta con
            // guiones — la píldora mantiene su tamaño intrínseco y el
            // FlowLayout la acomoda entera en la siguiente fila si no cabe.
            // ✅ 13 semibold: la píldora es dato de cabecera, no letra pequeña.
            Text(text).font(.system(size: 13, weight: .semibold).monospacedDigit())
                .lineLimit(1)
        }
        .foregroundStyle(highlighted ? tintColor : Color.secondary)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .fixedSize()
        .nativeGlassCapsule()
    }

    // ✅ Formatea kHz UNA sola vez y sin duplicar: 44100 → "44.1 kHz",
    // 48000 → "48 kHz", 96000 → "96 kHz". El `Int(.../1000)` anterior
    // truncaba 44.1 → "44 kHz" y, combinado con formatDescription (que ya
    // trae "44 kHz"), el origen mostraba "44 kHz · 44 kHz".
    static func khzLabel(_ sampleRate: Double) -> String {
        guard sampleRate > 0 else { return "—" }
        let kHz = sampleRate / 1000.0
        if kHz.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(kHz)) kHz"
        }
        return String(format: "%.1f kHz", kHz)
    }

    // ✅ Formatear año de salida del álbum (locale/calendario/zona FIJOS:
    // "yyyy" estable y consistente con el parser de fechas)
    private func formatYear(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy"
        return formatter.string(from: date)
    }

    private func formatLongDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let totalMinutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        if totalMinutes >= 60 {
            let hours = totalMinutes / 60
            let mins = totalMinutes % 60
            if remainingSeconds > 0 {
                return "\(hours) h \(mins) min \(remainingSeconds) s"
            }
            return mins > 0 ? "\(hours) h \(mins) min" : "\(hours) h"
        }
        if remainingSeconds > 0 {
            return "\(totalMinutes) min \(remainingSeconds) s"
        }
        return "\(totalMinutes) min"
    }
}

// MARK: - Song Row optimizado (View struct para diffing correcto y 60fps)
struct AlbumSongRow: View {
    let song: Song
    let index: Int
    let isCurrent: Bool
    /// ✅ Estado de reproducción para que el indicador de "suena ahora" solo
    /// anime mientras suena de verdad (ver EqualizerBars).
    let isPlaying: Bool
    let tintColor: Color
    // ✅ Acciones rápidas por menú contextual. No usamos .swipeActions porque
    // estas filas viven en un LazyVStack dentro de un ScrollView, y swipeActions
    // solo se activa dentro de un List.
    let isLiked: Bool
    let onAddToQueue: () -> Void
    let onToggleLike: () -> Void
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            HStack(spacing: 14) {
                if isCurrent {
                    EqualizerBars(color: tintColor, isPlaying: isPlaying)
                } else {
                    Text("\(index + 1)")
                        .font(.system(size: 14, weight: .medium).monospacedDigit())
                        .foregroundStyle(Color.secondary.opacity(0.5)).frame(width: 24)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(song.title)
                        .font(.system(size: 15, weight: isCurrent ? .bold : .semibold, design: .rounded))
                        .foregroundStyle(isCurrent ? tintColor : .primary).lineLimit(1)
                    // ✅ Debajo del título: el ARTISTA (en la vista de álbum el
                    // nombre del álbum es redundante — siempre es el mismo).
                    Text(song.artist.isEmpty ? song.displaySubtitle : song.artist)
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }

                Spacer()

                Text(formatDuration(song.duration))
                    .font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isCurrent ? tintColor.opacity(0.12) : Color(UIColor.secondarySystemBackground).opacity(0.6))
            }
            .contentShape(Rectangle())
            .overlay {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(tintColor.opacity(0.3), lineWidth: 1)
                }
            }
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98))
        // ✅ Acciones rápidas (mantener pulsada la fila): añadir a la cola y me
        // gusta. Menú contextual en vez de swipeActions por lo explicado arriba.
        .contextMenu {
            Button {
                Haptics.light()
                onAddToQueue()
            } label: {
                Label(Localization.localized("actions.addToQueue"), systemImage: "text.badge.plus")
            }
            Button {
                onToggleLike()
            } label: {
                Label(
                    Localization.localized(isLiked ? "actions.unlike" : "actions.like"),
                    systemImage: isLiked ? "heart.slash" : "heart"
                )
            }
        }
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
    /// ✅ BATERÍA: el latido solo corre mientras hay reproducción. Antes el
    /// repeatForever seguía oscilando con la música en pausa (frames, CPU y GPU
    /// gastados para nada) porque la animación nunca se retiraba.
    let isPlaying: Bool
    @State private var animate = false
    // ✅ 3.0: observar el modo captura para detener el latido al grabar pantalla.
    @ObservedObject private var captureMode = CaptureModeManager.shared

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<3, id: \.self) { bar in
                RoundedRectangle(cornerRadius: 1).fill(color)
                    // ✅ FIX iOS 16: la altura se deriva de @State y la animación
                    // repeatForever se lanza al aparecer. Con .animation(value:)
                    // la animación persiste (se re-aplica en cada cambio de @State)
                    // — antes, sin value:, iOS 16 la abandonaba al primer re-render
                    // y las barras del tema activo quedaban CONGELADAS.
                    .frame(width: 2.5, height: DecorativeMotion.isAnimating(animate) ? (bar % 2 == 0 ? 13 : 8) : (bar % 2 == 0 ? 8 : 13))
                    .animation(
                        // ✅ 3.0: sin bucle decorativo al grabar pantalla.
                        DecorativeMotion.animation(
                            Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true),
                            isActive: animate
                        ),
                        value: DecorativeMotion.isAnimating(animate)
                    )
            }
        }
        .frame(width: 24)
        .onAppear {
            animate = isPlaying
        }
        .onChange(of: isPlaying) { playing in
            animate = playing
        }
    }
}

// MARK: - Header de secci�n reutilizable (con gradiente sutil y color din�mico)
private func sectionHeader(icon: String, title: String, accent: DetailAccent) -> some View {
    return HStack(spacing: 8) {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(accent.gradient(start: .top, end: .bottom))
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
    // ✅ Inyectado: acciones rápidas de las filas (cola y me gusta).
    @ObservedObject var fileAccessService: FileAccessService
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

    // ✅ Acento de DOS colores: primario + secundario real de la carátula.
    // El secundario solo se usa con "Acento desde portada" activo.
    @ObservedObject private var theme = ThemeManager.shared
    @State private var liveSecondaryColor: UIColor? = nil
    // ✅ PARALLAX / BARRA EMERGENTE (mismo criterio que AlbumDetailView).
    @State private var scrollOffset: CGFloat = 0
    private var totalDuration: TimeInterval { cachedTotalDuration }
    /// ✅ Acento de la vista, SIEMPRE de dos colores (mismo criterio que Album
    /// Detail): color del artista + su secundario con el modo portada activo;
    /// acento manual con su segunda parada al 40% si el modo está desactivado.
    private var accent: DetailAccent {
        DetailAccent.resolve(
            artworkColor: liveDominantColor ?? artist.albums.first?.dominantColor,
            artworkSecondaryColor: liveSecondaryColor,
            fromArtwork: theme.accentFromArtwork
        )
    }

    /// ✅ Acento sólido (textos, iconos y resaltados de fila): el mismo primario
    /// del gradiente, para que la pantalla entera respete el modo activo.
    private var tintColor: Color { accent.primary }

    /// ✅ Secundario de la carátula del artista para el gradiente de dos colores.
    private func loadSecondaryArtworkColorIfNeeded() {
        guard theme.accentFromArtwork, liveSecondaryColor == nil, let artwork = artist.artwork else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            let dominant = AppTheme.cachedDominantColor(from: artwork, key: "artist-" + artist.id)
            let secondary = dominant.flatMap {
                AppTheme.cachedSecondaryDominantColor(from: artwork, key: "artist-secondary-" + artist.id, primary: $0)
            }
            DispatchQueue.main.async {
                guard let secondary, self.liveSecondaryColor == nil else { return }
                withAnimation(.easeInOut(duration: 0.3)) { self.liveSecondaryColor = secondary }
            }
        }
    }
    private var tintUIColor: UIColor { liveDominantColor ?? artist.albums.first?.dominantColor ?? AppTheme.accentUIColor }
    // ? Contraste para botones (igual que AlbumDetailView)
    private var onTintColor: Color { AppTheme.contrastingText(on: tintUIColor) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                artistHeroSection
                    // ✅ Rastreo del scroll (mismo criterio que AlbumDetailView).
                    .background(
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: DetailScrollOffsetKey.self,
                                value: geometry.frame(in: .named("detailScroll")).minY
                            )
                        }
                    )
                artistActionButtons
                    .padding(.horizontal, 20).padding(.top, 18)
                if !albums.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        sectionHeader(icon: "square.stack", title: Localization.localized("details.albums"), accent: accent)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(cachedAlbums) { album in
                                    NavigationLink {
                                        AlbumDetailView(album: album, audioEngine: audioEngine, fileAccessService: fileAccessService)
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
                    sectionHeader(icon: "music.note.list", title: Localization.localized("details.songs"), accent: accent)
                    ForEach(Array(cachedSongs.enumerated()), id: \.element.id) { index, song in
                        ArtistSongRow(
                            song: song,
                            index: index,
                            isCurrent: audioEngine.currentSong?.id == song.id,
                            isPlaying: audioEngine.isPlaying,
                            tintColor: tintColor,
                            isLiked: fileAccessService.isLiked(song),
                            onAddToQueue: { audioEngine.addToQueue(song) },
                            onToggleLike: { Haptics.light(); fileAccessService.toggleLike(song) }
                        ) {
                            audioEngine.play(song: song, from: cachedSongs)
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 28)
                // ? FIX: padding inferior amplio para el PlayerBar flotante
                .padding(.bottom, 130)
            }
        }
        .coordinateSpace(name: "detailScroll")
        // ✅ Cuantizado a 1pt: el scroll repinta un par de veces menos por frame
        // (una subida de 40pt ya no genera 40 renders).
        .onPreferenceChange(DetailScrollOffsetKey.self) { offset in
            if abs(offset - scrollOffset) > 1 { scrollOffset = offset }
        }
        .background(AppBackground().ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        // ✅ Barra emergente con el nombre del artista (mismo criterio que Album).
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(artist.name)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                    .opacity(detailTitleReveal(for: detailHeroProgress(for: scrollOffset)))
            }
        }
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
            loadSecondaryArtworkColorIfNeeded()
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
                    // ✅ ANTI-JETSAM: avatar de 170pt → miniatura de 340px.
                    Image(uiImage: AppTheme.thumbnail(from: artwork, size: CGSize(width: 340, height: 340)))
                        .resizable().interpolation(.high).scaledToFill()
                        .frame(width: 170, height: 170)
                        .clipShape(Circle())
                        .overlay {
                            // ? Borde con gradiente premium (estilo NowPlayingView)
                            Circle().strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.45), accent.primary.opacity(0.7), accent.secondary.opacity(0.55), .white.opacity(0.15)],
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
                                colors: accent.colors(primaryOpacity: 0.45, secondaryOpacity: 0.25) + [Color.secondary.opacity(0.25)],
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
                FlowLayout(horizontalSpacing: 10, verticalSpacing: 8) {
                    statPill(icon: "music.note", text: "\(songs.count) \(Localization.localized("songs"))")
                    if !albums.isEmpty {
                        statPill(icon: "square.stack", text: "\(albums.count) \(Localization.localized("details.albumsStat"))")
                    }
                    if totalDuration > 60 {
                        statPill(icon: "clock", text: formatLongDuration(totalDuration))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
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
                                    colors: accent.colors(primaryOpacity: 0.25, secondaryOpacity: 0.12)
                                        + [Color(UIColor.secondarySystemBackground).opacity(0.5)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                    } else {
                        LinearGradient(
                            colors: accent.colors(primaryOpacity: 0.2, secondaryOpacity: 0.1) + [Color(UIColor.secondarySystemBackground)],
                            startPoint: .top, endPoint: .bottom
                        )
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height + 80)
                // ✅ PARALLAX BARATO: esta capa YA está rasterizada por el
                // .drawingGroup() de abajo (el blur se calculó una sola vez en
                // background), así que aquí solo se le aplican transform y
                // opacidad — no se recalcula ni el blur ni ningún material.
                .scaleEffect(1 + detailHeroProgress(for: scrollOffset) * 0.14)
                .opacity(1 - detailHeroProgress(for: scrollOffset) * 0.55)
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
                    Image(systemName: "play.fill").font(.system(size: 15, weight: .bold))
                    Text(Localization.localized("details.play")).font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .foregroundStyle(onTintColor).frame(maxWidth: .infinity).frame(height: 48)
                .background {
                    Capsule().fill(
                        accent.textSafeGradient()
                    )
                }
                .contentShape(Capsule())
                .shadow(color: tintColor.opacity(0.5), radius: 10, x: 0, y: 5)
            }
            .buttonStyle(PressableButtonStyle(scale: 0.97))

            Button {
                Haptics.medium()
                if !audioEngine.isShuffleEnabled { audioEngine.toggleShuffle() }
                if let randomSong = songs.randomElement() {
                    audioEngine.play(song: randomSong, from: songs)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "shuffle").font(.system(size: 15, weight: .bold))
                    Text(Localization.localized("details.shuffle")).font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .foregroundStyle(tintColor)
                // ✅ GEMELO del botón de reproducir: misma altura (48) y mismo eje
                // que el primario, con jerarquía secundaria (relleno suave +
                // borde de acento en vez del sólido). Antes era un círculo de
                // 56pt que quedaba desalineado respecto a la cápsula de 46pt.
                .frame(maxWidth: .infinity).frame(height: 48)
                // ✅ Se MANTIENE el material de vidrio (identidad de la app) y el
                // acento va como velo encima; antes eran dos círculos apilados
                // (material + color), ahora una sola cápsula con el mismo vidrio.
                .background {
                    Capsule().fill(AnyShapeStyle(.ultraThinMaterial))
                }
                .overlay {
                    Capsule().fill(accent.gradient(primaryOpacity: 0.22, secondaryOpacity: 0.12))
                }
                .overlay {
                    Capsule().strokeBorder(tintColor.opacity(0.35), lineWidth: 1)
                }
                .contentShape(Capsule())
            }
            .accessibilityLabel(Localization.localized("details.shuffle"))
            .buttonStyle(PressableButtonStyle(scale: 0.97))
        }
        .padding(.horizontal, 4)
    }

    private func statPill(icon: String, text: String, highlighted: Bool = false) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold))
            // lineLimit(1) + fixedSize: el texto NUNCA se parte ni corta con
            // guiones — la píldora mantiene su tamaño intrínseco y el
            // FlowLayout la acomoda entera en la siguiente fila si no cabe.
            // ✅ 13 semibold: la píldora es dato de cabecera, no letra pequeña.
            Text(text).font(.system(size: 13, weight: .semibold).monospacedDigit())
                .lineLimit(1)
        }
        .foregroundStyle(highlighted ? tintColor : Color.secondary)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .fixedSize()
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

    @ObservedObject private var theme = ThemeManager.shared

    /// ✅ Mismo criterio que el resto de la app: dos colores de acento (con el modo
    /// portada activo, el de ESTE álbum cuando existe; si no, el manual).
    private var accent: DetailAccent {
        DetailAccent.resolve(
            artworkColor: album.dominantColor,
            artworkSecondaryColor: nil,
            fromArtwork: theme.accentFromArtwork
        )
    }

    /// ✅ Subtítulo de la tarjeta: "2021 · 12 canciones" (o solo el recuento si
    /// el álbum no trae fecha).
    private var cardSubtitle: String {
        let count = localizedSongCount(album.songs.count)
        guard let date = album.releaseDate else { return count }
        return "\(Calendar.current.component(.year, from: date)) · \(count)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if let artwork = album.artwork {
                    // ✅ ANTI-JETSAM: card de 150pt → miniatura de 300px.
                    Image(uiImage: AppTheme.thumbnail(from: artwork, size: CGSize(width: 300, height: 300)))
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
                                LinearGradient(colors: accent.colors(primaryOpacity: 0.25, secondaryOpacity: 0.18), startPoint: .topLeading, endPoint: .bottomTrailing)
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
                // ✅ Año + nº de canciones: en un carrusel de discografía el año
                // es el dato que orienta al usuario (antes solo el recuento).
                Text(cardSubtitle)
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 150)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(album.name), \(cardSubtitle)")
        // ? Micro-escala al presionar la tarjeta (feedback premium, GPU)
        .contentShape(Rectangle())
    }
}

// MARK: - Song Row optimizado para Artist Detail
struct ArtistSongRow: View {
    let song: Song
    let index: Int
    let isCurrent: Bool
    /// ✅ Estado de reproducción para que el indicador de "suena ahora" solo
    /// anime mientras suena de verdad (ver EqualizerBars).
    let isPlaying: Bool
    let tintColor: Color
    // ✅ Acciones rápidas por menú contextual. No usamos .swipeActions porque
    // estas filas viven en un LazyVStack dentro de un ScrollView, y swipeActions
    // solo se activa dentro de un List.
    let isLiked: Bool
    let onAddToQueue: () -> Void
    let onToggleLike: () -> Void
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            HStack(spacing: 14) {
                if isCurrent {
                    EqualizerBars(color: tintColor, isPlaying: isPlaying)
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
                    .fill(isCurrent ? tintColor.opacity(0.12) : Color(UIColor.secondarySystemBackground).opacity(0.6))
            }
            .contentShape(Rectangle())
            .overlay {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(tintColor.opacity(0.3), lineWidth: 1)
                }
            }
        }
        // ? Feedback de presi�n al tocar (micro-escala, animaci�n GPU)
        .buttonStyle(PressableButtonStyle(scale: 0.98))
        // ✅ Acciones rápidas (mantener pulsada la fila): añadir a la cola y me
        // gusta. Menú contextual en vez de swipeActions por lo explicado arriba.
        .contextMenu {
            Button {
                Haptics.light()
                onAddToQueue()
            } label: {
                Label(Localization.localized("actions.addToQueue"), systemImage: "text.badge.plus")
            }
            Button {
                onToggleLike()
            } label: {
                Label(
                    Localization.localized(isLiked ? "actions.unlike" : "actions.like"),
                    systemImage: isLiked ? "heart.slash" : "heart"
                )
            }
        }
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

// MARK: - FlowLayout (iOS 16+): acomoda vistas en filas y pasa a la siguiente
// cuando no caben — las píldoras de info se mantienen ENTERAS (nada de texto
// partido con guiones), se adaptan a español/inglés y a pantallas estrechas.
struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 10
    var verticalSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? max(x - horizontalSpacing, 0) : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(size)
            )
            x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
