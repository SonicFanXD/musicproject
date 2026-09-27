import Foundation
import SwiftUI

// MARK: - Vista de lyrics línea por línea (optimizada para iPhone 8 Plus)
// ✅ Diseño: ScrollView + LazyVStack para máximo rendimiento
// ✅ 60 fps REALES: el relleno progresivo vive dentro de un TimelineView(.animation)
//    que interpola entre los ticks del reloj de reproducción (0.4s) usando el
//    ancla CACurrentMediaTime del ViewModel.
// ✅ Solo la línea ACTIVA tiene TimelineView → el resto del LazyVStack no se
//    re-evalúa en cada frame.
// ✅ Una línea lógica puede tener VARIAS filas visuales (TTML <br/>): cada fila
//    lleva su propia máscara y su propia ventana temporal, así el relleno
//    avanza de arriba abajo (nunca en paralelo) y respeta los silencios.
// ✅ KARAOKE POR PALABRA (estilo Apple Music): cuando la fila trae timings por
//    palabra (TTML `itunes:timing="Word"` o LRC híbrido), el borde del relleno lo
//    marca la VOZ: cada palabra se revela dentro de SU ventana y las que todavía
//    no han sonado quedan apagadas. Con una sola palabra, un LRC clásico o un
//    reparto de timings no demostrable, se conserva el relleno lineal por fila.
// ✅ La capa brillante lleva debajo una copia tintada con el acento y desenfocada
//    (~2 pt) que produce el halo/"glow" del texto ya sonado.
// ✅ Las filas que SwiftUI partiría por ANCHURA también se trocean (medición real
//    con la fuente activa): el wipe avanza fila a fila, nunca en paralelo.
// ✅ Sin temporizadores propios (ni en la vista ni en el modelo).
// ✅ Auto-scroll suave con ScrollViewReader (solo cuando cambia la línea activa)
// ✅ Sin línea activa (intro instrumental / outro) se centra la primera o la
//    última línea como "activa provisional": la vista nunca nace mostrando la
//    franja vacía del relleno de centrado con las letras abajo.
// ✅ Los huecos instrumentales (intro y interludio, ≥ 3 s) se anuncian con el
//    MISMO indicador de puntos, colgado de la fila focal como overlay: en el
//    flujo, alineado con el texto y sin mover la letra ni el LazyVStack.
// ✅ Colores ADAPTATIVOS (`.primary`): la app no fuerza modo oscuro, así que el
//    texto blanco fijo era invisible sobre el fondo claro en modo claro.
// ✅ Render 100% por código, sin assets
struct LyricsView: View {
    let song: Song?
    @ObservedObject var viewModel: LyricsViewModel
    // ✅ Observado para que los textos se re-rendericen al cambiar de idioma en vivo.
    @ObservedObject private var localization = Localization.shared
    @Environment(\.dismiss) private var dismiss
    /// ✅ Fase de la escena: al abrir el Centro de Control (o cualquier overlay del
    /// sistema) la app pasa a `.inactive`. El karaoke no debe pedir frames
    /// entonces —la GPU la necesita el panel del sistema y el run loop está en
    /// modo de gesto— así que el wipe se congela y, al volver, se re-ancla el
    /// reloj con la posición REAL del motor: retoma donde toca, no desde cero.
    @Environment(\.scenePhase) private var scenePhase
    /// ✅ Detector de grabación de pantalla (`UIScreen.isCaptured`): mientras se
    /// graba, el sistema pide TODOS los frames que dibujamos y el wipe compite
    /// con el codificador. Con esto el karaoke baja a 30 fps alineados con el
    /// vsync y se sueltan las pasadas más caras.
    /// ✅ Mismo patrón que `VisualizerFrameRate`: singleton observado por la vista.
    @ObservedObject private var captureMonitor = LyricCaptureMonitor.shared
    /// ✅ Acento OBSERVADO: ThemeManager extrae el color de la carátula en
    /// background y lo publica un instante después del cambio de canción. Con la
    /// vista suscrita, el fondo se re-tiñe en cuanto el acento real está listo
    /// (sin esperar al siguiente verso) y el cambio se ve suave, nunca un flash
    /// con el color del acento anterior.
    @ObservedObject private var theme = ThemeManager.shared
    /// ✅ "Reducir transparencia": el mismo ajuste que respeta `NowPlayingView`.
    /// Con él no se paga material de vidrio ni desenfoque de carátula.
    @AppStorage("com.aurora.reduceTransparency") private var reduceTransparency = false

    /// ✅ Petición de centrado: el `token` garantiza que SwiftUI reciba un
    /// cambio aunque la línea destino sea la misma (al cambiar de canción), así
    /// el re-centrado nunca se pierde.
    private struct ScrollRequest: Equatable {
        let lineID: Int
        let token: Int
    }

    @State private var scrollRequest: ScrollRequest?
    @State private var scrollToken: Int = 0
    /// ✅ Distingue el PRIMER centrado (al entrar o al cambiar de canción) del
    /// resto: el primero va SIN animación (la vista "nace" ya centrada) y los
    /// scrolleos durante la reproducción sí se animan.
    @State private var hasDoneInitialScroll = false

    /// ✅ Padding horizontal del contenido de letras: el ancho ÚTIL para el texto
    /// (y para el troceo por medición) es el ancho de la vista menos el doble.
    /// El indicador del interludio NO lo replica: cuelga de la fila, que ya vive
    /// dentro de este padding, así que hereda la alineación sin duplicarla.
    private static let horizontalPadding: CGFloat = 24

    /// ✅ Separación entre filas del stack de letras: la MISMA constante con la
    /// que el indicador del interludio mide la banda vacía donde se coloca. Si el
    /// stack cambia de separación, el indicador la sigue sin tocar nada más.
    private static let interlineSpacing: CGFloat = 8

    /// ✅ Cuánto se asoma el indicador fuera del borde de su fila: media
    /// separación (para caer en la banda vacía contigua) más medio punto (para
    /// quedar centrado en esa banda, a la misma distancia del verso cantado y de
    /// la línea siguiente). Un solo número que ajustar tras la prueba en
    /// dispositivo; el radio del punto lo aporta el propio indicador.
    private static let gapIndicatorOutset: CGFloat = interlineSpacing / 2 + LyricInstrumentalIndicator.dotRadius

    /// ✅ Acento del karaoke: es el color con el que se tiñe la copia desenfocada
    /// del texto (el "glow" de Apple Music). Sale de la CARÁTULA cuando el ajuste
    /// de acento desde carátula está activo; si no, del acento elegido por el usuario.
    private var glowColor: Color { AppTheme.accent }

    /// ✅ Centrado geométrico exacto: el relleno vertical debe ser al menos MEDIA
    /// ALTURA del área visible. Con menos, `scrollTo(anchor: .center)` no puede
    /// alcanzar el centro de las PRIMERAS y ÚLTIMAS líneas (el scroll se queda
    /// clavado en el borde del contenido). El 40 % de `UIScreen.main` se quedaba
    /// corto: en el 8 Plus son 294 pt frente a los 346 pt que exige un área
    /// visible de 692 pt, así que la línea 0 aterrizaba ~30-65 pt por encima del
    /// centro y, sin scroll inicial, el relleno se veía como una franja vacía
    /// arriba con las letras en la mitad inferior.
    /// ✅ Se mide el área REAL de scroll (ya sin el header), no la pantalla: el
    /// centrado queda exacto en cualquier dispositivo y tamaño de ventana.
    private func centeringInset(viewportHeight: CGFloat) -> CGFloat {
        // Red de seguridad: si la geometría todavía no está medida (0), se
        // conserva el valor anterior para no dejar el contenido sin relleno.
        viewportHeight > 0 ? viewportHeight / 2 : UIScreen.main.bounds.height * 0.4
    }

    var body: some View {
        ZStack {
            // ✅ Fondo como vista propia y `Equatable`: al cambiar de línea activa
            // este body se re-evalúa, pero el blur de pantalla completa NO vuelve
            // a componerse si la carátula y el acento siguen siendo los mismos.
            LyricsArtworkBackground(
                artwork: song?.artwork,
                accentToken: AppTheme.accentUIColor,
                reduceTransparency: reduceTransparency
            )
            .equatable()

            VStack(spacing: 0) {
                // Header transparente
                headerView

                Group {
                    if !viewModel.hasLyrics {
                        emptyLyricsView
                    } else {
                        lyricsContentView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // ✅ El indicador del interludio NO vive aquí: cuelga de la fila
            // focal como `.overlay` (ver `interludeIndicator(for:)`) para ocupar
            // su propio espacio en el flujo de las letras, alineado con el texto
            // y sin tocar ni el layout de la lista ni el auto-scroll.
        }
        .onAppear {
            parseLyricsIfNeeded()
            // ✅ Centrado inmediato, sin animación: la línea activa ya está en el
            // centro en el primer frame.
            syncScrollToActiveLine()
        }
        // ✅ iOS 16 onChange clásico: scroll solo cuando cambia la línea activa
        .onChange(of: viewModel.activeID) { newID in
            guard let newID else { return }
            requestScroll(to: newID)
        }
        // ✅ Letras que llegan de un parseo en background: terminan DESPUÉS del
        // `onAppear`, así que el centrado inicial hay que repetirlo con las líneas
        // ya publicadas (sigue siendo el primer centrado → sin animación).
        .onChange(of: viewModel.lyricsRevision) { _ in
            syncScrollToActiveLine()
        }
        // ✅ Cambio de canción con la vista abierta: re-parsear y re-centrar sin
        // animación, como si la vista acabara de nacer.
        .onChange(of: song?.id) { _ in
            parseLyricsIfNeeded()
            syncScrollToActiveLine()
        }
        // ✅ Vuelta del overlay del sistema (Centro de Control, notificación…):
        // se re-ancla el reloj de interpolación con la posición real del motor.
        // Sin esto, el wipe reaparecía con el estado "atrasado" (o directamente
        // al principio de la línea) y daba un salto visible al volver.
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                viewModel.syncToCurrentTime()
            }
        }
    }

    // MARK: - Centrado de la línea activa
    /// Centra la línea activa SIN animación (entrada a la vista / cambio de
    /// canción). Resetea la petición para poder re-centrar aunque la línea
    /// destino coincida con la anterior.
    /// ✅ SIN línea activa (intro instrumental antes de la primera letra, o
    /// canción ya terminada) se centra la PRIMERA o la ÚLTIMA línea como si fuera
    /// la activa provisional: antes se salía sin pedir ningún scroll, la lista
    /// nacía en su posición natural y el relleno de centrado se veía como una
    /// franja vacía arriba con las letras pegadas abajo.
    private func syncScrollToActiveLine() {
        hasDoneInitialScroll = false
        scrollRequest = nil
        if let activeID = viewModel.activeID {
            requestScroll(to: activeID)
        } else if let fallbackID = centeringFallbackLineID() {
            requestScroll(to: fallbackID)
        }
    }

    /// ✅ Línea provisional que se centra mientras no hay línea activa: la primera
    /// si la reproducción todavía no la ha alcanzado (intro), la última si ya
    /// pasó todas (outro). Mismo criterio que Apple Music.
    private func centeringFallbackLineID() -> Int? {
        let lines = viewModel.lyricsLines
        guard let first = lines.first, let last = lines.last else { return nil }

        let timeMs = Int(((viewModel.audioEngine?.currentTime ?? 0) * 1000).rounded())
        return timeMs < first.startMs ? first.id : last.id
    }

    /// Pide un centrado. El token hace que la petición siempre sea distinta de la
    /// anterior (y que un scroll a la MISMA línea no se descarte).
    private func requestScroll(to lineID: Int) {
        scrollToken += 1
        scrollRequest = ScrollRequest(lineID: lineID, token: scrollToken)
    }

    // MARK: - Header
    private var headerView: some View {
        HStack(spacing: 0) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Localization.localized("nowPlaying.close"))

            Spacer()

            Text(Localization.localized("nowPlaying.lyrics"))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.9))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 1)

            Spacer()

            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Contenido de lyrics
    private var lyricsContentView: some View {
        // ✅ El ancho real se mide aquí (UNA vez, no por fila) y se pasa a cada
        // línea: el troceo por medición necesita saber cuánto texto cabe.
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    // ✅ La altura del área de scroll (ya descontado el header) es
                    // la que define el relleno de centrado: no se depende de la
                    // pantalla completa.
                    lyricsStack(contentWidth: geometry.size.width, viewportHeight: geometry.size.height)
                }
                // ✅ iOS 16 onChange clásico: scroll suave solo cuando cambia el target
                .onChange(of: scrollRequest) { request in
                    scrollToActiveLine(request, proxy: proxy)
                }
            }
        }
    }

    /// ✅ Relleno de media altura visible antes y después: fuerza que la línea
    /// centrada lo esté de forma geométrica (no depende del tamaño de la lista) y
    /// deja margen suficiente para centrar también la PRIMERA y la ÚLTIMA.
    private func lyricsStack(contentWidth: CGFloat, viewportHeight: CGFloat) -> some View {
        // ✅ Media altura visible arriba y abajo → la primera y la última línea
        // pueden quedar centradas de verdad (no solo las de en medio).
        let inset = centeringInset(viewportHeight: viewportHeight)
        return LazyVStack(alignment: .leading, spacing: Self.interlineSpacing) {
            Color.clear.frame(height: inset)

            ForEach(viewModel.lyricsLines) { line in
                lyricLineView(line: line, contentWidth: contentWidth)
                    .id(line.id)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        seekToLine(line)
                    }
            }

            Color.clear.frame(height: inset)
        }
        .padding(.horizontal, Self.horizontalPadding)
    }

    /// ✅ Scroll centrado y natural (spring 0.35s, damping 0.85, el tacto de
    /// Apple Music) al cambiar de línea activa. Cuanto más corto es el solape
    /// entre la animación del scroll y el wipe a 60 fps de la línea entrante,
    /// menos tirones se ven en la transición.
    /// ✅ El PRIMER centrado (entrada / cambio de canción) va sin animación: el
    /// usuario no ve la letra "llegar" desde la primera línea.
    private func scrollToActiveLine(_ request: ScrollRequest?, proxy: ScrollViewProxy) {
        guard let request else { return }

        // ✅ Con un overlay del sistema encima (Centro de Control) el scroll se
        // hace SIN animación: animar aquí es robarle frames al panel del sistema
        // por un movimiento que el usuario ni ve. Al volver, la lista ya está en
        // el sitio correcto.
        if hasDoneInitialScroll, renderState.isSceneActive {
            withAnimation(scrollAnimation) {
                proxy.scrollTo(request.lineID, anchor: .center)
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                proxy.scrollTo(request.lineID, anchor: .center)
            }
            hasDoneInitialScroll = true
        }
    }

    /// ✅ Animación del auto-scroll. El spring de 0.35 s es el tacto de Apple
    /// Music, pero durante la grabación genera frames intermedios que la captura
    /// no siempre completa (el desplazamiento se veía "a saltos" en el vídeo):
    /// bajo captura se usa un easeOut corto, casi idéntico a la vista y mucho más
    /// estable en la grabación.
    private var scrollAnimation: Animation {
        captureMonitor.isCaptured
            ? .easeOut(duration: 0.3)
            : .spring(response: 0.35, dampingFraction: 0.85)
    }

    /// ✅ Ancla del efecto lupa: la línea ACTIVA o, mientras no hay activa (intro
    /// instrumental / outro), la provisional que el scroll centra. Es el mismo
    /// criterio con el que se centra la lista, así el foco visual y el centro de
    /// la pantalla no pueden discrepar al abrir ni al terminar la canción.
    private var focusAnchorID: Int? {
        viewModel.activeID ?? centeringFallbackLineID()
    }

    /// ✅ Distancia de una fila al foco, medida en LÍNEAS (`LyricsLine.id` es el
    /// índice: invariante de los dos parsers). No se mide geometría por frame a
    /// propósito: ver `LyricFocus`.
    private func focusDistance(to lineID: Int) -> Int {
        guard let anchor = focusAnchorID else { return LyricFocus.farDistance }
        return min(abs(lineID - anchor), LyricFocus.farDistance)
    }

    /// ✅ Condiciones de render que comparten la vista y TODAS las filas: se
    /// calculan en un solo sitio para que el criterio no se pueda desincronizar.
    private var renderState: LyricRenderState {
        LyricRenderState(
            isSceneActive: scenePhase == .active,
            isCaptured: captureMonitor.isCaptured
        )
    }

    // MARK: - Línea individual
    /// ✅ El scroll se hace en DOS fases (activeID → scrollRequest → scrollTo) a
    /// propósito: así la línea activa se centra también cuando el ScrollView
    /// nace en el mismo ciclo en que el parser publica `activeID` (con un solo
    /// onChange dentro del ScrollViewReader ese primer centrado se perdería).
    private func lyricLineView(line: LyricsLine, contentWidth: CGFloat) -> some View {
        LyricLineView(
            line: line,
            isActive: viewModel.activeID == line.id,
            isPlaying: viewModel.isPlaying,
            viewModel: viewModel,
            // ✅ Ancho ÚTIL para el texto (sin el padding horizontal): es lo que
            // se mide para trocear las filas que SwiftUI envolvería.
            availableWidth: max(0, contentWidth - Self.horizontalPadding * 2),
            glowColor: glowColor,
            // ✅ Distancia al foco de la línea ACTIVA. Con ella se resuelve el
            // efecto lupa sin medir geometría por frame (ver `LyricFocus`).
            focusDistance: focusDistance(to: line.id),
            // ✅ Condiciones de render (overlay del sistema / grabación): van como
            // valor para que formen parte de la igualdad de la fila; si no, el
            // diff de `.equatable()` no las vería cambiar.
            renderState: renderState
        )
        // ✅ Solo las filas cuyo contenido ha cambiado vuelven a evaluar su body:
        // al cambiar de línea activa (o al hacer scroll) se evita re-evaluar todo
        // el LazyVStack visible.
        .equatable()
        // ✅ INDICADOR DEL INTERLUDIO EN EL FLUJO: cuelga de ESTA fila solo si es
        // la focal del hueco (durante el interludio `activeID` ES la última línea
        // cantada, la que el auto-scroll mantiene centrada) y se dibuja en la
        // banda vacía de debajo, alineado con el texto. `.overlay` no participa
        // en el layout: ni la fila cambia de alto (el verso cantado no se mueve)
        // ni el LazyVStack gana hijos (el diff que en 292218b hacía desaparecer
        // letras no se puede reproducir desde aquí).
        .overlay(alignment: .bottomLeading) { interludeIndicator(for: line) }
        // ✅ INDICADOR DEL INTRO EN EL FLUJO: misma idea, colgado del borde de
        // ARRIBA de la PRIMERA fila, porque la pseudo-línea va ANTES de la primera
        // letra. El indicador NO es una fila: no entra en `lyricsLines` ni pide un
        // ID nuevo, y el overlay no toca el layout (ver `introIndicator`).
        .overlay(alignment: .topLeading) { introIndicator(for: line) }
    }

    /// ✅ Indicador del interludio: su propio sitio en el flujo, sin mover nada.
    /// · Alineación: `.bottomLeading` sobre la fila, que ya vive dentro del
    ///   padding horizontal de 24 pt del stack → la misma columna que el texto,
    ///   sin repetir aquí el 24.
    /// · Separación: `gapIndicatorOutset` hacia la banda vacía entre las dos
    ///   líneas, centrado en ella (ni pegado al verso cantado ni a la siguiente).
    /// · Frames: el TimelineView del indicador solo EXISTE con `isHost` (mismo
    ///   patrón que la línea activa del karaoke); fuera del interludio no hay
    ///   ninguna suscripción nueva.
    @ViewBuilder
    private func interludeIndicator(for line: LyricsLine) -> some View {
        let isHost = viewModel.isInstrumentalGap && line.id == viewModel.activeID

        Group {
            if isHost {
                LyricInstrumentalIndicator(
                    glowColor: glowColor,
                    isPlaying: viewModel.isPlaying,
                    renderState: renderState
                )
                .offset(y: Self.gapIndicatorOutset)
                .transition(.opacity)
            }
        }
        // ✅ Fundido SCOPED al indicador: antes vivía en la raíz de la vista y, en
        // el mismo update en que el interludio termina, también cambian la línea
        // activa y el scroll de la lista; desde la raíz esa animación envolvía
        // TODO el layout del LazyVStack (frames de más en el cambio de verso).
        .animation(.easeInOut(duration: 0.3), value: isHost)
        // ✅ Sin hit-testing: los toques de la fila siguen siendo del seek.
        .allowsHitTesting(false)
    }

    /// ✅ Indicador del INTRO instrumental: mismo componente y misma banda, con la
    /// colocación espejada (el hueco está antes de la primera letra, no entre dos
    /// versos).
    /// · Se cuelga de la PRIMERA fila, que durante el intro es además la focal del
    ///   scroll (`centeringFallbackLineID` devuelve la primera mientras no ha
    ///   empezado ninguna): el indicador queda centrado sin tocar el auto-scroll,
    ///   sin reservar un ID en el espacio de índices (que es `id == índice` para el
    ///   foco y para el karaoke) y sin añadir filas al LazyVStack.
    /// · `-gapIndicatorOutset` con `.topLeading`: sale hacia la banda vacía de
    ///   arriba y queda a la misma distancia de la primera letra que el interludio
    ///   de la suya (12.5 pt).
    /// · Frames: idéntico al interludio — el TimelineView solo EXISTE con el flag
    ///   activo. Además, durante el intro no hay línea activa, así que el karaoke
    ///   no está pidiendo frames: el pulso es la única animación de la vista.
    @ViewBuilder
    private func introIndicator(for line: LyricsLine) -> some View {
        let isHost = viewModel.isIntroGap && line.id == viewModel.lyricsLines.first?.id

        Group {
            if isHost {
                LyricInstrumentalIndicator(
                    glowColor: glowColor,
                    isPlaying: viewModel.isPlaying,
                    renderState: renderState
                )
                .offset(y: -Self.gapIndicatorOutset)
                .transition(.opacity)
            }
        }
        // ✅ Mismo fundido scoped que el interludio (0.3 s): al empezar la primera
        // línea, el update que la activa también baja el flag, y ni el cambio de
        // línea ni el scroll se ven envueltos por esta animación.
        .animation(.easeInOut(duration: 0.3), value: isHost)
        .allowsHitTesting(false)
    }

    // MARK: - Seek a línea
    private func seekToLine(_ line: LyricsLine) {
        guard let audioEngine = viewModel.audioEngine else { return }

        // ✅ Seek al inicio de la línea
        let seekTime = TimeInterval(line.startMs) / 1000.0
        audioEngine.seek(to: seekTime)

        // ✅ Recalcular línea activa inmediatamente
        viewModel.handleSeek()
    }

    // MARK: - Vista vacía
    private var emptyLyricsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.5))

            Text(Localization.localized("lyrics.noLyrics"))
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Parse lyrics
    private func parseLyricsIfNeeded() {
        guard let song = song else { return }

        // ✅ Usar lyrics del modelo de canción (ya parseado en FileAccessService)
        let lyrics = song.lyrics
        if !lyrics.isEmpty {
            viewModel.parseLyrics(lyrics)
            // ✅ La línea activa se fija con el tiempo REAL de reproducción antes
            // del primer centrado (entrar en el minuto 2:30 no muestra la línea 1).
            viewModel.syncToCurrentTime()
        } else {
            viewModel.clearLyrics()
        }
    }
}

// MARK: - Fondo dinámico "Aurora" (carátula desenfocada + vidrio + tinte)
/// ✅ Vista PROPIA y `Equatable`: el body de `LyricsView` se re-evalúa en cada
/// cambio de línea activa; con `.equatable()` esta sub-vista no vuelve a componer
/// el desenfoque de pantalla completa si la carátula y el acento no han cambiado
/// (era el candidato a los tirones al cambiar de verso).
/// ✅ Tres capas y TODAS estáticas: carátula desenfocada, vidrio esmerilado y
/// tinte del acento. Aquí está la clave de los 60 fps: el material necesita
/// muestrear lo que tiene DETRÁS, y detrás solo hay capas fijas (la carátula y el
/// propio material); lo que sí anima —el karaoke, los puntos del interludio—
/// vive POR ENCIMA del vidrio, así que el fondo se compone una vez al cambiar de
/// canción y no se vuelve a tocar ni un frame más.
/// ✅ Sin `.drawingGroup()`: rasterizaría el material dentro de un pase Metal y
/// los materiales pierden ahí su muestreo del fondo (se ven como color plano).
private struct LyricsArtworkBackground: View, Equatable {
    let artwork: UIImage?
    /// ✅ Solo como TOKEN de comparación: el color se pinta con `AppTheme.accent`
    /// para no alterar el tono con conversiones de espacio de color.
    let accentToken: UIColor
    /// ✅ "Reducir transparencia": fondo plano, sin material ni desenfoque.
    let reduceTransparency: Bool

    static func == (lhs: LyricsArtworkBackground, rhs: LyricsArtworkBackground) -> Bool {
        guard lhs.accentToken == rhs.accentToken,
              lhs.reduceTransparency == rhs.reduceTransparency else { return false }
        if let lhsArtwork = lhs.artwork, let rhsArtwork = rhs.artwork {
            return lhsArtwork === rhsArtwork
        }
        return lhs.artwork == nil && rhs.artwork == nil
    }

    /// ✅ Calibración del fondo en UN solo sitio (intensidad, desenfoque y tinte).
    private enum Design {
        /// ✅ Miniatura de 400 px + desenfoque de 40 pt: mismo aspecto que
        /// desenfocar la carátula completa, pero decodificando ~1/10 de los
        /// píxeles (patrón que ya usa la cabecera de `PlaylistsView`). En un 8 Plus
        /// es la diferencia entre pagar el desenfoque una vez o arriesgar un pico
        /// de memoria al abrir la hoja.
        static let thumbnailSize = CGSize(width: 400, height: 400)
        static let artworkBlurRadius: CGFloat = 40
        /// ✅ Techo del rango pedido (0.35-0.45): el vidrio de encima ya rebaja la
        /// presencia de la carátula, así que la capa de abajo va generosa.
        static let artworkOpacity: Double = 0.45
        /// ✅ Tinte del acento: fuerte arriba (la "aurora") y desvanecido abajo.
        static let accentTopOpacity: Double = 0.30
        static let accentMidOpacity: Double = 0.08
        /// ✅ Con "reducir transparencia" (o sin carátula) la base es plana, así que
        /// el tinte sube un poco para que el fondo siga teniendo identidad.
        static let flatTopOpacity: Double = 0.18
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                artworkLayer(in: geometry.size)
                glassLayer
                tintLayer
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// 1️⃣ Carátula desenfocada (la única fuente de color del fondo).
    @ViewBuilder
    private func artworkLayer(in size: CGSize) -> some View {
        if let artwork, !reduceTransparency {
            Image(uiImage: AppTheme.thumbnail(from: artwork, size: Design.thumbnailSize))
                .resizable()
                .interpolation(.medium)
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .blur(radius: Design.artworkBlurRadius)
                .opacity(Design.artworkOpacity)
        } else {
            Color(UIColor.systemBackground)
        }
    }

    /// 2️⃣ Vidrio esmerilado: `.ultraThinMaterial` (el más transparente de los
    /// materiales del sistema, el único que deja leer la carátula que tiene
    /// debajo). Con "reducir transparencia" se sustituye por superficie opaca,
    /// igual que hace `nativeGlass` en el resto de la app.
    /// ⚠️ El vidrio va DEBAJO del tinte a propósito: el material difumina lo que
    /// tiene detrás y, si el acento quedara debajo, entraría al vídeo lavado. La
    /// carátula —que sí debe fundirse con el vidrio— está debajo, que es lo que
    /// pide el efecto esmerilado.
    @ViewBuilder
    private var glassLayer: some View {
        if reduceTransparency {
            Color(UIColor.secondarySystemBackground)
        } else {
            Rectangle().fill(.ultraThinMaterial)
        }
    }

    /// 3️⃣ Tinte del acento ACTUAL (`AppTheme.accent` respeta "acento desde
    /// carátula"): si la portada es gris-azulada, el fondo queda gris-azulado.
    /// Ningún color hardcodeado aquí.
    private var tintLayer: some View {
        LinearGradient(
            stops: [
                .init(color: AppTheme.accent.opacity(tintTopOpacity), location: 0),
                .init(color: AppTheme.accent.opacity(Design.accentMidOpacity), location: 0.45),
                .init(color: AppTheme.accent.opacity(0), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var tintTopOpacity: Double {
        reduceTransparency || artwork == nil ? Design.flatTopOpacity : Design.accentTopOpacity
    }
}

// MARK: - Indicador de gap instrumental ("• • •" en el intro y el interludio)
// ✅ Estilo Aurora: tres puntos que RESPIRAN (opacidad 0.4 → 1.0 en un ciclo
//    lento de ~2.6 s, con el acento de la carátula) mientras dura el hueco
//    instrumental (≥ 3s detectado por LyricsViewModel): el INTERLUDIO entre dos
//    líneas (`isInstrumentalGap`) y el INTRO antes de la primera (`isIntroGap`).
// ✅ EN EL FLUJO, no flotando: el contenedor lo cuelga de una FILA con
//    `.overlay` (ver `LyricsView.interludeIndicator` / `LyricsView.introIndicator`),
//    así ocupa la banda vacía que YA existe junto a la línea focal —su propio
//    espacio, en la misma columna que el texto— sin cambiar el alto de la fila ni
//    añadir hijos al LazyVStack.
// ✅ Cero frames cuando no hay hueco: la vista solo existe con su flag activo (el
//    `if` del contenedor) y, dentro, el TimelineView se desarma si no hay
//    reproducción o la escena no está activa. Mismo patrón que la línea activa
//    del karaoke: la suscripción de frames vive dentro del estado que la
//    necesita, nunca en la vista completa.
// ✅ `TimelineView(.animation)` y NO `repeatForever`: la respiración se calcula
//    con una fase continua sobre la fecha de CADA frame, así el ritmo no depende
//    del momento en que se insertó el overlay (con `repeatForever` el arranque
//    coincidía con la transición de entrada y el pulso nacía desfasado) y el
//    mismo código sirve para bajar el ritmo a 30 fps bajo grabación.
private struct LyricInstrumentalIndicator: View {
    let glowColor: Color
    let isPlaying: Bool
    /// ✅ Overlay del sistema / grabación de pantalla: cambia el ritmo de frames y
    /// si se paga el halo (la MISMA condición que usa el karaoke para su glow).
    let renderState: LyricRenderState

    /// ✅ Radio de un punto, expuesto al CONTENEDOR: la fila que aloja el
    /// indicador necesita saber cuánto mide para centrarlo en la banda vacía (la
    /// separación del stack la conoce el stack, no este view).
    static let dotRadius: CGFloat = Design.dotSize / 2

    /// ✅ Identidad y calibración del indicador en un solo sitio: el tamaño y el
    /// espaciado no cambian; lo que respira es la opacidad.
    private enum Design {
        static let dotSize: CGFloat = 7
        static let dotSpacing: CGFloat = 6
        static let dotCount = 3
        /// ✅ Ciclo de respiración (~2.6 s): lento, nunca parpadeo.
        static let breathPeriod: Double = 2.6
        /// ✅ Mismo suelo de tenuidad que la letra que aún no suena
        /// (`LyricDim.inactiveOpacity`): el indicador pertenece a la familia de
        /// las líneas inactivas y el pulso sube desde ahí, nunca más apagado.
        static let minOpacity: Double = LyricDim.inactiveOpacity
        static let maxOpacity: Double = 1.0
        /// ✅ Desfase entre puntos: la onda recorre el grupo (orgánico), no son
        /// tres latidos sincronizados.
        static let phaseStep: Double = 0.22
        /// ✅ Reposo (pausa y grabación): punto medio del ciclo, ni apagado ni
        /// encendido, y sin gastar ni un frame.
        static let restingOpacity: Double = 0.7
        /// ✅ Halo: UNA copia desenfocada del grupo entero (una sola pasada fuera
        /// de pantalla para los tres puntos, no tres) con el acento del karaoke.
        static let haloRadius: CGFloat = 5
        static let haloOpacity: Double = 0.75
    }

    var body: some View {
        Group {
            if breathes {
                TimelineView(.animation(minimumInterval: frameInterval)) { context in
                    dots(opacities: opacities(at: context.date))
                }
            } else {
                dots(opacities: Array(repeating: Design.restingOpacity, count: Design.dotCount))
            }
        }
        // ✅ Sin padding propio: la colocación la decide la FILA que lo aloja
        // (alineación por `.bottomLeading` y `gapIndicatorOutset`), que es quien
        // conoce la separación del stack y el padding del contenido. Así el
        // indicador queda en la misma columna que el texto sin duplicar aquí ni
        // el 24 ni el 8.
    }

    /// ✅ ¿Se piden frames? Solo con reproducción Y escena en primer plano Y sin
    /// la política de captura activada. Cualquier otra combinación es UN dibujo.
    private var breathes: Bool {
        guard isPlaying, renderState.isSceneActive else { return false }
        if renderState.isCaptured, LyricCapturePolicy.dropsInstrumentalPulseWhileCaptured {
            return false
        }
        return true
    }

    /// ✅ Bajo grabación, si la respiración se mantiene, va a 30 fps alineados con
    /// el vsync (el mismo ritmo que el karaoke); sin captura, sin límite.
    private var frameInterval: Double? {
        renderState.isCaptured ? LyricCapturePolicy.capturedFrameInterval : nil
    }

    /// ✅ Fase continua por punto: una sinusoide lenta sobre la fecha del frame. Ni
    /// temporizadores ni animaciones en bucle: no hay estado que se pueda
    /// desincronizar al entrar o salir del interludio.
    private func opacities(at date: Date) -> [Double] {
        let cycle = date.timeIntervalSinceReferenceDate / Design.breathPeriod
        let range = Design.maxOpacity - Design.minOpacity

        return (0..<Design.dotCount).map { dot in
            let wave = 0.5 + 0.5 * sin(2 * Double.pi * (cycle + Double(dot) * Design.phaseStep))
            return Design.minOpacity + wave * range
        }
    }

    /// ✅ Puntos + halo, con el MISMO acento que el karaoke. El halo se suelta con
    /// la política que ya decide si el karaoke paga su copia desenfocada: un solo
    /// criterio para las dos cosas que brillan.
    @ViewBuilder
    private func dots(opacities: [Double]) -> some View {
        let dots = HStack(spacing: Design.dotSpacing) {
            ForEach(0..<Design.dotCount, id: \.self) { dot in
                Circle()
                    .fill(glowColor)
                    .frame(width: Design.dotSize, height: Design.dotSize)
                    .opacity(opacity(at: dot, in: opacities))
            }
        }

        ZStack {
            if renderState.showsGlow {
                dots
                    .blur(radius: Design.haloRadius)
                    .opacity(Design.haloOpacity)
            }
            dots
        }
    }

    /// ✅ Acceso seguro: la lista siempre trae los tres valores, pero un índice
    /// fuera de rango en el render de la hoja no se paga con un crash.
    private func opacity(at dot: Int, in opacities: [Double]) -> Double {
        opacities.indices.contains(dot) ? opacities[dot] : Design.restingOpacity
    }
}

// MARK: - Troceo por medición real (filas que SwiftUI partiría por ancho)
/// ✅ El modelo no conoce el ancho ni la fuente, así que una fila lógica larga
/// (sin `<br/>`) la partía SwiftUI por anchura y la máscara —un solo rectángulo
/// sobre el `Text` completo— iluminaba TODAS las líneas envueltas a la vez.
/// Aquí se mide el texto con la fuente real y se trocea en filas de verdad: cada
/// trozo se dibuja como `Text` propio con su ventana temporal (reparto
/// proporcional al nº de caracteres), así el wipe avanza de arriba abajo.
/// ✅ Si la medición se queda corta por milímetros, el peor caso es que ESE trozo
/// envuelva dentro de sí mismo: nunca se recorta ni se pierde texto.
private enum LyricRowSplitter {
    /// Por debajo de este ancho no se intenta trocear (geometría aún sin medir).
    private static let minimumUsableWidth: CGFloat = 40
    /// ✅ Margen de seguridad: la medición con `UIFont` y el render de SwiftUI
    /// pueden diferir en una fracción; trocear un 1,5% antes evita que un trozo
    /// envuelva por sorpresa (peor caso: una palabra baja a la fila siguiente).
    private static let safetyMargin: CGFloat = 0.985
    /// ✅ Cacheado por (texto + fuente + ancho) para no medir en cada render, con
    /// tope de entradas: una canción de 500 líneas en sus dos estados (activa a
    /// 24pt e inactiva a 18pt) no debe crecer sin límite (iPhone 8 Plus / 3GB).
    private static let cache: NSCache<NSString, NSArray> = {
        let cache = NSCache<NSString, NSArray>()
        cache.countLimit = 600
        return cache
    }()

    static func split(_ text: String, fontSize: CGFloat, weight: UIFont.Weight, maxWidth: CGFloat) -> [String] {
        guard !text.isEmpty, maxWidth >= minimumUsableWidth else { return [text] }

        let key = "\(Int(fontSize.rounded()))|\(weight.rawValue)|\(Int(maxWidth.rounded()))|\(text)" as NSString
        if let cached = cache.object(forKey: key) as? [String] { return cached }

        let font = UIFont.systemFont(ofSize: fontSize, weight: weight)
        let parts = wrap(text, font: font, maxWidth: maxWidth)
        cache.setObject(parts as NSArray, forKey: key)
        return parts
    }

    /// Reparto voraz por palabras (y por caracteres cuando no hay espacios, p. ej.
    /// CJK). Una palabra sola más ancha que la fila se deja entera.
    private static func wrap(_ text: String, font: UIFont, maxWidth: CGFloat) -> [String] {
        var lines: [String] = []
        var current = ""

        for word in text.components(separatedBy: " ") {
            let candidate = current.isEmpty ? word : current + " " + word
            if current.isEmpty || width(of: candidate, font: font) <= maxWidth * safetyMargin {
                current = candidate
            } else {
                lines.append(current)
                current = word
            }
        }
        if !current.isEmpty { lines.append(current) }

        if lines.count == 1, let only = lines.first, width(of: only, font: font) > maxWidth * safetyMargin {
            return splitByCharacter(only, font: font, maxWidth: maxWidth)
        }
        return lines.isEmpty ? [text] : lines
    }

    private static func splitByCharacter(_ text: String, font: UIFont, maxWidth: CGFloat) -> [String] {
        var lines: [String] = []
        var current = ""

        for character in text {
            let candidate = current + String(character)
            if current.isEmpty || width(of: candidate, font: font) <= maxWidth * safetyMargin {
                current = candidate
            } else {
                lines.append(current)
                current = String(character)
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines.isEmpty ? [text] : lines
    }

    private static func width(of text: String, font: UIFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }
}

// MARK: - Voces de fondo de Apple Music (`ttm:role="x-bg"`)
/// ✅ En la app de Apple las voces de fondo se pintan más pequeñas y más tenues
/// que la voz principal. Solo se aplica a filas COMPLETAS de voz de fondo: una
/// fila con mezcla se pinta normal, porque mezclar tamaños dentro de una misma
/// máscara rompería el reparto del relleno.
/// ✅ La MISMA regla la usan el troceo por medición y el render, de modo que el
/// tamaño con el que se mide una fila es el tamaño con el que se pinta.
private enum LyricBackgroundVoice {
    static let fontScale: CGFloat = 0.86
    static let opacity: Double = 0.8

    static func isOnlyBackground(_ row: LyricVisualRow) -> Bool {
        !row.words.isEmpty && row.words.allSatisfy { $0.isBackground }
    }

    static func fontSize(_ base: CGFloat, for row: LyricVisualRow) -> CGFloat {
        isOnlyBackground(row) ? base * fontScale : base
    }
}

// MARK: - Filas reales (lógicas + troceo por medición)
private enum LyricRowBuilder {
    /// ✅ Cada trozo hereda un sub-rango de la ventana de su fila lógica, en
    /// proporción al nº de caracteres (misma regla que el modelo cuando no hay
    /// timings por palabra), así las ventanas quedan encadenadas y el trozo N+1
    /// no empieza hasta que el N termina.
    /// ✅ Cuando la fila SÍ trae timings de palabra y se pueden repartir entre los
    /// trozos de forma demostrable, cada trozo usa la ventana real de sus palabras
    /// (y se las lleva, que es lo que permite el karaoke por palabra).
    static func rows(
        from logicalRows: [LyricVisualRow],
        fontSize: CGFloat,
        weight: UIFont.Weight,
        maxWidth: CGFloat
    ) -> [LyricVisualRow] {
        var result: [LyricVisualRow] = []
        result.reserveCapacity(logicalRows.count)

        for row in logicalRows {
            // ✅ El troceo usa el tamaño REAL con el que se va a pintar la fila: las
            // voces de fondo van más pequeñas, así que caben más palabras por línea
            // y no se parten antes de tiempo.
            let rowFontSize = LyricBackgroundVoice.fontSize(fontSize, for: row)
            let parts = LyricRowSplitter.split(row.text, fontSize: rowFontSize, weight: weight, maxWidth: maxWidth)
            guard parts.count > 1 else {
                result.append(row)
                continue
            }

            // ✅ Si los timings de palabra se pueden repartir entre los trozos, cada
            // trozo toma la ventana REAL de sus palabras; si no, se conserva el
            // reparto proporcional al nº de caracteres.
            let chunks = LyricWordAligner.split(words: row.words, parts: parts)

            let span = Double(max(row.endMs - row.startMs, 1))
            let totalCharacters = max(1, parts.reduce(0) { $0 + $1.count })
            var charactersBefore = 0
            var previousEndMs = row.startMs

            for (index, part) in parts.enumerated() {
                let characterStart = row.startMs + Int((span * Double(charactersBefore) / Double(totalCharacters)).rounded())
                let characterEnd = row.startMs + Int((span * Double(charactersBefore + part.count) / Double(totalCharacters)).rounded())
                charactersBefore += part.count

                var startMs = max(characterStart, previousEndMs)
                var endMs = max(characterEnd, startMs + 1)
                var partWords: [LyricWordToken] = []

                if let chunk = chunks?[index], let first = chunk.first, let last = chunk.last {
                    startMs = max(min(first.startMs, row.endMs), previousEndMs)
                    endMs = max(min(last.endMs, row.endMs), startMs + 1)
                    partWords = LyricsLine.clampedWords(chunk, startMs: startMs, endMs: endMs)
                }

                previousEndMs = endMs
                result.append(LyricVisualRow(
                    text: part,
                    startMs: startMs,
                    endMs: endMs,
                    words: partWords
                ))
            }
        }

        return result
    }
}

// MARK: - Línea individual con relleno progresivo (estilo Apple Music)
// ✅ Struct (no clase) y sin envoltorios de tipo borrado: el cuerpo solo se
//    re-evalúa cuando cambia el estado de activación; el TimelineView
//    recalcula únicamente su contenido.
private struct LyricLineView: View, Equatable {
    let line: LyricsLine
    let isActive: Bool
    /// ✅ Valor explícito (en lugar de leer `viewModel.isPlaying` dentro): forma
    /// parte de la comparación, así la vista se entera de play/pause sin
    /// depender de que el padre se re-evalúe.
    let isPlaying: Bool
    let viewModel: LyricsViewModel
    /// ✅ Ancho útil para el texto: el troceo por medición real depende de él.
    let availableWidth: CGFloat
    /// ✅ Acento (de la carátula si el ajuste está activo): con él se pinta el
    /// "glow" de la capa brillante del karaoke.
    let glowColor: Color
    /// ✅ Distancia (en líneas) a la línea activa: alimenta el efecto lupa de las
    /// filas que no están en el foco. Forma parte de la igualdad de la vista.
    let focusDistance: Int
    /// ✅ Overlay del sistema / grabación de pantalla: cambia el ritmo del reloj
    /// de frames y qué pasadas caras (halo, desenfoque) se pagan.
    let renderState: LyricRenderState

    /// ✅ Separación entre filas visuales de una misma línea lógica (también en
    /// la capa atenuada, para que el texto no salte al activarse la línea).
    private static let rowSpacing: CGFloat = 2

    /// ✅ Igualdad = "¿está igual lo que esta fila PINTA?". Del viewModel solo se
    /// compara la IDENTIDAD (misma instancia), nunca su estado mutable: el estado
    /// vivo (reloj, línea activa) solo se lee DENTRO del TimelineView, que se
    /// actualiza por frame por su cuenta y sin depender de este diff.
    /// ✅ Sin `.drawingGroup()`: rasterizaría el texto antes del "pop" de escala
    /// y la animación de entrada se vería borrosa (la máscara ya compone fuera
    /// de pantalla, así que tampoco ahorraría una pasada).
    static func == (lhs: LyricLineView, rhs: LyricLineView) -> Bool {
        lhs.isActive == rhs.isActive
            && lhs.isPlaying == rhs.isPlaying
            && lhs.viewModel === rhs.viewModel
            && lhs.line == rhs.line
            && lhs.availableWidth == rhs.availableWidth
            && lhs.glowColor == rhs.glowColor
            && lhs.focusDistance == rhs.focusDistance
            && lhs.renderState == rhs.renderState
    }

    /// ✅ Una fila LISTA para pintar. Todo lo caro (medición del texto, reparto de
    /// los timings de palabra, tamaño de fuente) se resuelve aquí, FUERA del
    /// TimelineView: el bucle de frames solo interpola `Double` y no vuelve a
    /// medir texto ni a construir claves de caché.
    private struct RenderRow {
        let text: String
        /// Fila del MODELO: su ventana y sus timings de palabra son los que
        /// consume el motor de lyrics para calcular el relleno.
        let source: LyricVisualRow
        let fontSize: CGFloat
        let isBackground: Bool
        /// Fracciones de ancho acumuladas al final de cada palabra (nil = la fila
        /// no tiene timings utilizables y se rellena de forma lineal por fila).
        let wordFractions: [Double]?
    }

    private var fontSize: CGFloat {
        isActive ? 24 : 18
    }

    private var fontWeight: Font.Weight {
        isActive ? .bold : .regular
    }

    var body: some View {
        // ✅ Las filas REALES se calculan AQUÍ, fuera del TimelineView: el troceo
        // por medición y el karaoke por palabra se pagan una sola vez por línea
        // (y quedan cacheados), nunca por frame.
        let rows = renderRows

        Group {
            if isActive {
                activeLine(rows)
                    // ✅ Al ganar el foco, la capa brillante entra con el spring
                    // de la línea; al perderlo se funde hacia la capa atenuada
                    // (0.2s easeInOut) en vez de cambiar de golpe.
                    .transition(.asymmetric(
                        insertion: .opacity.animation(lineActivation),
                        removal: .opacity.animation(.easeInOut(duration: 0.2))
                    ))
            } else {
                dimmedRows(rows, opacityMultiplier: focus.dimMultiplier)
                    // ✅ Profundidad SOLO de las líneas inactivas y SOLO a partir del
                    // segundo nivel de distancia: la activa es la que pide frames a
                    // 60 Hz y no debe pagar ninguna pasada fuera de pantalla, y la
                    // vecina (distancia 1) conserva la nitidez del texto que el
                    // usuario está a punto de cantar.
                    // ✅ Bajo grabación el radio llega en 0 y el modificador
                    // desaparece: cada blur es una pasada por línea y la captura no
                    // siempre la completa (en el vídeo se veía como parpadeo).
                    .modifier(InactiveDepthBlur(radius: focus.blurRadius))
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        // ✅ EFECTO LUPA: "pop" premium al cambiar de línea y, además, las filas
        // que se alejan del foco siguen encogiéndose y perdiendo tenuidad (el
        // desenfoque va en el modificador de arriba). El valor es el mismo que
        // alimenta la animación, así que una sola declaración cubre los dos casos
        // y la fila ACTIVA cae en la identidad: no paga ningún efecto extra.
        .scaleEffect(focus.scale)
        // ✅ Una sola animación por cambio: entrar o salir del foco usa el spring
        // de la casa; un paso de distancia entre líneas ya inactivas usa el
        // easeInOut corto del efecto lupa. Encadenar dos `.animation(value:)`
        // sobre la misma escala dejaría la curva a merced del orden.
        .animation(focusAnimation, value: focus)
    }

    /// ✅ Estilo del foco de esta fila: distancia 0 = la línea enfocada (la
    /// activa), que es la única que no recibe NINGÚN efecto (conserva su escala
    /// completa y su karaoke intacto).
    private var focus: LyricFocus.Style {
        LyricFocus.style(
            distance: isActive ? 0 : focusDistance,
            blurEnabled: renderState.usesInactiveDepthBlur
        )
    }

    /// ✅ Curva del cambio de foco (ver `body`).
    private var focusAnimation: Animation {
        isActive ? lineActivation : .easeInOut(duration: LyricFocus.transitionDuration)
    }

    /// ✅ Spring del cambio de línea (activación de la capa brillante y pop de
    /// escala). El wipe a 60 fps NO lo usa: el TimelineView interpola por frame.
    private var lineActivation: Animation {
        .spring(response: 0.4, dampingFraction: 0.75)
    }

    /// ✅ Filas REALES de la línea (cacheado por texto+fuente+ancho): las lógicas
    /// del modelo troceadas por medición. Una fila larga sin `<br/>` que SwiftUI
    /// partiría en dos líneas se convierte en DOS filas con su propia ventana de
    /// tiempo, así el relleno avanza de arriba abajo y no ilumina ambas a la vez.
    private var displayedRows: [LyricVisualRow] {
        LyricRowBuilder.rows(
            from: line.visualRows,
            fontSize: fontSize,
            weight: isActive ? .bold : .regular,
            maxWidth: availableWidth
        )
    }

    /// ✅ Prepara las filas del render: tamaño de fuente real (las voces de fondo
    /// van más pequeñas) y, SOLO en la línea activa (la única que hace karaoke),
    /// las fracciones de ancho por palabra. Las líneas inactivas no pagan ni una
    /// medición de texto.
    private var renderRows: [RenderRow] {
        let baseSize = fontSize
        let weight: UIFont.Weight = isActive ? .bold : .regular

        return displayedRows.map { row in
            let isBackground = LyricBackgroundVoice.isOnlyBackground(row)
            let rowFontSize = LyricBackgroundVoice.fontSize(baseSize, for: row)
            let fractions = isActive && !row.words.isEmpty
                ? LyricWordMeasure.fractions(
                    text: row.text,
                    words: row.words,
                    fontSize: rowFontSize,
                    weight: weight
                )
                : nil

            return RenderRow(
                text: row.text,
                source: row,
                fontSize: rowFontSize,
                isBackground: isBackground,
                wordFractions: fractions
            )
        }
    }

    // MARK: Línea activa (relleno animado, fila a fila)
    /// ✅ Con reproducción activa se piden frames a 60 Hz; en pausa se dibuja el
    /// estado congelado una sola vez (sin gastar GPU/batería).
    @ViewBuilder
    private func activeLine(_ rows: [RenderRow]) -> some View {
        if isPlaying, renderState.isSceneActive {
            if renderState.isCaptured {
                // ✅ Grabación de pantalla activa: el sistema captura cada frame
                // que dibujamos, así que el karaoke baja a 30 fps. Es
                // `TimelineView(.animation(minimumInterval:))` y NO `.periodic`:
                // sigue colgado del vsync (frames alineados con la pantalla y con
                // el codificador) y solo limita el ritmo; un timer periódico no
                // está alineado y produciría justo el síntoma a evitar (frames
                // duplicados o saltados en el vídeo).
                TimelineView(.animation(minimumInterval: LyricCapturePolicy.capturedFrameInterval)) { _ in
                    activeRows(rows)
                }
            } else {
                TimelineView(.animation) { _ in
                    activeRows(rows)
                }
            }
        } else {
            // ✅ En pausa o con un overlay del sistema encima (Centro de Control,
            // notificación): UN solo dibujo, sin pedir frames. Al volver, el
            // TimelineView se rearma y el wipe retoma en la posición re-anclada.
            activeRows(rows)
        }
    }

    /// ✅ UN solo TimelineView para la línea completa: cada fila visual lleva su
    /// propia máscara y su propia ventana temporal, pero solo hay UNA
    /// suscripción de frames por línea activa (nunca una por fila).
    private func activeRows(_ rows: [RenderRow]) -> some View {
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            ForEach(rows.indices, id: \.self) { index in
                LyricFillText(
                    text: rows[index].text,
                    fontSize: rows[index].fontSize,
                    fontWeight: fontWeight,
                    progress: easedProgress(rows: rows, index: index),
                    glowColor: glowColor,
                    contentOpacity: rows[index].isBackground ? LyricBackgroundVoice.opacity : 1,
                    glowEnabled: renderState.showsGlow
                )
                // ✅ Las filas ya completadas (o aún sin empezar) tienen el mismo
                // progreso frame a frame → no se redibujan; solo la fila que se
                // está rellenando recalcula su máscara.
                .equatable()
            }
        }
    }

    /// ✅ Misma estructura de filas que la capa activa: el texto de una línea
    /// normal (una sola fila) se dibuja exactamente igual que antes.
    /// ✅ `opacityMultiplier` es el factor del efecto lupa: NUNCA una opacidad
    /// absoluta, para no tocar la tenuidad con la que Aurora Player identifica la
    /// letra que aún no suena (0.4) — la fila vecina a la activa va igual que
    /// siempre y solo las lejanas se atenúan un poco más.
    private func dimmedRows(_ rows: [RenderRow], opacityMultiplier: Double) -> some View {
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            ForEach(rows.indices, id: \.self) { index in
                Text(rows[index].text)
                    .font(.system(size: rows[index].fontSize, weight: fontWeight))
                    .foregroundStyle(Color.primary.opacity(LyricDim.inactiveOpacity * opacityMultiplier))
                    // ✅ Misma escala/tenuidad que en la capa activa: el texto no
                    // puede cambiar de tamaño al activarse la línea.
                    .opacity(rows[index].isBackground ? LyricBackgroundVoice.opacity : 1)
            }
        }
    }

    /// ✅ Smoothstep (t·t·(3−2t)) POR FILA: cada fila se rellena en su propio
    /// rango, así la fila de arriba se completa antes de que empiece la de abajo.
    /// ✅ Con timings por palabra el progreso lo marca la VOZ (cada palabra se
    /// revela en su propia ventana y las que aún no suenan quedan apagadas); sin
    /// ellos se conserva el reparto lineal dentro de la ventana de la fila.
    private func easedProgress(rows: [RenderRow], index: Int) -> Double {
        guard rows.indices.contains(index) else { return 0 }

        let isLastRow = index == rows.count - 1
        let raw: Double

        if let fractions = rows[index].wordFractions,
           let wordProgress = viewModel.wordFillProgress(
               forLineID: line.id,
               row: rows[index].source,
               fractions: fractions,
               isLastRow: isLastRow
           ) {
            raw = wordProgress
        } else {
            raw = viewModel.fillProgress(
                forLineID: line.id,
                row: rows[index].source,
                isLastRow: isLastRow
            )
        }

        return raw * raw * (3 - 2 * raw)
    }
}

// MARK: - Atenuación de la letra que no suena
/// ✅ Apple Music pinta la letra inactiva al 40% de opacidad. Es la MISMA
/// constante para (a) la capa atenuada de una línea inactiva y (b) la parte aún
/// no cantada de la línea activa: así el texto no cambia de tenuidad al
/// activarse su línea (el único cambio es el relleno y el glow).
private enum LyricDim {
    static let inactiveOpacity: Double = 0.4
}

// MARK: - Efecto lupa: protagonismo según la distancia a la línea activa
/// ✅ iOS 16 NO tiene `scrollTransition` (iOS 17) ni `visualEffect` (iOS 17), así
/// que el efecto de enfoque del scroll se calcula con DATOS, no con geometría por
/// frame: la distancia de cada fila a la línea activa, medida en LÍNEAS.
///
/// ⚠️ Por qué NO se mide la distancia en píxeles al centro del viewport con
/// `GeometryReader` + `PreferenceKey` (la alternativa "literal"): obligaría a
/// publicar y recomputar la geometría de TODAS las filas visibles en cada frame
/// del scroll, y eso (a) invalida el `.equatable()` que hoy evita re-evaluar el
/// LazyVStack, (b) re-rasteriza el desenfoque de cada fila inactiva en cada frame
/// y (c) realimenta layout → geometría → layout, que es la fuente clásica de
/// tirones. En un A11, con karaoke a 60 fps y grabación activa, no se sostiene — y
/// la regla del proyecto es no pagar ningún efecto con frames.
///
/// ✅ Y no hace falta medirlo: el auto-scroll mantiene SIEMPRE la línea activa
/// centrada (spring de 0.35 s) —es el 95 % del tiempo de esta vista— y la regla de
/// diseño dice que la línea ACTIVA no recibe el efecto, es decir, el foco ES la
/// línea activa. Con el índice se obtiene el mismo degradado radial durante la
/// reproducción sin una sola operación por frame: el estilo solo cambia cuando
/// cambia la línea activa (una vez por verso, 1-2 filas por vez) y la transición
/// la interpola SwiftUI.
///
/// ✅ Al migrar a iOS 17+, este bloque se sustituye por `.scrollTransition` sin
/// tocar nada más: la vista ya consume exactamente (escala, tenuidad, desenfoque).
private enum LyricFocus {
    /// ✅ Distancia (en líneas) a la que el efecto llega a su tope. Una canción con
    /// 30 líneas fuera de pantalla cuesta lo mismo que una con 3: no se itera
    /// ninguna fila, solo se compara un entero por fila.
    static let farDistance = 3

    /// ✅ Duración del paso de una fila de un nivel de foco a otro.
    static let transitionDuration: Double = 0.25

    struct Style: Equatable {
        let scale: CGFloat
        /// ✅ Multiplicador del 0.4 ya calibrado de la letra inactiva: el efecto
        /// NUNCA fija una opacidad absoluta, para no alterar la tenuidad que
        /// identifica a Aurora Player.
        let dimMultiplier: Double
        /// ✅ Radio del desenfoque de profundidad (0 = sin pasada fuera de
        /// pantalla). Bajo grabación la política lo apaga desde el llamador.
        let blurRadius: CGFloat
    }

    /// ✅ La escalera del efecto. Nivel 0 = la línea enfocada (identidad total) y a
    /// partir de ahí un degradado suave, nunca agresivo: la calibración vive aquí
    /// y en un solo sitio para poder ajustarla tras la prueba en dispositivo.
    static func style(distance: Int, blurEnabled: Bool) -> Style {
        switch distance {
        case ...0:
            // Foco: sin escala, sin atenuación extra y sin desenfoque. La línea
            // activa —la única que pide frames— no paga absolutamente nada.
            return Style(scale: 1.0, dimMultiplier: 1.0, blurRadius: 0)
        case 1:
            // Vecina: conserva el "pop" (0.96) y la tenuidad de siempre, y el
            // texto que el usuario está a punto de cantar sigue nítido.
            return Style(scale: 0.96, dimMultiplier: 1.0, blurRadius: 0)
        case 2:
            return Style(scale: 0.93, dimMultiplier: 0.88, blurRadius: blurEnabled ? 1.5 : 0)
        default:
            return Style(scale: 0.90, dimMultiplier: 0.80, blurRadius: blurEnabled ? 2.5 : 0)
        }
    }
}

// MARK: - Texto con relleno progresivo (dos capas + máscara)
// ✅ Dos capas de texto y una máscara rectangular por frame (es el coste que
//    mantiene el karaoke a 60 fps en el A11).
// ✅ La capa brillante va por DUPLICADO: debajo, una copia tintada con el acento
//    de la carátula y desenfocada (el "glow" de Apple Music); encima, el texto
//    nítido. La máscara recorta AMBAS, así el halo aparece progresivamente con
//    el barrido y no ilumina lo que todavía no ha sonado.
private struct LyricFillText: View, Equatable {
    let text: String
    let fontSize: CGFloat
    let fontWeight: Font.Weight
    let progress: Double
    let glowColor: Color
    /// ✅ Voz de fondo: la fila entera se pinta algo más tenue.
    let contentOpacity: Double
    /// ✅ ¿Se pinta el halo? Bajo grabación se suelta la capa más cara por frame
    /// (copia tintada con el acento + blur) y queda solo el texto brillante.
    let glowEnabled: Bool

    /// ✅ Radio del halo: 2 pt. Es un blur sobre UNA línea de texto (no sobre la
    /// pantalla) y su contenido no cambia, así que SwiftUI lo rasteriza de nuevo
    /// solo cuando cambia la geometría del texto; lo que se recalcula por frame
    /// es únicamente la máscara.
    private static let glowRadius: CGFloat = 2
    private static let glowOpacity: Double = 0.9

    var body: some View {
        ZStack(alignment: .leading) {
            dimmedLayer
            brightLayers.mask(alignment: .leading) { progressMask }
        }
        .opacity(contentOpacity)
    }

    private var font: Font {
        .system(size: fontSize, weight: fontWeight)
    }

    private var dimmedLayer: some View {
        Text(text)
            .font(font)
            .foregroundStyle(Color.primary.opacity(LyricDim.inactiveOpacity))
    }

    @ViewBuilder
    private var brightLayers: some View {
        if glowEnabled {
            ZStack(alignment: .leading) {
                Text(text)
                    .font(font)
                    .foregroundStyle(glowColor)
                    .blur(radius: Self.glowRadius)
                    .opacity(Self.glowOpacity)

                Text(text)
                    .font(font)
                    .foregroundStyle(Color.primary)
            }
        } else {
            // ✅ Sin halo: el texto ya sonado se sigue viendo nítido y a plena
            // intensidad (el "ya cantado" no pierde legibilidad, solo el halo).
            Text(text)
                .font(font)
                .foregroundStyle(Color.primary)
        }
    }

    /// ✅ Ancho de la máscara = ancho REAL del texto × progreso (0...1).
    private var progressMask: some View {
        GeometryReader { geometry in
            Rectangle()
                .frame(width: geometry.size.width * progress)
        }
    }
}

// MARK: - Karaoke por palabra: fracciones de ancho por palabra
/// ✅ Apple Music no reparte la ventana de la fila entre sus caracteres: cada
/// palabra tiene su propio timing y se revela en él. Para pintarlo con UNA sola
/// máscara rectangular se necesita saber QUÉ FRACCIÓN DEL ANCHO de la fila ocupa
/// cada palabra, y eso exige medir el texto con la fuente real (la misma
/// maquinaria que el troceo por anchura).
/// ✅ Se mide UNA vez por (texto + fuente + palabras) y se cachea: el bucle de
/// frames solo recorre un array de `Double`.
/// ✅ El ancho se mide por PREFIJOS: el texto de una fila nunca se reconstruye,
/// así que no hay deriva posible entre lo medido y lo dibujado.
private enum LyricWordMeasure {
    /// Tope de entradas: una canción larga en sus dos estados (activa 24pt e
    /// inactiva 18pt) no debe crecer sin límite (iPhone 8 Plus / 3GB).
    private static let cache: NSCache<NSString, NSArray> = {
        let cache = NSCache<NSString, NSArray>()
        cache.countLimit = 600
        return cache
    }()

    /// Fracción de ancho acumulada al FINAL de cada palabra (la última siempre
    /// vale 1). Devuelve nil si los timings no reproducen el texto de la fila:
    /// en ese caso la fila se rellena de forma lineal, nunca desalineada.
    static func fractions(
        text: String,
        words: [LyricWordToken],
        fontSize: CGFloat,
        weight: UIFont.Weight
    ) -> [Double]? {
        guard !text.isEmpty, !words.isEmpty else { return nil }

        let key = "\(Int(fontSize.rounded()))|\(weight.rawValue)|\(text)|\(words.map(\.text).joined(separator: "\u{1}"))" as NSString
        if let cached = cache.object(forKey: key) as? [Double] { return cached.isEmpty ? nil : cached }

        guard let measured = measure(text: text, words: words, fontSize: fontSize, weight: weight) else {
            // ✅ El fallo también se cachea (array vacío) para no remedir en cada render.
            cache.setObject([] as NSArray, forKey: key)
            return nil
        }

        cache.setObject(measured as NSArray, forKey: key)
        return measured
    }

    /// ✅ Se recorre el texto con un cursor comprobando que cada palabra APARECE
    /// ahí, en orden. Así se aceptan los dos espaciados reales del TTML (palabras
    /// separadas por espacios y SÍLABAS pegadas: `<span>Te-</span><span>te-</span>`)
    /// e incluso mezclas de ambos. Si una palabra no cuadra, no se devuelve nada:
    /// el karaoke por palabra solo se pinta cuando el reparto es demostrable.
    ///
    /// ✅ La fracción de cada palabra se mide sobre el PREFIJO REAL del texto (no
    /// sobre una reconstrucción), así el ancho incluye exactamente los mismos
    /// espacios y el mismo kern que el texto que SwiftUI dibuja.
    private static func measure(
        text: String,
        words: [LyricWordToken],
        fontSize: CGFloat,
        weight: UIFont.Weight
    ) -> [Double]? {
        let font = UIFont.systemFont(ofSize: fontSize, weight: weight)
        let total = (text as NSString).size(withAttributes: [.font: font]).width
        guard total > 0 else { return nil }

        var fractions: [Double] = []
        fractions.reserveCapacity(words.count)
        var cursor = text.startIndex

        for word in words {
            // ✅ Los espacios entre palabras se saltan (el separador puede ser " "
            // o nada, según cómo viniera el propio archivo).
            while cursor < text.endIndex, text[cursor].isWhitespace {
                cursor = text.index(after: cursor)
            }
            guard text[cursor...].hasPrefix(word.text) else { return nil }
            cursor = text.index(cursor, offsetBy: word.text.count)

            let prefix = String(text[text.startIndex..<cursor])
            let width = (prefix as NSString).size(withAttributes: [.font: font]).width
            fractions.append(min(max(width / total, 0), 1))
        }

        // ✅ Si sobra texto visible sin timing, el reparto no es demostrable.
        guard !text[cursor...].contains(where: { !$0.isWhitespace }) else { return nil }

        // ✅ El final de la última palabra ES el ancho completo de la fila: con el
        // redondeo de la medición, deja el barrido cerrado al 100%.
        fractions[fractions.count - 1] = 1
        return fractions
    }
}

// MARK: - Reparto EXACTO de los timings de palabra entre los trozos medidos
/// ✅ El troceo por anchura parte la fila en trozos, y los timings de palabra
/// tienen que viajar con su trozo: si no, el karaoke se desalinearía.
/// ✅ El reparto solo se acepta cuando es DEMOSTRABLE: los textos de las palabras
/// (unidos con el mismo separador con el que el modelo construyó la fila) tienen
/// que reproducir EXACTAMENTE el texto de cada trozo. Cuando no cuadra se
/// devuelve nil y esos trozos usan el relleno lineal: preferimos un karaoke por
/// fila correcto a uno por palabra desalineado.
private enum LyricWordAligner {
    static func split(words: [LyricWordToken], parts: [String]) -> [[LyricWordToken]]? {
        guard !words.isEmpty, parts.count > 1 else { return nil }

        for separator in [" ", ""] {
            if let assigned = assign(words: words, parts: parts, separator: separator) {
                return assigned
            }
        }
        return nil
    }

    private static func assign(
        words: [LyricWordToken],
        parts: [String],
        separator: String
    ) -> [[LyricWordToken]]? {
        var result: [[LyricWordToken]] = []
        result.reserveCapacity(parts.count)
        var index = 0

        for part in parts {
            var chunk: [LyricWordToken] = []
            var consumed = ""

            while index < words.count {
                let candidate = chunk.isEmpty
                    ? words[index].text
                    : consumed + separator + words[index].text
                guard part.hasPrefix(candidate) else { break }
                consumed = candidate
                chunk.append(words[index])
                index += 1
            }

            // ✅ Exactitud: lo consumido tiene que ser TODO el trozo, no un prefijo.
            guard !chunk.isEmpty, consumed == part else { return nil }
            result.append(chunk)
        }

        return index == words.count ? result : nil
    }
}

// MARK: - Render bajo presión (grabación de pantalla / overlay del sistema)
/// ✅ Condiciones que NO dependen del reloj y que, aun así, cambian cómo se pinta
/// el karaoke. Van como VALOR (no leídas dentro de la fila) porque los diffs de
/// `.equatable()` solo comparan las propiedades de la vista: si no formaran parte
/// de la igualdad, la fila no se enteraría de que cambió la condición.
private struct LyricRenderState: Equatable {
    /// ✅ La escena está en primer plano. Con el Centro de Control encima (o
    /// cualquier overlay del sistema) iOS pone la app en `.inactive`.
    let isSceneActive: Bool
    /// ✅ Grabación de pantalla activa (`UIScreen.isCaptured`).
    let isCaptured: Bool

    /// ✅ ¿Se pinta el halo del karaoke (copia tintada + blur bajo la máscara)?
    var showsGlow: Bool {
        !(isCaptured && LyricCapturePolicy.dropsGlowWhileCaptured)
    }

    /// ✅ ¿Se aplica el desenfoque sutil de las líneas inactivas?
    var usesInactiveDepthBlur: Bool {
        !(isCaptured && LyricCapturePolicy.dropsInactiveBlurWhileCaptured)
    }
}

/// ✅ Política de render bajo captura, en constantes y en un solo sitio para
/// poder calibrarla sin rastrear cada punto de decisión.
private enum LyricCapturePolicy {
    /// ✅ 30 fps al grabar en lugar de 60.
    static let capturedFrameInterval: Double = 1.0 / 30.0

    /// ✅ Sin halo mientras se graba.
    /// ⚠️ Contrapartida CONSCIENTE: el vídeo queda sin el halo que SÍ se ve en
    /// pantalla (el síntoma "la grabación se ve distinta" se acepta aquí a cambio
    /// de fluidez). Si se prefiere que la grabación sea idéntica a la pantalla —el
    /// blur del halo se rasteriza una sola vez, no se repaga por frame—, basta
    /// con poner esto en `false`.
    static let dropsGlowWhileCaptured = true

    /// ✅ Sin desenfoque en las líneas inactivas mientras se graba.
    static let dropsInactiveBlurWhileCaptured = true

    /// ✅ Respiración de los puntos del interludio bajo captura. En `true` los
    /// puntos se quedan en el punto MEDIO del ciclo (0.7): un estado que se lee
    /// bien —ni apagado ni encendido— y que no añade NI UNA suscripción de frames
    /// mientras el codificador trabaja (el karaoke ya pide los suyos a 30 fps).
    /// Con `false` la respiración se mantiene, pero a `capturedFrameInterval`
    /// (30 fps alineados con el vsync): es la alternativa si en el vídeo se quiere
    /// el latido completo.
    static let dropsInstrumentalPulseWhileCaptured = true
}

/// ✅ Desenfoque de profundidad de las líneas que se alejan del foco, evitable:
/// `.blur(radius: 0)` seguiría creando la pasada fuera de pantalla, así que con
/// radio 0 (foco, fila vecina o grabación) se quita el modificador entero en vez
/// de anularlo.
private struct InactiveDepthBlur: ViewModifier {
    let radius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if radius > 0 {
            content.blur(radius: radius)
        } else {
            content
        }
    }
}

/// ✅ Detector de grabación de pantalla (`UIScreen.isCaptured`, iOS 11+), con el
/// MISMO patrón que `VisualizerFrameRate`: singleton `@MainActor` observado por la
/// vista. `capturedDidChangeNotification` avisa tanto al empezar como al terminar
/// de grabar, así que el karaoke pasa a 30 fps durante la grabación y vuelve a 60
/// al parar, sin intervención del usuario.
@MainActor
final class LyricCaptureMonitor: ObservableObject {
    static let shared = LyricCaptureMonitor()

    @Published private(set) var isCaptured: Bool = UIScreen.main.isCaptured

    private init() {
        // ✅ `object: nil`: el aviso es de la pantalla, no de una pantalla
        // concreta, así que no se depende de la instancia al registrarlo.
        NotificationCenter.default.addObserver(
            forName: UIScreen.capturedDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isCaptured = UIScreen.main.isCaptured
            }
        }
    }
}

// MARK: - Preview
#if DEBUG
struct LyricsView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // ✅ Sin hueco: primera línea a 1 s (ningún indicador de gap).
            let sinIntro = LyricsViewModel()
            sinIntro.parseLyrics("""
            [00:01.00]Primera línea de prueba
            [00:05.50]Segunda línea de prueba
            [00:10.00]Tercera línea de prueba
            """)
            LyricsView(song: nil, viewModel: sinIntro)

            // ✅ Intro instrumental largo (primera línea a los 9 s): el indicador
            // debe colgar de la PRIMERA línea —la que el scroll centra mientras no
            // hay línea activa— desde el segundo 0 y apagarse al empezar la letra.
            // En preview estática (sin reproducción) los puntos salen en reposo
            // (0.7): es justo lo que se puede validar sin dispositivo, la
            // alineación con la columna del texto y el aire respecto de la línea.
            let conIntro = LyricsViewModel()
            conIntro.parseLyrics("""
            [00:09.00]Primera línea tras el intro
            [00:14.00]Segunda línea de prueba
            [00:18.00]Tercera línea de prueba
            """)
            LyricsView(song: nil, viewModel: conIntro)
        }
    }
}
#endif
