import SwiftUI
import CoreImage

// MARK: - Métricas del hero de detalle (Album / Artist)
/// ✅ FIX FRANJA SUPERIOR: alto de la franja que ocupan el status bar + la
/// navigation bar, que el fondo del hero debe tapar cuando el ScrollView ya no
/// aporta ese inset. Se resuelve UNA vez por proceso (lectura de window, mismo
/// patrón que FPSCounter) y NO en el body: el body del detalle se reevalúa en
/// cada tick de scroll y ahí no puede haber una consulta a UIKit.
/// En portrait es exacto (20+44 en iPhone 8 Plus; 44+44 con notch). En landscape
/// la barra mide 44 y el valor queda algo alto: diferencia solo estética.
enum DetailHeroMetrics {
    static let topSafeInset: CGFloat = {
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        let inset = scene?.windows.first(where: { $0.isKeyWindow })?.safeAreaInsets.top ?? 0
        return inset > 0 ? inset : 64
    }()
}

// MARK: - Acento de las vistas de detalle (SIEMPRE de DOS colores)
/// ✅ Regla única para Album/Artist detail:
/// ✅ G (comentario corregido): la fuente del acento NO es la portada del
/// álbum/artista que se está mirando, es la de la CANCIÓN QUE SUENA.
/// · Con "Acento desde portada" ACTIVO → el par que publica `ThemeManager` para
///   la carátula de la canción actual (fuente única, el mismo par que usan chips
///   y cabeceras del resto de la app), pasado por `readableColor`, más su
///   secundario REAL extraído con la misma caché que el primario.
///   Excepción: `ArtistAlbumCard`, que pinta los OTROS álbumes del artista y usa
///   el `dominantColor` de su propia carátula.
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

/// ✅ M3E: visibilidad del título de la barra como BOOLEANO con umbral.
/// Antes el título recibía una opacidad CONTINUA calculada del scroll, y una
/// opacidad reasignada en cada tick no se puede animar: el sistema la aplicaba
/// de golpe y el cruce se sentía abrupto. Con un estado booleano, SwiftUI
/// anima el CAMBIO con `AuroraMotion.spatialDefault` (spring) y solo cuando cruza.
private func detailShowsInlineTitle(for progress: CGFloat) -> Bool {
    detailTitleReveal(for: progress) > 0.35
}

// MARK: - Album Detail (dise�o inmersivo premium con color de car�tula)
struct AlbumDetailView: View {
    let album: Album
    @ObservedObject var audioEngine: AudioEngine
    // ✅ Inyectado (mismo patrón que NowPlayingView/PlayerBar): lo necesitan las
    // acciones rápidas de las filas (añadir a la cola y me gusta).
    @ObservedObject var fileAccessService: FileAccessService
    @M3EDismiss private var dismiss

    // ✅ ACENTO UNIFICADO: el par de la carátula lo resuelve y publica
    // ThemeManager (una sola pasada + caché por huella de imagen).
    // Esta vista SOLO LEE: aquí no se computa ningún color.
    @State private var appearAnimation = false
    // ? OPT: blur precalculado UNA vez (en background) en vez de re-renderizar .blur(50) en cada frame


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

    /// ✅ M3E: ver `detailShowsInlineTitle`. Se calcula del offset ya
    /// cuantizado a 1pt, así que el body no se despierta por micro-movimientos.
    private var showsInlineTitle: Bool {
        detailShowsInlineTitle(for: detailHeroProgress(for: scrollOffset))
    }

    // ✅ Acento de DOS colores: primario + secundario publicados por ThemeManager
    // (fuente unificada = carátula de la canción actual). El secundario solo se
    // usa con "Acento desde portada" activo.
    @ObservedObject private var theme = ThemeManager.shared
    private var songs: [Song] { cachedSongs }
    private var totalDuration: TimeInterval { cachedTotalDuration }
    private var hasMultipleDiscs: Bool { cachedHasMultipleDiscs }
    private var songsByDisc: [(disc: Int, songs: [Song])] { cachedSongsByDisc }
    /// ✅ Acento de la vista, SIEMPRE de dos colores. Lee el par publicado por
    /// ThemeManager (fuente unificada = carátula de la canción actual); el hero
    /// sigue mostrando la carátula del álbum, solo el acento cambia de fuente.
    /// Con el modo desactivado, el acento manual con su segunda parada al 40%,
    /// igual que el resto de la app.
    private var accent: DetailAccent {
        DetailAccent.resolve(
            artworkColor: theme.artworkAccentUIColor,
            artworkSecondaryColor: theme.artworkSecondaryUIColor,
            fromArtwork: theme.accentFromArtwork
        )
    }

    /// ✅ Acento sólido (textos, iconos y resaltados de fila): el mismo primario
    /// del gradiente, para que la pantalla entera respete el modo activo.
    private var tintColor: Color { accent.primary }

    // ✅ El secundario ya no se carga aquí: ThemeManager lo publica (fuente
    // unificada, una sola pasada) y `accent` lo lee. Sin extracción local ni
    // pop de color al entrar.
    // ? UIColor crudo para calcular contraste de textos/botones
    /// ✅ Estado real del motor para ESTE álbum (ver el pill de bit-perfect).
    private var isAlbumBitPerfect: Bool {
        guard let current = audioEngine.currentSong else { return false }
        return audioEngine.isBitPerfect && songs.contains { $0.id == current.id }
    }

    private var tintUIColor: UIColor { theme.artworkAccentUIColor ?? AppTheme.accentUIColor }
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
                                onToggleLike: { fileAccessService.toggleLike(song) },
                                // ✅ E2.3: "Reproducir ahora" reusa el `action` de la
                                // fila, así que su contexto es el álbum completo en
                                // orden de disco (mismo que el tap).
                                onPlayNext: { audioEngine.playNext(song) }
                            ) {
                                audioEngine.play(song: song, from: cachedSongs)
                            }
                            // ✅ PERF: sin `.equatable()` el body del detalle (que
                            // observa el motor) re-evaluaría cada fila visible en
                            // cada @Published. Con esto solo se repinta la fila
                            // cuyo estado cambió.
                            .equatable()
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 20)
                // ? FIX: padding inferior amplio para que la �ltima canci�n
                // no quede oculta detr�s del PlayerBar flotante.
                .padding(.bottom, 24)
            }
        }
        .coordinateSpace(name: "detailScroll")
        // ✅ Cuantizado a 1pt: el scroll repinta un par de veces menos por frame
        // (una subida de 40pt ya no genera 40 renders).
        .onPreferenceChange(DetailScrollOffsetKey.self) { offset in
            if abs(offset - scrollOffset) > 1 { scrollOffset = offset }
        }
        .background(AppBackground().ignoresSafeArea())
        // ✅ M3E: top app bar PROPIA. Sin `NavigationStack` ni toolbar del
        // sistema: el detalle es una pantalla completa con su barra Material
        // (título title-large, back con dismiss), como una activity de Android.
        .safeAreaInset(edge: .top, spacing: 0) {
            detailTopBar
        }

        // ✅ FIX BACK TEXT: back nativo oculto (salía "Back" en inglés y con el
        // azul del asset). Back propio: acento vivo + texto localizado; el
        // dismiss de entorno hace el pop del stack.

        // ✅ BARRERA EMERGENTE (estilo Apple Music): el título aparece solo
        // cuando el hero ya casi salió de pantalla. Solo opacidad, sin recalculos.

        // ? Sin banda gris: el hero inmersivo fluye bajo la barra de navegaci�n

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
            withAnimation(AuroraMotion.spatialDefault) {
                appearAnimation = true
            }
            // ? OPT: precalcular el blur del hero UNA vez en background
        }
    }

    // ? OPT: gaussian blur costoso ? se calcula UNA vez en hilo de fondo y se cachea


    /// ✅ M3E: top app bar propia del detalle. Sustituye al toolbar del
    /// `NavigationStack`: back + título `title-large` sobre `surface` sólido.
    private var detailTopBar: some View {
        M3ENavigationBar(
            title: album.name,
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
            trailing: { EmptyView() }
        )
    }

    private var heroSection: some View {
        VStack(spacing: 14) {
            // ? Artwork con animaci�n de entrada y brillo sutil
            // ? 60fps: sombra �NICA consolidada (la doble sombra = 2 pasadas
            // de offscreen rendering por frame en A11; visualmente equivalente).
            // ✅ PERF/M3E: la portada es ahora una view VALOR Equatable
            // (`DetailHeroArtwork`). Esta vista se reevalúa en cada tick de scroll y
            // en cada @Published del motor; con `.equatable()` el subtree de la
            // portada (clip + borde + sombra) ni se evalúa mientras nada cambie, y la
            // sombra se calcula en UNA pasada (`compositingGroup`).
            DetailHeroArtwork(
                kind: .album,
                identity: album.songs.compactMap { $0.artworkHash }.first ?? album.id,
                image: album.artwork.map { AppTheme.thumbnail(from: $0, size: CGSize(width: 400, height: 400)) },
                size: 200,
                accentPrimary: accent.primary,
                accentSecondary: accent.secondary,
                shadowColor: .black,
                isVisible: appearAnimation
            )
            // ✅ FIX CI: `.equatable()` ANTES del padding. `padding` devuelve un
            // `ModifiedContent` que NO es Equatable, así que encadenarlo después
            // hacía fallar la conformidad ("requires that 'some View' conform to
            // 'Equatable'"). El corte del diff sigue siendo el mismo: se aplica
            // al cuerpo de la portada.
            .equatable()
            .padding(.top, 8)

            // ? Info del �lbum con mejor jerarqu�a visual
            VStack(spacing: 6) {
                Text(album.name)
                    .font(M3ETypography.headlineSmallEmphasized)
                    .tracking(-0.2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(album.artist)
                    .font(M3ETypography.bodyLarge)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 24)
            .offset(y: appearAnimation ? 0 : 10)
            .opacity(appearAnimation ? 1.0 : 0)
            .animation(AuroraMotion.spatialDefault.delay(0.06), value: appearAnimation)

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
            .animation(AuroraMotion.spatialDefault.delay(0.12), value: appearAnimation)
        }
        // ✅ FIX FRANJA SUPERIOR: el contenido del hero vuelve a su sitio (el
        // ScrollView ya no aporta el inset, lo aporta aquí) y el fondo —que cuelga
        // de ESTE frame con alignment .top— crece esos mismos puntos hacia
        // arriba, hasta el borde de la pantalla. El contenido no se mueve.

        .frame(maxWidth: .infinity).padding(.bottom, 4)
        .background(alignment: .top) {
            GeometryReader { geometry in
                Group {
                    // ✅ M3E: fondo TONAL sólido, no carátula desenfocada.
                    // El único blur de fondo permitido es NowPlaying.
                    LinearGradient(
                        colors: accent.colors(primaryOpacity: 0.2, secondaryOpacity: 0.1) + [M3EColor.surface],
                        startPoint: .top, endPoint: .bottom
                    )
                }
                .frame(width: geometry.size.width, height: geometry.size.height + 80)
                // ✅ PARALLAX BARATO: esta capa YA está rasterizada por el
                // .drawingGroup() de abajo (el blur se calculó una sola vez en
                // background), así que aquí solo se le aplican transform y
                // opacidad — no se recalcula ni el blur ni ningún material.
                .scaleEffect(1 + detailHeroProgress(for: scrollOffset) * 0.14)
                .opacity(1 - detailHeroProgress(for: scrollOffset) * 0.55)
                // ✅ FIX CORTE DEL GRADIENTE: la capa terminaba en un borde duro
                // (height + 80) contra el fondo de la app. El último tramo se
                // desvanece a transparente justo donde acaba la capa, así que el
                // hero se funde con el contenido en vez de cortarse. El mask va
                // ANTES del .drawingGroup(): el fundido se cuece en la misma
                // textura cacheada y no cuesta nada por frame en A11.
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: geometry.size.height / (geometry.size.height + 80)),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
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
                    Text(Localization.localized("details.play")).font(M3ETypography.labelLargeEmphasized)
                }
                .foregroundStyle(onTintColor).frame(maxWidth: .infinity).frame(height: 48)
                // ✅ AURORA DESIGN (excepción justificada): el botón de Play NO
                // se migra a `auroraPrimaryAction()`. Su relleno es el gradiente
                // text-safe de ESTA vista (dos colores REALES de DetailAccent,
                // que puede ser el de la carátula) y el texto va con
                // `onTintColor` (blanco o negro según luminancia), no con el
                // blanco fijo del sistema.
                .background {
                    Capsule().fill(
                        accent.textSafeGradient()
                    )
                }
                .contentShape(Capsule())
                .shadow(color: tintColor.opacity(0.5), radius: 10, x: 0, y: 5)
            }
            // ✅ M3E: rebote + leve apagado, coherente con el resto de transportes.
            .buttonStyle(PressableButtonStyle(scale: AuroraPressScale.button, pressedOpacity: 0.85))

            Button {
                Haptics.medium()
                if !audioEngine.isShuffleEnabled { audioEngine.toggleShuffle() }
                if let randomSong = songs.randomElement() {
                    audioEngine.play(song: randomSong, from: songs)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "shuffle").font(.system(size: 15, weight: .bold))
                    Text(Localization.localized("details.shuffle")).font(M3ETypography.labelLargeEmphasized)
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
                // ✅ AURORA DESIGN (excepción justificada): NO se migra a
                // `auroraSecondaryAction(accent:)`. Ese modifier añade su propio
                // font 16 + padding 20/12 SOBRE el contenido: aplicado antes del
                // .frame(height: 48) el botón quedaría en ~43pt (rompe el
                // emparejamiento con Play) y aplicado después en 72pt; está
                // pensado para botones de tamaño intrínseco, no para este par
                // 50/50 de altura fija. Además el velo de aquí es el gradiente
                // de dos colores de la vista, no un acento plano al 12%.
                // ✅ FIX REDUCIR TRANSPARENCIA: el vidrio del fondo SÍ usa la
                // superficie del sistema (antes `.ultraThinMaterial` a pelo, que
                // ignoraba el ajuste y no reaccionaba): con el ajuste activo cae
                // a opaco, igual que el resto de la app. El velo y el borde de
                // abajo (que no son vidrio) no cambian.
                .nativeGlassCapsule()
                .overlay {
                    Capsule().fill(accent.gradient(primaryOpacity: 0.22, secondaryOpacity: 0.12))
                }
                .overlay {
                    Capsule().strokeBorder(tintColor.opacity(0.35), lineWidth: 1)
                }
                .contentShape(Capsule())
            }
            .accessibilityLabel(Localization.localized("details.shuffle"))
            // ✅ M3E: rebote + leve apagado, coherente con el resto de transportes.
            .buttonStyle(PressableButtonStyle(scale: AuroraPressScale.button, pressedOpacity: 0.85))
        }
        .padding(.horizontal, 4)
    }

    private func discSection(disc: Int, songs: [Song]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // ✅ AURORA DESIGN: la cápsula "Disco N" es un chip informacional del
            // sistema (mismo caso que `statPill`), no un HStack + vidrio a mano:
            // el padding simétrico y el vidrio reactivo viven dentro del chip.
            // Deltas visuales al migrar: el texto baja de 15 a 13 semibold
            // (contrato de chips) y el icono de 13 a 12, y ambos pasan a UN solo
            // color, así que el icono pierde el tinte de acento al 0.9 que tenía
            // y queda `.secondary` como el texto. El padding exterior de 4 no cambia.
            AuroraInfoChip(icon: "opticaldisc", text: "\(Localization.localized("details.disc")) \(disc)")
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
                    onToggleLike: { fileAccessService.toggleLike(song) },
                    // ✅ E2.3: "Reproducir ahora" reusa el `action` de la fila, así
                    // que su contexto es el ÁLBUM COMPLETO (`cachedSongs`), el que
                    // arregla el FIX multi-disco (con `songs` la repetición volvía
                    // a empezar el mismo disco en vez de seguir con el siguiente).
                    onPlayNext: { audioEngine.playNext(song) }
                ) {
                    audioEngine.play(song: song, from: cachedSongs)
                }
                .equatable()
            }
        }
    }

    private func statPill(icon: String, text: String, highlighted: Bool = false) -> some View {
        // ✅ AURORA DESIGN: la píldora de datos es el chip informacional del
        // sistema. Este wrapper conserva el mapeo de ESTA vista (dato normal =
        // `.secondary`; dato destacado = acento de la vista), así no cambian las
        // llamadas. `fixedSize`, `lineLimit(1)`, la tipografía de chip y el
        // vidrio reactivo a "Reducir transparencia" viven dentro del chip.
        AuroraInfoChip(icon: icon, text: text, color: highlighted ? tintColor : Color.secondary)
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
    //
    // ✅ FASE D (auditoría 60 fps): el formateador se construye UNA vez y se
    // reutiliza. `formatYear(_:)` se llama desde el body (hero del álbum, dentro
    // de `statPill`), así que cada render creaba un `DateFormatter` nuevo con su
    // locale + calendar + timeZone + dateFormat: ~0.3-1.5 ms en el A11 para
    // escribir cuatro dígitos, en una vista que re-renderiza al cambiar de
    // canción, al marcar "Me gusta" o al animar su entrada. La salida es IDÉNTICA
    // (mismos ajustes). `DateFormatter` es seguro para formatear desde varios
    // hilos desde iOS 7.
    private static let yearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy"
        return formatter
    }()

    private func formatYear(_ date: Date) -> String {
        AlbumDetailView.yearFormatter.string(from: date)
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
// ✅ PERF SCROLL (Prioridad 5): la fila es `Equatable` y se usa con
// `.equatable()` en los DOS call sites. El body del detalle (álbum/artista)
// observa `AudioEngine`, así que cada @Published suyo lo re-evalúa; sin la
// igualdad, cada evento volvía a evaluar también TODAS las filas visibles.
// `==` compara solo lo que la fila PINTA (ver abajo): los closures de acción
// se ignoran y `isPlaying` solo cuenta en la fila que suena de verdad.
struct AlbumSongRow: View, Equatable {
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
    // ✅ E2: acción del menú contextual para el orden estándar (Reproducir ahora
    // → Reproducir siguiente → Añadir a la cola → Me gusta). Se declara ANTES de
    // `action` porque el init miembro respeta el orden de declaración y `action`
    // es el closure final (trailing) en los 3 call sites.
    // ✅ E2.3: `onPlayNow` eliminado — era idéntico al `action` de la fila
    // (play(song, from: cachedSongs)), así que el menú reusa `action()`.
    let onPlayNext: () -> Void
    let action: () -> Void

    /// ✅ Igualdad = "¿está igual lo que esta fila PINTA?". Los closures se
    /// ignoran (capturan el engine por referencia) y `isPlaying`/`tintColor`
    /// solo cuentan en la fila actual: son los únicos casos en los que el body
    /// los lee. Así un play/pausa repinta UNA fila, no la lista entera.
    static func == (lhs: AlbumSongRow, rhs: AlbumSongRow) -> Bool {
        guard lhs.song.id == rhs.song.id,
              lhs.song.title == rhs.song.title,
              lhs.song.artist == rhs.song.artist,
              lhs.song.album == rhs.song.album,
              lhs.song.duration == rhs.song.duration,
              lhs.index == rhs.index,
              lhs.isCurrent == rhs.isCurrent,
              lhs.isLiked == rhs.isLiked
        else { return false }
        guard lhs.isCurrent else { return true }
        return lhs.isPlaying == rhs.isPlaying && lhs.tintColor == rhs.tintColor
    }

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
                        .font(M3ETypography.labelLargeNumeric)
                        .foregroundStyle(Color.secondary.opacity(0.5)).frame(width: 24)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(song.title)
                        .font(M3ETypography.titleMediumEmphasized)
                        .foregroundStyle(isCurrent ? tintColor : .primary).lineLimit(1)
                    // ✅ Debajo del título: el ARTISTA (en la vista de álbum el
                    // nombre del álbum es redundante — siempre es el mismo).
                    Text(song.artist.isEmpty ? song.displaySubtitle : song.artist)
                        .font(M3ETypography.bodyMedium).foregroundStyle(.secondary).lineLimit(1)
                }

                Spacer()

                Text(formatDuration(song.duration))
                    .font(M3ETypography.labelMedium).foregroundStyle(.tertiary)
            }
            // ✅ GOLPE FINAL: fila plana Android, sin card ni borde redondeado.
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(isCurrent ? tintColor.opacity(0.10) : Color.clear)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(M3EColor.outlineVariant.opacity(0.35))
                    .frame(height: 0.5)
                    .padding(.leading, 56)
            }
        }
        .buttonStyle(PressableButtonStyle(scale: AuroraPressScale.row))
        // ✅ Acciones rápidas (mantener pulsada la fila). Menú contextual en vez
        // de swipeActions por lo explicado arriba.
        // ✅ E2: orden ESTÁNDAR, idéntico en las 3 vistas de canciones
        // (biblioteca, álbum/artista, lista): Reproducir ahora → Reproducir
        // siguiente → Añadir a la cola → Me gusta. Cada ítem lleva su propio
        // Haptics.light() al empezar la acción (por eso los closures del call
        // site ya no repiten haptics: evitaría el doble golpe).
        .contextMenu {
            Button {
                // ✅ E2.3: reusa el `action` de la fila (mismo array y misma
                // posición), sin parámetro duplicado.
                Haptics.light()
                action()
            } label: {
                Label(Localization.localized("context.playNow"), systemImage: "play.circle.fill")
            }
            Button {
                Haptics.light()
                onPlayNext()
            } label: {
                Label(Localization.localized("context.playNext"), systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            Button {
                Haptics.light()
                onAddToQueue()
            } label: {
                Label(Localization.localized("actions.addToQueue"), systemImage: "text.badge.plus")
            }
            Button {
                Haptics.light()
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
    let isPlaying: Bool

    var body: some View {
        // ✅ FASE 1: un único TimelineView + Canvas por indicador y ningún
        // `repeatForever`. Antes cada una de las 3 barras abría su propio bucle
        // y, al re-renderizarse la fila, SwiftUI volvía a encolarlo: la fuente
        // del "bucle infinito" que no terminaba al cambiar de sección.
        AuroraEqualizerBars(
            color: color,
            isPlaying: isPlaying,
            barWidth: 2.5,
            spacing: 2.5,
            minHeight: 8,
            maxHeight: 13,
            height: 13
        )
        .frame(width: 24)
    }
}

// MARK: - Header de secci�n reutilizable (con gradiente sutil y color din�mico)
private func sectionHeader(icon: String, title: String, accent: DetailAccent) -> some View {
    // ✅ AURORA DESIGN: header de sección del sistema (icon-badge .medium +
    // título 18 rounded). El wrapper se mantiene porque las 3 llamadas pasan un
    // título ya localizado y el acento de ESTA vista (DetailAccent), que no es
    // el acento de la app que consumen los headers del sistema.
    // Cambios visuales DELIBERADOS de la migración: el icono pasa de glifo 14pt
    // con gradiente VERTICAL de dos colores a `accent.primary` sólido dentro del
    // badge (velo 0.22 → 0.08, el lenguaje de Settings/AudioQualityDetail), el
    // título baja de 20 a 18 y la fila crece de ~17 a 34pt por el badge. El
    // `.padding(.top, 4)` se conserva para no mover las secciones.
    return AuroraSectionHeader(icon: icon, title: title, color: accent.primary)
        .padding(.top, 4)
}

// MARK: - Artist Detail (perfil inmersivo premium)
struct ArtistDetailView: View {
    let artist: Artist
    @ObservedObject var audioEngine: AudioEngine
    // ✅ Inyectado: acciones rápidas de las filas (cola y me gusta).
    @ObservedObject var fileAccessService: FileAccessService
    @M3EDismiss private var dismiss

    @State private var appearAnimation = false
    // ? OPT: blur precalculado UNA vez (en background)


    // ? OPT: cachear c�mputos
    @State private var cachedAlbums: [Album] = []
    @State private var cachedSongs: [Song] = []
    @State private var cachedTotalDuration: TimeInterval = 0
    private var songs: [Song] { cachedSongs }
    private var albums: [Album] { cachedAlbums }

    // ✅ Acento de DOS colores: primario + secundario publicados por ThemeManager
    // (fuente unificada = carátula de la canción actual). El secundario solo se
    // usa con "Acento desde portada" activo.
    @ObservedObject private var theme = ThemeManager.shared
    // ✅ PARALLAX / BARRA EMERGENTE (mismo criterio que AlbumDetailView).
    @State private var scrollOffset: CGFloat = 0
    /// ✅ M3E: álbum abierto desde el carrusel del artista (fullScreenCover,
    /// sin NavigationStack).
    @State private var selectedAlbum: Album? = nil

    /// ✅ M3E: ver `detailShowsInlineTitle`. Se calcula del offset ya
    /// cuantizado a 1pt, así que el body no se despierta por micro-movimientos.
    private var showsInlineTitle: Bool {
        detailShowsInlineTitle(for: detailHeroProgress(for: scrollOffset))
    }
    private var totalDuration: TimeInterval { cachedTotalDuration }
    /// ✅ Acento de la vista, SIEMPRE de dos colores (mismo criterio que Album
    /// Detail): lee el par publicado por ThemeManager (fuente unificada =
    /// carátula de la canción actual); el hero sigue mostrando la carátula del
    /// artista. Acento manual con su segunda parada al 40% si el modo está off.
    private var accent: DetailAccent {
        DetailAccent.resolve(
            artworkColor: theme.artworkAccentUIColor,
            artworkSecondaryColor: theme.artworkSecondaryUIColor,
            fromArtwork: theme.accentFromArtwork
        )
    }

    /// ✅ Acento sólido (textos, iconos y resaltados de fila): el mismo primario
    /// del gradiente, para que la pantalla entera respete el modo activo.
    private var tintColor: Color { accent.primary }

    // ✅ El secundario ya no se carga aquí: ThemeManager lo publica (fuente
    // unificada, una sola pasada) y `accent` lo lee. Sin extracción local ni
    // pop de color al entrar.
    private var tintUIColor: UIColor { theme.artworkAccentUIColor ?? AppTheme.accentUIColor }
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
                                    Button {
                                        Haptics.light()
                                        selectedAlbum = album
                                    } label: {
                                        ArtistAlbumCard(album: album)
                                    }
                                    .buttonStyle(PressableButtonStyle(scale: AuroraPressScale.chip))
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
                            onToggleLike: { fileAccessService.toggleLike(song) },
                            // ✅ E2.3: "Reproducir ahora" reusa el `action` de la fila.
                            onPlayNext: { audioEngine.playNext(song) }
                        ) {
                            audioEngine.play(song: song, from: cachedSongs)
                        }
                        // ✅ PERF: mismo corte de diff que en AlbumSongRow.
                        .equatable()
                    }
                }
                .padding(.horizontal, 20).padding(.top, 28)
                // ? FIX: padding inferior amplio para el PlayerBar flotante
                .padding(.bottom, 24)
            }
        }
        .coordinateSpace(name: "detailScroll")
        // ✅ Cuantizado a 1pt: el scroll repinta un par de veces menos por frame
        // (una subida de 40pt ya no genera 40 renders).
        .onPreferenceChange(DetailScrollOffsetKey.self) { offset in
            if abs(offset - scrollOffset) > 1 { scrollOffset = offset }
        }
        .background(AppBackground().ignoresSafeArea())
        // ✅ M3E: top app bar PROPIA. Sin `NavigationStack` ni toolbar del
        // sistema: el detalle es una pantalla completa con su barra Material
        // (título title-large, back con dismiss), como una activity de Android.
        .safeAreaInset(edge: .top, spacing: 0) {
            detailTopBar
        }

        // ✅ FIX BACK TEXT: mismo criterio que AlbumDetailView (back propio con
        // acento y texto localizado, en vez del "Back" del sistema).

        // ✅ Barra emergente con el nombre del artista (mismo criterio que Album).

        // ? Sin banda gris (coherente con AlbumDetailView)

        .onAppear {
            // ? Cachear c�mputos una sola vez
            if cachedAlbums.isEmpty {
                cachedAlbums = artist.albums
                cachedSongs = artist.songs
                cachedTotalDuration = cachedSongs.reduce(0) { $0 + $1.duration }
            }
            withAnimation(AuroraMotion.spatialDefault) {
                appearAnimation = true
            }
            // ? OPT: precalcular el blur del hero UNA vez en background
            }
        .m3eScreen(item: $selectedAlbum) { album in
            AlbumDetailView(album: album, audioEngine: audioEngine, fileAccessService: fileAccessService)
        }
        }

    // ? OPT: gaussian blur costoso ? se calcula UNA vez en hilo de fondo y se cachea


    /// ✅ M3E: top app bar propia (ver AlbumDetailView).
    private var detailTopBar: some View {
        M3ENavigationBar(
            title: artist.name,
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
            trailing: { EmptyView() }
        )
    }

    private var artistHeroSection: some View {
        VStack(spacing: 22) {
            // ? Avatar del artista con animaci�n y efectos mejorados
            // ✅ PERF/M3E: avatar Equatable (ver `DetailHeroArtwork`). El detalle del
            // artista se reevalúa en cada tick de scroll; este subtree ya no.
            DetailHeroArtwork(
                kind: .artist,
                identity: artist.songs.compactMap { $0.artworkHash }.first ?? artist.id,
                image: artist.artwork.map { AppTheme.thumbnail(from: $0, size: CGSize(width: 340, height: 340)) },
                size: 170,
                accentPrimary: accent.primary,
                accentSecondary: accent.secondary,
                shadowColor: tintColor,
                isVisible: appearAnimation
            )
            // ✅ FIX CI: `.equatable()` ANTES del padding (ver Álbum detail).
            .equatable()
            .padding(.top, 20)

            // ? Info del artista con mejor jerarqu�a visual
            VStack(spacing: 10) {
                Text(artist.name)
                    .font(M3ETypography.headlineSmallEmphasized)
                    .tracking(-0.3)
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
            .animation(AuroraMotion.spatialDefault.delay(0.06), value: appearAnimation)
        }
        // ✅ FIX FRANJA SUPERIOR: el contenido del hero vuelve a su sitio (el
        // ScrollView ya no aporta el inset, lo aporta aquí) y el fondo —que cuelga
        // de ESTE frame con alignment .top— crece esos mismos puntos hacia
        // arriba, hasta el borde de la pantalla. El contenido no se mueve.

        .frame(maxWidth: .infinity).padding(.bottom, 4)
        .background(alignment: .top) {
            GeometryReader { geometry in
                Group {
                    // ✅ M3E: fondo tonal sólido (sin carátula desenfocada).
                    LinearGradient(
                        colors: accent.colors(primaryOpacity: 0.25, secondaryOpacity: 0.12) + [M3EColor.surface],
                        startPoint: .top, endPoint: .bottom
                    )
                }
                .frame(width: geometry.size.width, height: geometry.size.height + 80)
                // ✅ PARALLAX BARATO: esta capa YA está rasterizada por el
                // .drawingGroup() de abajo (el blur se calculó una sola vez en
                // background), así que aquí solo se le aplican transform y
                // opacidad — no se recalcula ni el blur ni ningún material.
                .scaleEffect(1 + detailHeroProgress(for: scrollOffset) * 0.14)
                .opacity(1 - detailHeroProgress(for: scrollOffset) * 0.55)
                // ✅ FIX CORTE DEL GRADIENTE: la capa terminaba en un borde duro
                // (height + 80) contra el fondo de la app. El último tramo se
                // desvanece a transparente justo donde acaba la capa, así que el
                // hero se funde con el contenido en vez de cortarse. El mask va
                // ANTES del .drawingGroup(): el fundido se cuece en la misma
                // textura cacheada y no cuesta nada por frame en A11.
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: geometry.size.height / (geometry.size.height + 80)),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
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
                    Text(Localization.localized("details.play")).font(M3ETypography.labelLargeEmphasized)
                }
                .foregroundStyle(onTintColor).frame(maxWidth: .infinity).frame(height: 48)
                // ✅ AURORA DESIGN (excepción justificada): el botón de Play NO
                // se migra a `auroraPrimaryAction()`. Su relleno es el gradiente
                // text-safe de ESTA vista (dos colores REALES de DetailAccent,
                // que puede ser el de la carátula) y el texto va con
                // `onTintColor` (blanco o negro según luminancia), no con el
                // blanco fijo del sistema.
                .background {
                    Capsule().fill(
                        accent.textSafeGradient()
                    )
                }
                .contentShape(Capsule())
                .shadow(color: tintColor.opacity(0.5), radius: 10, x: 0, y: 5)
            }
            // ✅ M3E: rebote + leve apagado, coherente con el resto de transportes.
            .buttonStyle(PressableButtonStyle(scale: AuroraPressScale.button, pressedOpacity: 0.85))

            Button {
                Haptics.medium()
                if !audioEngine.isShuffleEnabled { audioEngine.toggleShuffle() }
                if let randomSong = songs.randomElement() {
                    audioEngine.play(song: randomSong, from: songs)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "shuffle").font(.system(size: 15, weight: .bold))
                    Text(Localization.localized("details.shuffle")).font(M3ETypography.labelLargeEmphasized)
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
                // ✅ AURORA DESIGN (excepción justificada): NO se migra a
                // `auroraSecondaryAction(accent:)`. Ese modifier añade su propio
                // font 16 + padding 20/12 SOBRE el contenido: aplicado antes del
                // .frame(height: 48) el botón quedaría en ~43pt (rompe el
                // emparejamiento con Play) y aplicado después en 72pt; está
                // pensado para botones de tamaño intrínseco, no para este par
                // 50/50 de altura fija. Además el velo de aquí es el gradiente
                // de dos colores de la vista, no un acento plano al 12%.
                // ✅ FIX REDUCIR TRANSPARENCIA: el vidrio del fondo SÍ usa la
                // superficie del sistema (antes `.ultraThinMaterial` a pelo, que
                // ignoraba el ajuste y no reaccionaba): con el ajuste activo cae
                // a opaco, igual que el resto de la app. El velo y el borde de
                // abajo (que no son vidrio) no cambian.
                .nativeGlassCapsule()
                .overlay {
                    Capsule().fill(accent.gradient(primaryOpacity: 0.22, secondaryOpacity: 0.12))
                }
                .overlay {
                    Capsule().strokeBorder(tintColor.opacity(0.35), lineWidth: 1)
                }
                .contentShape(Capsule())
            }
            .accessibilityLabel(Localization.localized("details.shuffle"))
            // ✅ M3E: rebote + leve apagado, coherente con el resto de transportes.
            .buttonStyle(PressableButtonStyle(scale: AuroraPressScale.button, pressedOpacity: 0.85))
        }
        .padding(.horizontal, 4)
    }

    private func statPill(icon: String, text: String, highlighted: Bool = false) -> some View {
        // ✅ AURORA DESIGN: la píldora de datos es el chip informacional del
        // sistema. Este wrapper conserva el mapeo de ESTA vista (dato normal =
        // `.secondary`; dato destacado = acento de la vista), así no cambian las
        // llamadas. `fixedSize`, `lineLimit(1)`, la tipografía de chip y el
        // vidrio reactivo a "Reducir transparencia" viven dentro del chip.
        AuroraInfoChip(icon: icon, text: text, color: highlighted ? tintColor : Color.secondary)
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
                        // ✅ AURORA DESIGN (excepción justificada): aquí NO hay card
                        // que migrar. Los radios 20 de esta tarjeta son la FORMA DE
                        // LA CARÁTULA (clipShape + borde + placeholder vacío), no el
                        // fondo de una card: la tarjeta es carátula + texto, igual
                        // que `playlistLibraryCard` de la biblioteca. Se alinean al
                        // radio .md (18) para coincidir con las filas. Un
                        // `auroraCard` aquí exigiría padding interno (cambiaría el
                        // ancho de 150 y el layout del carrusel) y DUPLICARÍA la
                        // sombra de la carátula: 2 pasadas offscreen por tarjeta en
                        // A11, prohibido (sombra siempre single).
                        .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.25), radius: 14, x: 0, y: 7)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
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
                    .font(M3ETypography.labelLargeEmphasized)
                    .foregroundStyle(.primary).lineLimit(1)
                // ✅ Año + nº de canciones: en un carrusel de discografía el año
                // es el dato que orienta al usuario (antes solo el recuento).
                Text(cardSubtitle)
                    .font(M3ETypography.bodyMedium).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 150)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(album.name), \(cardSubtitle)")
        // ✅ AURORA DESIGN: la micro-escala al presionar la aporta el
        // `PressableButtonStyle` del NavigationLink del carrusel (hasta ahora
        // este comentario prometía un feedback que no existía: `.plain` no anima
        // nada). El contentShape se queda: hace táctil todo el rect de 150pt,
        // incluidos los huecos transparentes entre carátula y textos.
        .contentShape(Rectangle())
    }
}

// MARK: - Song Row optimizado para Artist Detail
struct ArtistSongRow: View, Equatable {
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
    // ✅ E2: acción del menú contextual para el orden estándar (Reproducir ahora
    // → Reproducir siguiente → Añadir a la cola → Me gusta). Se declara ANTES de
    // `action` porque el init miembro respeta el orden de declaración y `action`
    // es el closure final (trailing) en los 3 call sites.
    // ✅ E2.3: `onPlayNow` eliminado — era idéntico al `action` de la fila
    // (play(song, from: cachedSongs)), así que el menú reusa `action()`.
    let onPlayNext: () -> Void
    let action: () -> Void

    /// ✅ Misma igualdad que `AlbumSongRow` (ver comentario allí).
    static func == (lhs: ArtistSongRow, rhs: ArtistSongRow) -> Bool {
        guard lhs.song.id == rhs.song.id,
              lhs.song.title == rhs.song.title,
              lhs.song.artist == rhs.song.artist,
              lhs.song.album == rhs.song.album,
              lhs.song.duration == rhs.song.duration,
              lhs.index == rhs.index,
              lhs.isCurrent == rhs.isCurrent,
              lhs.isLiked == rhs.isLiked
        else { return false }
        guard lhs.isCurrent else { return true }
        return lhs.isPlaying == rhs.isPlaying && lhs.tintColor == rhs.tintColor
    }

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
                        .font(M3ETypography.labelLargeNumeric)
                        .foregroundStyle(Color.secondary.opacity(0.5)).frame(width: 24)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(song.title)
                        .font(M3ETypography.titleMediumEmphasized)
                        .foregroundStyle(isCurrent ? tintColor : .primary).lineLimit(1)
                    Text(song.album.isEmpty ? song.displaySubtitle : song.album)
                        .font(M3ETypography.bodyMedium).foregroundStyle(.secondary).lineLimit(1)
                }

                Spacer()

                Text(formatDuration(song.duration))
                    .font(M3ETypography.labelMedium).foregroundStyle(.tertiary)
            }
            // ✅ GOLPE FINAL: fila plana Android, sin card ni borde redondeado.
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(isCurrent ? tintColor.opacity(0.10) : Color.clear)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(M3EColor.outlineVariant.opacity(0.35))
                    .frame(height: 0.5)
                    .padding(.leading, 56)
            }
        }
        // ? Feedback de presi�n al tocar (micro-escala, animaci�n GPU)
        .buttonStyle(PressableButtonStyle(scale: AuroraPressScale.row))
        // ✅ Acciones rápidas (mantener pulsada la fila). Menú contextual en vez
        // de swipeActions por lo explicado arriba.
        // ✅ E2: orden ESTÁNDAR, idéntico en las 3 vistas de canciones
        // (biblioteca, álbum/artista, lista): Reproducir ahora → Reproducir
        // siguiente → Añadir a la cola → Me gusta. Cada ítem lleva su propio
        // Haptics.light() al empezar la acción (por eso los closures del call
        // site ya no repiten haptics: evitaría el doble golpe).
        .contextMenu {
            Button {
                // ✅ E2.3: reusa el `action` de la fila (mismo array y misma
                // posición), sin parámetro duplicado.
                Haptics.light()
                action()
            } label: {
                Label(Localization.localized("context.playNow"), systemImage: "play.circle.fill")
            }
            Button {
                Haptics.light()
                onPlayNext()
            } label: {
                Label(Localization.localized("context.playNext"), systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            Button {
                Haptics.light()
                onAddToQueue()
            } label: {
                Label(Localization.localized("actions.addToQueue"), systemImage: "text.badge.plus")
            }
            Button {
                Haptics.light()
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
