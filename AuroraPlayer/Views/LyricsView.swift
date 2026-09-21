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
// ✅ Las filas que SwiftUI partiría por ANCHURA también se trocean (medición real
//    con la fuente activa): el wipe avanza fila a fila, nunca en paralelo.
// ✅ Sin temporizadores propios (ni en la vista ni en el modelo).
// ✅ Auto-scroll suave con ScrollViewReader (solo cuando cambia la línea activa)
// ✅ Colores ADAPTATIVOS (`.primary`): la app no fuerza modo oscuro, así que el
//    texto blanco fijo era invisible sobre el fondo claro en modo claro.
// ✅ Render 100% por código, sin assets
struct LyricsView: View {
    let song: Song?
    @ObservedObject var viewModel: LyricsViewModel
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

    /// ✅ Centrado geométrico exacto: 40% de la pantalla de relleno arriba y
    /// abajo, de modo que la línea activa quede en el centro real de la vista.
    private var centeringInset: CGFloat {
        UIScreen.main.bounds.height * 0.4
    }

    var body: some View {
        ZStack {
            blurredArtworkBackground

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
    private func syncScrollToActiveLine() {
        hasDoneInitialScroll = false
        scrollRequest = nil
        guard let activeID = viewModel.activeID else { return }
        requestScroll(to: activeID)
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
            .accessibilityLabel("Cerrar")

            Spacer()

            Text("Letras")
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
                    lyricsStack(contentWidth: geometry.size.width)
                }
                // ✅ iOS 16 onChange clásico: scroll suave solo cuando cambia el target
                .onChange(of: scrollRequest) { request in
                    scrollToActiveLine(request, proxy: proxy)
                }
            }
        }
    }

    /// ✅ Relleno de 40% de pantalla antes y después: fuerza que la línea activa
    /// quede centrada de forma geométrica (no depende del tamaño de la lista).
    private func lyricsStack(contentWidth: CGFloat) -> some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            Color.clear.frame(height: centeringInset)

            ForEach(viewModel.lyricsLines) { line in
                lyricLineView(line: line, contentWidth: contentWidth)
                    .id(line.id)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        seekToLine(line)
                    }
            }

            Color.clear.frame(height: centeringInset)
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
            availableWidth: max(0, contentWidth - Self.horizontalPadding * 2)
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

    // MARK: - Fondo difuminado
    private var blurredArtworkBackground: some View {
        GeometryReader { geometry in
            Group {
                if let artwork = song?.artwork {
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

    // MARK: - Vista vacía
    private var emptyLyricsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.5))

            Text("Esta canción no tiene letras")
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
    /// ✅ Cacheado por (texto + fuente + ancho) para no medir en cada render.
    private static let cache = NSCache<NSString, NSArray>()

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

// MARK: - Filas reales (lógicas + troceo por medición)
private enum LyricRowBuilder {
    /// ✅ Cada trozo hereda un sub-rango de la ventana de su fila lógica, en
    /// proporción al nº de caracteres (misma regla que el modelo cuando no hay
    /// timings por palabra), así las ventanas quedan encadenadas y el trozo N+1
    /// no empieza hasta que el N termina.
    static func rows(
        from logicalRows: [LyricVisualRow],
        fontSize: CGFloat,
        weight: UIFont.Weight,
        maxWidth: CGFloat
    ) -> [LyricVisualRow] {
        var result: [LyricVisualRow] = []
        result.reserveCapacity(logicalRows.count)

        for row in logicalRows {
            let parts = LyricRowSplitter.split(row.text, fontSize: fontSize, weight: weight, maxWidth: maxWidth)
            guard parts.count > 1 else {
                result.append(row)
                continue
            }

            let span = Double(max(row.endMs - row.startMs, 1))
            let totalCharacters = max(1, parts.reduce(0) { $0 + $1.count })
            var charactersBefore = 0

            for part in parts {
                let start = row.startMs + Int((span * Double(charactersBefore) / Double(totalCharacters)).rounded())
                let end = row.startMs + Int((span * Double(charactersBefore + part.count) / Double(totalCharacters)).rounded())
                result.append(LyricVisualRow(text: part, startMs: start, endMs: max(end, start + 1)))
                charactersBefore += part.count
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
    }

    private var fontSize: CGFloat {
        isActive ? 24 : 18
    }

    private var fontWeight: Font.Weight {
        isActive ? .bold : .regular
    }

    var body: some View {
        // ✅ Las filas REALES se calculan AQUÍ, fuera del TimelineView: el troceo
        // por medición se paga una sola vez por línea (y queda cacheado), nunca
        // por frame.
        let rows = displayedRows

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

    // MARK: Línea activa (relleno animado, fila a fila)
    /// ✅ Con reproducción activa se piden frames a 60 Hz; en pausa se dibuja el
    /// estado congelado una sola vez (sin gastar GPU/batería).
    @ViewBuilder
    private func activeLine(_ rows: [LyricVisualRow]) -> some View {
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
    private func activeRows(_ rows: [LyricVisualRow]) -> some View {
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            ForEach(rows.indices, id: \.self) { index in
                LyricFillText(
                    text: rows[index].text,
                    fontSize: fontSize,
                    fontWeight: fontWeight,
                    progress: easedProgress(rows: rows, index: index)
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
    private func dimmedRows(_ rows: [LyricVisualRow]) -> some View {
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            ForEach(rows.indices, id: \.self) { index in
                Text(rows[index].text)
                    .font(.system(size: fontSize, weight: fontWeight))
                    .foregroundStyle(Color.primary.opacity(0.35))
            }
        }
    }

    /// ✅ Smoothstep (t·t·(3−2t)) POR FILA: cada fila se rellena en su propio
    /// rango, así la fila de arriba se completa antes de que empiece la de abajo.
    private func easedProgress(rows: [LyricVisualRow], index: Int) -> Double {
        guard rows.indices.contains(index) else { return 0 }

        let raw = viewModel.fillProgress(
            forLineID: line.id,
            row: rows[index],
            isLastRow: index == rows.count - 1
        )
        return raw * raw * (3 - 2 * raw)
    }
}

// MARK: - Texto con relleno progresivo (dos capas + máscara)
// ✅ Sin blur ni capas extra: dos Text y una máscara rectangular por frame.
private struct LyricFillText: View, Equatable {
    let text: String
    let fontSize: CGFloat
    let fontWeight: Font.Weight
    let progress: Double

    var body: some View {
        ZStack(alignment: .leading) {
            dimmedLayer
            brightLayer.mask(alignment: .leading) { progressMask }
        }
    }

    private var dimmedLayer: some View {
        Text(text)
            .font(.system(size: fontSize, weight: fontWeight))
            .foregroundStyle(Color.primary.opacity(0.35))
    }

    private var brightLayer: some View {
        Text(text)
            .font(.system(size: fontSize, weight: fontWeight))
            .foregroundStyle(Color.primary)
    }

    /// ✅ Ancho de la máscara = ancho REAL del texto × progreso (0...1).
    private var progressMask: some View {
        GeometryReader { geometry in
            Rectangle()
                .frame(width: geometry.size.width * progress)
        }
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
