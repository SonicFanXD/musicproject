import Foundation

// MARK: - Timing de una palabra (TTML / LRC híbrido)
// ✅ La UI SÍ hace karaoke por palabra: cada token trae su ventana temporal y
//    el relleno de la línea avanza palabra a palabra con esos timings.
struct LyricWordToken: Equatable {
    let text: String
    let startMs: Int
    let endMs: Int
    /// ✅ Fila VISUAL a la que pertenece la palabra dentro de la línea lógica.
    /// TTML marca los saltos duros con `<br/>`; 0 en formatos sin filas.
    let rowIndex: Int
    /// ✅ Voz de FONDO (`ttm:role="x-bg"` del TTML de Apple Music): se pinta más
    /// pequeña y más tenue que la voz principal, como en la app de Apple.
    let isBackground: Bool

    init(text: String, startMs: Int, endMs: Int, rowIndex: Int = 0, isBackground: Bool = false) {
        self.text = text
        self.startMs = startMs
        self.endMs = endMs
        self.rowIndex = rowIndex
        self.isBackground = isBackground
    }
}

// MARK: - Fila visual de una línea
/// ✅ Una línea lógica puede ocupar VARIAS filas visuales (Apple Music usa
/// `<br/>` para partir un verso largo). Cada fila lleva su PROPIA ventana
/// temporal, de modo que el relleno progresivo avanza fila a fila (de arriba
/// abajo) en lugar de iluminar todas las filas a la vez.
struct LyricVisualRow: Equatable {
    let text: String
    let startMs: Int
    let endMs: Int
    /// ✅ Timings de las palabras de ESTA fila (vacío si el formato no los trae o
    /// si el troceo por medición no pudo repartirlos con exactitud). Con ellos el
    /// relleno avanza palabra por palabra, que es el karaoke de Apple Music; sin
    /// ellos se conserva el reparto proporcional dentro de la ventana de la fila.
    let words: [LyricWordToken]

    init(text: String, startMs: Int, endMs: Int, words: [LyricWordToken] = []) {
        self.text = text
        self.startMs = startMs
        self.endMs = endMs
        self.words = words
    }
}

// MARK: - Modelo de datos para lyrics línea por línea
// ✅ Diseño optimizado para iPhone 8 Plus (A11, 3GB RAM, iOS 16.x)
// - ID estable (Int) para evitar recreación de Swift.Identifiable
// - Timestamps en milisegundos para precisión absoluta
// - Estructura simple para minimizar allocations en runtime
struct LyricsLine: Identifiable, Equatable {
    let id: Int          // Índice estable, NUNCA UUID
    let text: String
    let startMs: Int
    let endMs: Int
    /// ✅ Timings por palabra (TTML / LRC híbrido). Vacío en LRC clásico.
    let words: [LyricWordToken]
    /// ✅ Texto listo para render, calculado UNA vez en el init.
    /// Antes `cleanText` ejecutaba 3 regex en CADA acceso y el wipe lo lee en
    /// cada frame (60/s por línea activa) → esto elimina ese coste del render.
    let displayText: String
    /// ✅ Filas visuales de la línea (siempre ≥ 1), con su ventana temporal.
    /// Una línea de una sola fila contiene exactamente [startMs, endMs], así que
    /// el wipe se comporta igual que antes de existir este campo.
    let visualRows: [LyricVisualRow]

    init(id: Int, text: String, startMs: Int, endMs: Int, words: [LyricWordToken] = []) {
        self.id = id
        self.text = text
        self.startMs = startMs
        self.endMs = endMs
        self.words = words

        let cleaned = LyricsLine.cleaned(text)
        self.displayText = cleaned
        self.visualRows = LyricsLine.buildRows(cleaned, startMs: startMs, endMs: endMs, words: words)
    }

    /// ✅ Texto completo de la línea (sin timestamps de palabra).
    /// El parser de formato híbrido eliminará los timestamps <mm:ss.xxx>
    var cleanText: String { displayText }

    /// Limpieza única del texto crudo (se aplica en el init, no en el render).
    static func cleaned(_ text: String) -> String {
        text.replacingOccurrences(of: "<[0-9:.]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// ✅ Recorta los timings de palabra al hueco REAL de su fila visual.
    /// El fin de la última palabra de un `<p>` TTML suele cerrarse con el fin de
    /// TODA la línea: sin este recorte, la fila de arriba de un verso con
    /// `<br/>` seguiría iluminándose mientras suena la de abajo.
    /// Los inicios se fuerzan monótonos porque el karaoke solo avanza de izquierda
    /// a derecha: una palabra con timing solapado (armonías de fondo que entran
    /// antes que la voz principal) no debe retroceder el borde del relleno.
    static func clampedWords(_ words: [LyricWordToken], startMs: Int, endMs: Int) -> [LyricWordToken] {
        guard !words.isEmpty, endMs > startMs else { return [] }

        var result: [LyricWordToken] = []
        result.reserveCapacity(words.count)
        var floorMs = startMs

        for word in words {
            let wordStart = min(max(word.startMs, floorMs), endMs)
            let wordEnd = min(max(word.endMs, wordStart), endMs)
            result.append(LyricWordToken(
                text: word.text,
                startMs: wordStart,
                endMs: wordEnd,
                rowIndex: word.rowIndex,
                isBackground: word.isBackground
            ))
            floorMs = max(floorMs, wordStart)
        }

        return result
    }

    // MARK: - Filas visuales
    /// Construye las filas visuales y su ventana temporal (se calcula UNA sola
    /// vez, en el init: cero coste por frame).
    ///
    /// · Filas CON timings de palabra: cada fila usa el rango REAL de sus
    ///   palabras. Si la fila de abajo empieza a los 10.8s no se rellena antes:
    ///   el silencio se respeta y la fila de arriba permanece completa.
    /// · Sin timings (LRC clásico o TTML sin `<span>`): el rango de la línea se
    ///   reparte de forma proporcional al nº de caracteres de cada fila, así una
    ///   fila única conserva exactamente [startMs, endMs].
    static func buildRows(
        _ text: String,
        startMs: Int,
        endMs: Int,
        words: [LyricWordToken]
    ) -> [LyricVisualRow] {
        let safeEndMs = max(endMs, startMs + 1)
        let rowTexts = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // ✅ Caso normal (una sola fila): ventana de la línea.
        guard rowTexts.count > 1 else {
            let rowText = rowTexts.first ?? text
            // ✅ Con timings por palabra, la fila se rellena de la PRIMERA a la
            // ÚLTIMA palabra: un intro instrumental no ilumina la letra antes de
            // que suene, y el hueco posterior no la sigue iluminando.
            if let firstWord = words.first,
               let lastWord = words.last,
               lastWord.endMs > firstWord.startMs {
                let rowStartMs = firstWord.startMs
                let rowEndMs = lastWord.endMs
                return [LyricVisualRow(
                    text: rowText,
                    startMs: rowStartMs,
                    endMs: rowEndMs,
                    words: clampedWords(words, startMs: rowStartMs, endMs: rowEndMs)
                )]
            }
            return [LyricVisualRow(
                text: rowText,
                startMs: startMs,
                endMs: safeEndMs,
                words: clampedWords(words, startMs: startMs, endMs: safeEndMs)
            )]
        }

        let totalCharacters = max(1, rowTexts.reduce(0) { $0 + $1.count })
        let lineSpan = Double(safeEndMs - startMs)

        var rows: [LyricVisualRow] = []
        rows.reserveCapacity(rowTexts.count)
        var charactersBefore = 0

        for (index, rowText) in rowTexts.enumerated() {
            let rowWords = words.filter { $0.rowIndex == index }
            let rowStartMs: Int
            let rowEndMs: Int

            if let firstWordMs = rowWords.first?.startMs,
               let lastWordMs = rowWords.last?.endMs,
               lastWordMs > firstWordMs {
                rowStartMs = firstWordMs
                rowEndMs = lastWordMs
            } else {
                // ✅ Reparto proporcional al texto de cada fila.
                let before = Double(charactersBefore) / Double(totalCharacters)
                let after = Double(charactersBefore + rowText.count) / Double(totalCharacters)
                rowStartMs = startMs + Int((lineSpan * before).rounded())
                rowEndMs = startMs + Int((lineSpan * after).rounded())
            }

            rows.append(LyricVisualRow(
                text: rowText,
                startMs: rowStartMs,
                endMs: max(rowEndMs, rowStartMs + 1),
                // ✅ Se guardan SIN recortar: las ventanas de las filas todavía
                // pueden moverse en el reajuste final de aquí abajo.
                words: rowWords
            ))
            charactersBefore += rowText.count
        }

        // ✅ Reajuste final: ninguna fila puede invadir a la siguiente. El
        // timing de la última palabra de una fila suele cerrarse con el fin de
        // TODA la línea, y eso solaparía las filas de abajo.
        for index in 0..<(rows.count - 1) where rows[index].endMs > rows[index + 1].startMs {
            let current = rows[index]
            rows[index] = LyricVisualRow(
                text: current.text,
                startMs: current.startMs,
                endMs: max(rows[index + 1].startMs, current.startMs + 1),
                words: current.words
            )
        }

        // ✅ El recorte de los timings de palabra se hace AL FINAL, cuando las
        // ventanas de las filas ya son definitivas (el bucle de arriba acaba de
        // recortar el fin de la fila justo donde terminaba su última palabra).
        return rows.map { row in
            LyricVisualRow(
                text: row.text,
                startMs: row.startMs,
                endMs: row.endMs,
                words: clampedWords(row.words, startMs: row.startMs, endMs: row.endMs)
            )
        }
    }
}
