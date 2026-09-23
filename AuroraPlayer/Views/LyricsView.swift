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
// ✅ Colores ADAPTATIVOS (`.primary`): la app no fuerza modo oscuro, así que el
//    texto blanco fijo era invisible sobre el fondo claro en modo claro.
// ✅ Render 100% por código, sin assets
struct LyricsView: View {
    let song: Song?
    @ObservedObject var viewModel: LyricsViewModel
    // ✅ Observado para que los textos se re-rendericen al cambiar de idioma en vivo.
    @ObservedObject private var localization = Localization.shared
    @Environment(\.dismiss) private var dismiss

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
    private static let horizontalPadding: CGFloat = 24

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
            LyricsArtworkBackground(artwork: song?.artwork, accentToken: AppTheme.accentUIColor)
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
        return LazyVStack(alignment: .leading, spacing: 8) {
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

        if hasDoneInitialScroll {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
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
            glowColor: glowColor
        )
        // ✅ Solo las filas cuyo contenido ha cambiado vuelven a evaluar su body:
        // al cambiar de línea activa (o al hacer scroll) se evita re-evaluar todo
        // el LazyVStack visible.
        .equatable()
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

// MARK: - Fondo de carátula difuminada
/// ✅ Vista PROPIA y `Equatable`: el body de `LyricsView` se re-evalúa en cada
/// cambio de línea activa; con `.equatable()` esta sub-vista no vuelve a componer
/// el blur de pantalla completa si la carátula y el acento no han cambiado (era
/// el candidato a los tirones al cambiar de verso).
private struct LyricsArtworkBackground: View, Equatable {
    let artwork: UIImage?
    /// ✅ Solo como TOKEN de comparación: el color se pinta con `AppTheme.accent`
    /// para no alterar el tono con conversiones de espacio de color.
    let accentToken: UIColor

    static func == (lhs: LyricsArtworkBackground, rhs: LyricsArtworkBackground) -> Bool {
        guard lhs.accentToken == rhs.accentToken else { return false }
        if let lhsArtwork = lhs.artwork, let rhsArtwork = rhs.artwork {
            return lhsArtwork === rhsArtwork
        }
        return lhs.artwork == nil && rhs.artwork == nil
    }

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .blur(radius: 60)
                        .opacity(0.4)
                        .overlay(Color(UIColor.systemBackground).opacity(0.72))
                } else {
                    LinearGradient(
                        colors: [AppTheme.accent.opacity(0.12), Color(UIColor.systemBackground)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
        }
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
                dimmedRows(rows)
                    // ✅ Profundidad MUY sutil (0.5pt), y SOLO en las líneas
                    // inactivas: la activa es la que pide frames a 60 Hz y no
                    // debe pagar ninguna pasada de blur. Si en el iPhone 8 Plus
                    // no convence, basta con borrar esta línea.
                    .blur(radius: 0.5)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        // ✅ "Pop" premium al cambiar de línea: las inactivas "respiran" algo
        // más pequeñas (0.96) y la activa recupera la escala completa.
        .scaleEffect(isActive ? 1.0 : 0.96)
        .animation(lineActivation, value: isActive)
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
        if isPlaying {
            TimelineView(.animation) { _ in
                activeRows(rows)
            }
        } else {
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
                    contentOpacity: rows[index].isBackground ? LyricBackgroundVoice.opacity : 1
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
    private func dimmedRows(_ rows: [RenderRow]) -> some View {
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            ForEach(rows.indices, id: \.self) { index in
                Text(rows[index].text)
                    .font(.system(size: rows[index].fontSize, weight: fontWeight))
                    .foregroundStyle(Color.primary.opacity(LyricDim.inactiveOpacity))
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

    private var brightLayers: some View {
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

// MARK: - Preview
#if DEBUG
struct LyricsView_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = LyricsViewModel()
        viewModel.parseLyrics("""
        [00:01.00]Primera línea de prueba
        [00:05.50]Segunda línea de prueba
        [00:10.00]Tercera línea de prueba
        """)
        
        return LyricsView(song: nil, viewModel: viewModel)
    }
}
#endif
