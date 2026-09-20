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
// ✅ Sin temporizadores propios (ni en la vista ni en el modelo).
// ✅ Auto-scroll suave con ScrollViewReader (solo cuando cambia la línea activa)
// ✅ Render 100% por código, sin assets
struct LyricsView: View {
    let song: Song?
    @ObservedObject var viewModel: LyricsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var scrollTarget: Int? = nil

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
        }
        // ✅ iOS 16 onChange clásico: scroll solo cuando cambia la línea activa
        .onChange(of: viewModel.activeID) { newID in
            scrollTarget = newID
        }
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
        ScrollViewReader { proxy in
            ScrollView {
                lyricsStack
            }
            // ✅ iOS 16 onChange clásico: scroll suave solo cuando cambia el target
            .onChange(of: scrollTarget) { target in
                scrollToActiveLine(target, proxy: proxy)
            }
        }
    }

    /// ✅ Relleno de 40% de pantalla antes y después: fuerza que la línea activa
    /// quede centrada de forma geométrica (no depende del tamaño de la lista).
    private var lyricsStack: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            Color.clear.frame(height: centeringInset)

            ForEach(viewModel.lyricsLines) { line in
                lyricLineView(line: line)
                    .id(line.id)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        seekToLine(line)
                    }
            }

            Color.clear.frame(height: centeringInset)
        }
        .padding(.horizontal, 24)
    }

    /// ✅ Scroll centrado y suave (0.25s easeInOut, el estándar de Apple Music)
    /// al cambiar de línea activa. Cuanto más corto es el solape entre la
    /// animación del scroll y el wipe a 60 fps de la línea entrante, menos
    /// tirones se ven en la transición.
    private func scrollToActiveLine(_ target: Int?, proxy: ScrollViewProxy) {
        guard let target = target else { return }

        withAnimation(.easeInOut(duration: 0.25)) {
            proxy.scrollTo(target, anchor: .center)
        }
    }

    // MARK: - Línea individual
    /// ✅ El scroll se hace en DOS fases (activeID → scrollTarget → scrollTo) a
    /// propósito: así la primera línea se centra también cuando el ScrollView
    /// nace en el mismo ciclo en que el parser publica `activeID` (con un solo
    /// onChange dentro del ScrollViewReader ese primer centrado se perdería).
    private func lyricLineView(line: LyricsLine) -> some View {
        LyricLineView(
            line: line,
            isActive: viewModel.activeID == line.id,
            isPlaying: viewModel.isPlaying,
            viewModel: viewModel
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
        } else {
            viewModel.clearLyrics()
        }
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
    }

    private var fontSize: CGFloat {
        isActive ? 24 : 18
    }

    private var fontWeight: Font.Weight {
        isActive ? .bold : .regular
    }

    var body: some View {
        Group {
            if isActive {
                activeLine
            } else {
                dimmedRows
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        // ✅ "Pop" de escala al cambiar de línea activa
        .scaleEffect(isActive ? 1.0 : 0.985)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isActive)
    }

    // MARK: Línea activa (relleno animado, fila a fila)
    /// ✅ Con reproducción activa se piden frames a 60 Hz; en pausa se dibuja el
    /// estado congelado una sola vez (sin gastar GPU/batería).
    @ViewBuilder
    private var activeLine: some View {
        if isPlaying {
            TimelineView(.animation) { _ in
                activeRows
            }
        } else {
            activeRows
        }
    }

    /// ✅ UN solo TimelineView para la línea completa: cada fila visual lleva su
    /// propia máscara y su propia ventana temporal, pero solo hay UNA
    /// suscripción de frames por línea activa (nunca una por fila).
    private var activeRows: some View {
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            ForEach(line.visualRows.indices, id: \.self) { index in
                LyricFillText(
                    text: line.visualRows[index].text,
                    fontSize: fontSize,
                    fontWeight: fontWeight,
                    progress: easedProgress(forRowIndex: index)
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
    private var dimmedRows: some View {
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            ForEach(line.visualRows.indices, id: \.self) { index in
                Text(line.visualRows[index].text)
                    .font(.system(size: fontSize, weight: fontWeight))
                    .foregroundStyle(Color.white.opacity(0.35))
            }
        }
    }

    /// ✅ Smoothstep (t·t·(3−2t)) POR FILA: cada fila se rellena en su propio
    /// rango, así la fila de arriba se completa antes de que empiece la de abajo.
    private func easedProgress(forRowIndex index: Int) -> Double {
        let rows = line.visualRows
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
            .foregroundStyle(Color.white.opacity(0.35))
    }

    private var brightLayer: some View {
        Text(text)
            .font(.system(size: fontSize, weight: fontWeight))
            .foregroundStyle(Color.white)
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
