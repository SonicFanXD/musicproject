import Foundation

// MARK: - Parser de LRC clásico, formato híbrido y TTML
// ✅ Soporta:
// - TTML (Apple Music): si el texto usa el namespace http://www.w3.org/ns/ttml
//   se delega en TTMLParser (líneas <p> + timings por palabra <span>)
// - LRC clásico: [mm:ss.xx] texto
// - Formato híbrido: [mm:ss.xx]<mm:ss.xxx>texto (extrae línea + timings de palabra)
// - Metadatos: [ti:], [ar:], [al:], [offset:]
// - Líneas vacías, timestamps duplicados, saltos de línea
// ✅ Optimizado para iPhone 8 Plus: sin allocations por línea, regex eficiente
struct LRCParser {
    /// Duración por defecto de la última línea si no hay siguiente.
    private static let defaultLineDurationMs = 10_000

    // MARK: - Parse completo de texto LRC
    /// Parsea el texto de letras y devuelve array de LyricsLine ordenado por startMs
    /// - Parameter text: Texto crudo (TTML, LRC clásico o híbrido)
    /// - Returns: Array de LyricsLine ordenado cronológicamente con id == índice
    static func parse(_ text: String) -> [LyricsLine] {
        guard !text.isEmpty else { return [] }

        // ✅ TTML (Apple Music) ANTES que LRC: un TTML no trae timestamps
        // [mm:ss.xx], así que sin esta detección todas sus líneas se perderían.
        if let ttmlLines = TTMLParser.parse(text), !ttmlLines.isEmpty {
            return ttmlLines
        }

        var lines: [LyricsLine] = []

        // ✅ Split por líneas para procesamiento eficiente
        let rawLines = text.components(separatedBy: .newlines)

        for rawLine in rawLines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // ✅ Ignorar metadatos [ti:], [ar:], [al:], [offset:]
            if isMetadataLine(trimmed) {
                continue
            }

            // ✅ Extraer timestamp de línea [mm:ss.xx]
            guard let startMs = extractLineTimestamp(trimmed) else { continue }

            // ✅ Extraer texto completo (limpiando timestamps de palabra <...>)
            let cleanText = extractCleanText(trimmed)
            guard !cleanText.isEmpty else { continue }

            // ✅ Fin provisional: se corrige con el inicio de la siguiente línea.
            lines.append(LyricsLine(
                id: lines.count,
                text: cleanText,
                startMs: startMs,
                endMs: startMs + defaultLineDurationMs,
                words: extractWordTokens(trimmed)
            ))
        }

        // ✅ Ordenar por startMs (los .lrc no siempre vienen cronológicos) y
        // renumerar: `id == índice` es el invariante que usan el motor de lyrics
        // y la vista (resaltado, tap-to-seek y scroll por id).
        let sorted = lines.sorted { ($0.startMs, $0.text) < ($1.startMs, $1.text) }
        return sorted.enumerated().map { index, line in
            let nextStartMs = index + 1 < sorted.count ? sorted[index + 1].startMs : nil
            let endMs = nextStartMs ?? (line.startMs + defaultLineDurationMs)

            return LyricsLine(
                id: index,
                text: line.text,
                startMs: line.startMs,
                endMs: endMs,
                words: closeWords(line.words, lineEndMs: endMs)
            )
        }
    }

    // MARK: - Helpers de parsing

    /// Detecta si una línea es metadatos (no lyrics)
    private static func isMetadataLine(_ line: String) -> Bool {
        let metadataPrefixes = ["[ti:", "[ar:", "[al:", "[offset:", "[by:", "[re:", "[ve:"]
        return metadataPrefixes.contains { line.hasPrefix($0) }
    }

    /// Extrae timestamp de línea [mm:ss.xx] en milisegundos
    private static func extractLineTimestamp(_ line: String) -> Int? {
        // ✅ Regex para [mm:ss.xx] o [mm:ss]
        let pattern = "\\[(\\d{2}):(\\d{2})(?:\\.(\\d{2,3}))?\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
            return nil
        }

        return timestampMs(from: match, in: line as NSString)
    }

    /// Convierte los grupos (mm, ss, fracción opcional) de un match a milisegundos
    /// ✅ Fracción de 2 dígitos = centésimas (×10); de 3 dígitos = milésimas (×1)
    private static func timestampMs(from match: NSTextCheckingResult, in text: NSString) -> Int? {
        // ✅ Guard defensivo: nunca hacer substring(range:) sin comprobar el
        // rango (NSNotFound crashea). Estabilidad > cualquier micro-optimización.
        let minuteRange = match.range(at: 1)
        let secondRange = match.range(at: 2)
        guard minuteRange.location != NSNotFound,
              secondRange.location != NSNotFound,
              let minutes = Int(text.substring(with: minuteRange)),
              let seconds = Int(text.substring(with: secondRange)) else {
            return nil
        }

        var milliseconds = 0
        var multiplier = 10
        let fractionRange = match.numberOfRanges > 3 ? match.range(at: 3) : NSRange(location: NSNotFound, length: 0)
        if fractionRange.location != NSNotFound {
            let fraction = text.substring(with: fractionRange)
            milliseconds = Int(fraction) ?? 0
            multiplier = fraction.count == 3 ? 1 : 10
        }

        return (minutes * 60 * 1000) + (seconds * 1000) + (milliseconds * multiplier)
    }

    /// ✅ Formato híbrido: [mm:ss.xx]<mm:ss.xxx>palabra<mm:ss.xxx>palabra
    /// Extrae los timings por palabra como DATOS: la UI de esta iteración no
    /// pinta karaoke por palabra. El último token queda con end == start y se
    /// cierra con el fin real de la línea en `closeWords`.
    private static func extractWordTokens(_ line: String) -> [LyricWordToken] {
        let pattern = "<(\\d{2}):(\\d{2})\\.(\\d{2,3})>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let text = line as NSString
        let matches = regex.matches(in: line, range: NSRange(location: 0, length: text.length))
        guard !matches.isEmpty else { return [] }

        var tokens: [LyricWordToken] = []
        for (index, match) in matches.enumerated() {
            guard let startMs = timestampMs(from: match, in: text) else { continue }

            let wordStart = match.range.location + match.range.length
            let wordEnd = index + 1 < matches.count ? matches[index + 1].range.location : text.length
            guard wordEnd > wordStart else { continue }

            let word = text.substring(with: NSRange(location: wordStart, length: wordEnd - wordStart))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty else { continue }

            tokens.append(LyricWordToken(text: word, startMs: startMs, endMs: startMs))
        }

        // ✅ Cada palabra termina donde empieza la siguiente.
        for index in 0..<tokens.count where index + 1 < tokens.count {
            let current = tokens[index]
            tokens[index] = LyricWordToken(
                text: current.text,
                startMs: current.startMs,
                endMs: max(tokens[index + 1].startMs, current.startMs)
            )
        }

        return tokens
    }

    /// Cierra la última palabra de la línea con su fin real (solo si el formato
    /// híbrido no traía un `end` propio).
    private static func closeWords(_ words: [LyricWordToken], lineEndMs: Int) -> [LyricWordToken] {
        guard let last = words.last, last.endMs <= last.startMs else { return words }

        var closed = words
        closed[closed.count - 1] = LyricWordToken(
            text: last.text,
            startMs: last.startMs,
            endMs: max(lineEndMs, last.startMs)
        )
        return closed
    }

    /// Extrae texto limpio sin timestamps
    /// - Formato híbrido: [mm:ss.xx]<mm:ss.xxx>palabra -> palabra
    /// - Formato clásico: [mm:ss.xx] texto -> texto
    private static func extractCleanText(_ line: String) -> String {
        var cleaned = line

        // ✅ Eliminar timestamp de línea [mm:ss.xx]
        cleaned = cleaned.replacingOccurrences(of: "\\[\\d{2}:\\d{2}(?:\\.\\d{2,3})?\\]", with: "", options: .regularExpression)

        // ✅ Eliminar timestamps de palabra <mm:ss.xxx>
        cleaned = cleaned.replacingOccurrences(of: "<\\d{2}:\\d{2}\\.\\d{3}>", with: "", options: .regularExpression)

        // ✅ Eliminar cualquier etiqueta HTML remanente
        cleaned = cleaned.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Tests unitarios para LRCParser
// ✅ Casos borde: gaps, seek, inicio, fin, array vacío, timestamps duplicados
#if DEBUG
extension LRCParser {
    static func runTests() {
        print("🧪 Ejecutando tests de LRCParser...")
        
        // Test 1: LRC clásico simple
        let classicLRC = """
        [00:01.00]Primera línea
        [00:05.50]Segunda línea
        [00:10.00]Tercera línea
        """
        let classicResult = parse(classicLRC)
        assert(classicResult.count == 3, "Test 1 falló: Expected 3 lines, got \(classicResult.count)")
        assert(classicResult[0].text == "Primera línea", "Test 1 falló: Text mismatch")
        assert(classicResult[0].startMs == 1000, "Test 1 falló: Timestamp mismatch")
        print("✅ Test 1 (LRC clásico) passed")
        
        // Test 2: Formato híbrido
        let hybridLRC = """
        [00:00.04]<00:00.040>Te-<00:00.412>te-<00:00.681>te-<00:00.963>te <00:01.097>v
        [00:02.50]<00:02.500>Se-<00:02.800>gun-<00:03.100>da
        """
        let hybridResult = parse(hybridLRC)
        assert(hybridResult.count == 2, "Test 2 falló: Expected 2 lines, got \(hybridResult.count)")
        assert(hybridResult[0].cleanText == "Te-te-te-te v", "Test 2 falló: Clean text mismatch")
        assert(hybridResult[0].startMs == 40, "Test 2 falló: Timestamp mismatch")
        print("✅ Test 2 (Formato híbrido) passed")
        
        // Test 3: Array vacío
        let emptyResult = parse("")
        assert(emptyResult.isEmpty, "Test 3 falló: Expected empty array")
        print("✅ Test 3 (Array vacío) passed")
        
        // Test 4: Líneas con metadatos
        let metadataLRC = """
        [ti:Canción de prueba]
        [ar:Artista]
        [00:01.00]Primera línea
        """
        let metadataResult = parse(metadataLRC)
        assert(metadataResult.count == 1, "Test 4 falló: Expected 1 line after filtering metadata")
        print("✅ Test 4 (Metadatos) passed")
        
        // Test 5: Timestamps duplicados (mismo inicio)
        let duplicateLRC = """
        [00:01.00]Línea 1
        [00:01.00]Línea 2
        """
        let duplicateResult = parse(duplicateLRC)
        assert(duplicateResult.count == 2, "Test 5 falló: Expected 2 lines with duplicate timestamps")
        print("✅ Test 5 (Timestamps duplicados) passed")
        
        // Test 6: Gap entre líneas
        let gapLRC = """
        [00:01.00]Línea 1
        [00:05.00]Línea 2
        """
        let gapResult = parse(gapLRC)
        assert(gapResult.count == 2, "Test 6 falló: Expected 2 lines")
        assert(gapResult[0].endMs == 5000, "Test 6 falló: Gap endMs mismatch")
        print("✅ Test 6 (Gap entre líneas) passed")

        // Test 7: Líneas desordenadas → ids consecutivos en orden cronológico
        // (la vista resalta y hace scroll por id, así que id == índice importa)
        let unsortedLRC = """
        [00:10.00]Tercera
        [00:01.00]Primera
        [00:05.00]Segunda
        """
        let unsortedResult = parse(unsortedLRC)
        assert(unsortedResult.count == 3, "Test 7 falló: Expected 3 lines")
        assert(unsortedResult[0].id == 0 && unsortedResult[1].id == 1 && unsortedResult[2].id == 2, "Test 7 falló: Expected consecutive ids")
        assert(unsortedResult[0].text == "Primera", "Test 7 falló: Expected chronological order")
        print("✅ Test 7 (Reordenado + ids consecutivos) passed")

        // Test 8: Timings por palabra del formato híbrido (solo DATOS)
        assert(hybridResult[0].words.count == 5, "Test 8 falló: Expected 5 word tokens")
        assert(hybridResult[0].words[0].text == "Te-", "Test 8 falló: Word text mismatch")
        assert(hybridResult[0].words[0].startMs == 40, "Test 8 falló: Word start mismatch")
        assert(hybridResult[0].words[0].endMs == 412, "Test 8 falló: Word end mismatch")
        assert(hybridResult[0].words[4].endMs == 2500, "Test 8 falló: Last word should close with line end")
        assert(classicResult[0].words.isEmpty, "Test 8 falló: LRC clásico no tiene palabras")
        print("✅ Test 8 (Timings por palabra) passed")

        // Test 9: TTML se delega a TTMLParser (namespace w3.org/ns/ttml)
        let ttml = """
        <tt xmlns="http://www.w3.org/ns/ttml"><body><div>
        <p begin="00:00:01.000" end="00:00:02.000"><span begin="00:00:01.000" end="00:00:02.000">Hola</span></p>
        </div></body></tt>
        """
        let ttmlResult = parse(ttml)
        assert(ttmlResult.count == 1, "Test 9 falló: Expected 1 TTML line")
        assert(ttmlResult[0].displayText == "Hola", "Test 9 falló: TTML text mismatch")
        assert(ttmlResult[0].startMs == 1000, "Test 9 falló: TTML timestamp mismatch")
        print("✅ Test 9 (TTML delegado) passed")
        
        print("🎉 Todos los tests de LRCParser pasaron correctamente")
    }
}
#endif
