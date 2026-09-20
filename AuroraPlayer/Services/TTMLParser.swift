import Foundation

// MARK: - Parser de TTML (Apple Music)
// ✅ TTML = Timed Text Markup Language: el formato de letras sincronizadas de
//    Apple Music, con timings por línea (<p begin/end>) y por palabra (<span>).
// ✅ Solo se acepta si el documento usa el namespace oficial
//    http://www.w3.org/ns/ttml → nunca se confunde un LRC con un TTML.
// ✅ Las palabras se extraen como DATOS (`LyricWordToken`): la UI de esta
//    iteración NO hace karaoke por palabra (prohibido), así que no se pintan.
// ✅ Si algo falla se devuelve nil y el llamador sigue con LRCParser (fallback).
struct TTMLParser {
    static let namespace = "http://www.w3.org/ns/ttml"
    /// ✅ Marca INTERNA de los saltos duros (`<br/>`): XMLParser no emite nunca
    /// este carácter en el contenido, así que distingue un salto REAL (fila
    /// nueva) de la indentación del XML, que es whitespace normal y debe
    /// colapsarse. Sin esto, `<br/>` se convertía en un espacio y las dos filas
    /// visuales de un verso se fundían en una sola línea que envolvía por
    /// anchura → el relleno progresivo iluminaba ambas filas en paralelo.
    static let hardBreak: Character = "\u{0000}"
    /// Duración por defecto de la última línea si el TTML no trae `end`.
    private static let defaultLineDurationMs = 10_000

    // MARK: - Entrada
    /// Devuelve las líneas si `text` es un TTML válido; nil en cualquier otro caso.
    static func parse(_ text: String) -> [LyricsLine]? {
        guard text.range(of: "<tt", options: .caseInsensitive) != nil,
              text.contains(namespace) || text.range(of: "ttml", options: .caseInsensitive) != nil,
              let data = text.data(using: .utf8) else { return nil }

        let delegate = Delegate()
        let parser = XMLParser(data: data)
        // ✅ Con namespaces activados XMLParser resuelve el namespace real de
        // cada elemento (incluidos los heredados del <tt> raíz).
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        guard parser.parse(), delegate.usesTTMLNamespace, !delegate.entries.isEmpty else { return nil }
        return buildLines(delegate.entries)
    }

    // MARK: - Modelo intermedio
    struct Word {
        let beginMs: Int
        let endMs: Int?
        let text: String
        /// Fila visual dentro de la línea (0 si el verso no tiene `<br/>`).
        let rowIndex: Int
    }

    struct Line {
        let beginMs: Int
        let endMs: Int?
        let text: String
        let words: [Word]
    }

    // MARK: - Conversión a modelo de la app
    /// Ordena por tiempo y asigna ids consecutivos (id == índice, invariante que
    /// la vista y el motor de lyrics usan para resaltar/scroll).
    static func buildLines(_ entries: [Line]) -> [LyricsLine] {
        let sorted = entries.sorted { ($0.beginMs, $0.text) < ($1.beginMs, $1.text) }

        return sorted.enumerated().map { index, entry in
            let nextStartMs = index + 1 < sorted.count ? sorted[index + 1].beginMs : nil
            let explicitEndMs = entry.endMs ?? entry.words.last?.endMs
            let endMs = explicitEndMs ?? nextStartMs ?? (entry.beginMs + defaultLineDurationMs)
            let safeEndMs = max(endMs, entry.beginMs + 1)

            return LyricsLine(
                id: index,
                text: entry.text,
                startMs: entry.beginMs,
                endMs: safeEndMs,
                words: closeWords(entry.words, lineEndMs: safeEndMs)
            )
        }
    }

    /// ✅ Cierra los timings de las palabras: cada una dura hasta el inicio de la
    /// siguiente y la última hasta el fin de la línea (así nunca queda end < begin).
    static func closeWords(_ words: [Word], lineEndMs: Int) -> [LyricWordToken] {
        words.enumerated().map { index, word in
            let fallbackEndMs = index + 1 < words.count ? words[index + 1].beginMs : lineEndMs
            let endMs = word.endMs ?? fallbackEndMs
            return LyricWordToken(
                text: word.text,
                startMs: word.beginMs,
                endMs: max(endMs, word.beginMs),
                rowIndex: word.rowIndex
            )
        }
    }

    // MARK: - Expresiones de tiempo
    /// Convierte una expresión de tiempo TTML a milisegundos.
    /// ✅ Soporta tiempo de reloj ([hh:]mm:ss.frac) y de offset (h/m/s/ms).
    static func milliseconds(_ raw: String?) -> Int? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }

        // ✅ Offset time: sufijo obligatorio (12.5s, 500ms, 2m, 1h).
        let metrics: [(suffix: String, scale: Double)] = [("ms", 1), ("s", 1000), ("m", 60_000), ("h", 3_600_000)]
        for metric in metrics where value.hasSuffix(metric.suffix) {
            value.removeLast(metric.suffix.count)
            guard let number = Double(value) else { return nil }
            return Int((number * metric.scale).rounded())
        }

        // ✅ Clock time: hh:mm:ss.frac | mm:ss.frac | ss.frac
        let parts = value.split(separator: ":")
        guard parts.count <= 3 else { return nil }
        var seconds = 0.0
        for part in parts {
            guard let number = Double(part) else { return nil }
            seconds = seconds * 60 + number
        }
        return Int((seconds * 1000).rounded())
    }

    /// Normaliza el texto de una línea (TTML suele venir con indentaciones).
    static func normalized(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// ✅ Normaliza RESPETANDO los saltos duros: cada fila se normaliza por
    /// separado (la indentación del XML desaparece) y las filas se unen con un
    /// `\n` real. Las filas vacías se descartan, y el índice de fila de cada
    /// palabra (`rowIndex`) se cuenta con la MISMA regla, así que quedan
    /// alineados fila ↔ palabras incluso con `<br/>` repetidos o al final.
    static func normalizedRows(_ text: String) -> String {
        text.split(separator: hardBreak, omittingEmptySubsequences: true)
            .map { normalized(String($0)) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    // MARK: - XMLParserDelegate
    /// ✅ Acumula en propiedades escalares/arrays propios (sin structs copiados
    /// por carácter) para que el parseo de una canción sea de un solo pase.
    private final class Delegate: NSObject, XMLParserDelegate {
        private(set) var entries: [Line] = []
        private(set) var usesTTMLNamespace = false

        private var isInsideLine = false
        private var isInsideWord = false
        private var lineBeginMs = 0
        private var lineEndMs: Int?
        private var lineText = ""
        private var lineWords: [Word] = []
        /// Fila visual actual dentro de la línea (sube con cada `<br/>`).
        private var lineRowIndex = 0

        private var wordBeginMs = 0
        private var wordEndMs: Int?
        private var wordText = ""
        private var wordRowIndex = 0

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            if namespaceURI == TTMLParser.namespace {
                usesTTMLNamespace = true
            }

            switch localName(elementName, qualifiedName: qName) {
            case "p":
                isInsideLine = true
                lineBeginMs = TTMLParser.milliseconds(attributeDict["begin"]) ?? 0
                lineEndMs = TTMLParser.milliseconds(attributeDict["end"])
                lineText = ""
                lineWords = []
                lineRowIndex = 0
            case "span":
                guard isInsideLine else { return }
                isInsideWord = true
                wordBeginMs = TTMLParser.milliseconds(attributeDict["begin"]) ?? lineBeginMs
                wordEndMs = TTMLParser.milliseconds(attributeDict["end"])
                wordText = ""
                wordRowIndex = lineRowIndex
            case "br":
                markHardBreak()
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard isInsideLine else { return }
            lineText += string
            if isInsideWord { wordText += string }
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            switch localName(elementName, qualifiedName: qName) {
            case "span":
                finishWord()
            case "p":
                finishWord()
                finishLine()
            default:
                break
            }
        }

        // MARK: Acumuladores
        private func finishWord() {
            guard isInsideWord else { return }
            isInsideWord = false
            // ✅ Nunca se deja la marca de salto dentro del texto de una palabra.
            let text = wordText
                .split(separator: TTMLParser.hardBreak, omittingEmptySubsequences: true)
                .map { TTMLParser.normalized(String($0)) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if !text.isEmpty {
                lineWords.append(Word(
                    beginMs: wordBeginMs,
                    endMs: wordEndMs,
                    text: text,
                    rowIndex: wordRowIndex
                ))
            }
            wordText = ""
        }

        /// ✅ `<br/>` = fila nueva. Los saltos repetidos o al principio de la
        /// línea se ignoran para que `lineRowIndex` cuente exactamente las filas
        /// que `normalizedRows` va a conservar.
        private func markHardBreak() {
            guard isInsideLine, !isAtRowBreak else { return }
            lineText.append(TTMLParser.hardBreak)
            lineRowIndex += 1
        }

        /// ✅ ¿La fila actual está vacía (solo whitespace o un salto ya puesto)?
        private var isAtRowBreak: Bool {
            guard let index = lineText.lastIndex(where: { !$0.isWhitespace }) else { return true }
            return lineText[index] == TTMLParser.hardBreak
        }

        private func finishLine() {
            guard isInsideLine else { return }
            isInsideLine = false
            let text = TTMLParser.normalizedRows(lineText)
            if !text.isEmpty {
                entries.append(Line(beginMs: lineBeginMs, endMs: lineEndMs, text: text, words: lineWords))
            }
            lineText = ""
            lineWords = []
        }

        private func localName(_ name: String, qualifiedName: String?) -> String {
            let value = qualifiedName ?? name
            return value.split(separator: ":").last.map(String.init) ?? value
        }
    }
}

// MARK: - Tests unitarios para TTMLParser
#if DEBUG
extension TTMLParser {
    static func runTests() {
        print("🧪 Ejecutando tests de TTMLParser...")

        let sample = """
        <?xml version="1.0" encoding="UTF-8"?>
        <tt xmlns="http://www.w3.org/ns/ttml" xml:lang="es">
          <body>
            <div>
              <p begin="00:00:01.000" end="00:00:03.500">
                <span begin="00:00:01.000" end="00:00:01.800">Hola</span>
                <span begin="00:00:01.800" end="00:00:03.400">mundo</span>
              </p>
              <p begin="00:00:04.000" end="00:00:05.000">Segunda línea</p>
            </div>
          </body>
        </tt>
        """
        let parsed = parse(sample)
        assert(parsed?.count == 2, "TTML Test 1 falló: Expected 2 lines")
        assert(parsed?[0].displayText == "Hola mundo", "TTML Test 1 falló: Text mismatch")
        assert(parsed?[0].startMs == 1000 && parsed?[0].endMs == 3500, "TTML Test 1 falló: Window mismatch")
        assert(parsed?[0].words.count == 2, "TTML Test 1 falló: Expected 2 word tokens")
        assert(parsed?[0].words[0].endMs == 1800, "TTML Test 1 falló: Word end mismatch")
        assert(parsed?[1].words.isEmpty == true, "TTML Test 1 falló: Line without spans has no words")
        print("✅ TTML Test 1 (líneas + palabras) passed")

        assert(parse("[00:01.00]Texto LRC normal") == nil, "TTML Test 2 falló: LRC no debe parsearse como TTML")
        assert(parse("") == nil, "TTML Test 2 falló: Texto vacío")
        print("✅ TTML Test 2 (no confunde LRC) passed")

        // ✅ Test 2b: `<br/>` = fila visual propia (nunca un espacio perdido).
        let multiline = """
        <tt xmlns="http://www.w3.org/ns/ttml"><body><div>
        <p begin="00:00:01.000" end="00:00:05.000">
          <span begin="00:00:01.000" end="00:00:02.000">Primera</span>
          <span begin="00:00:02.000" end="00:00:03.000">fila<br/></span>
          <span begin="00:00:04.000" end="00:00:05.000">Segunda</span>
        </p>
        </div></body></tt>
        """
        guard let rows = parse(multiline)?.first else {
            assertionFailure("TTML Test 2b falló: no se parseó la línea")
            return
        }
        assert(rows.displayText == "Primera fila\nSegunda", "TTML Test 2b falló: filas mal unidas")
        assert(rows.visualRows.count == 2, "TTML Test 2b falló: Expected 2 filas visuales")
        // La fila 1 se rellena con SUS palabras y se queda completa durante el
        // silencio (3000→4000ms); la fila 2 no empieza hasta su propio timestamp.
        assert(rows.visualRows[0].startMs == 1000 && rows.visualRows[0].endMs == 3000, "TTML Test 2b falló: ventana de la fila 1")
        assert(rows.visualRows[1].startMs == 4000 && rows.visualRows[1].endMs == 5000, "TTML Test 2b falló: ventana de la fila 2")
        assert(rows.visualRows[0].endMs <= rows.visualRows[1].startMs, "TTML Test 2b falló: filas solapadas")
        print("✅ TTML Test 2b (filas visuales por <br/>) passed")

        assert(milliseconds("00:00:12.500") == 12_500, "TTML Test 3 falló: Clock time")
        assert(milliseconds("01:02:03") == 3_723_000, "TTML Test 3 falló: Clock time con horas")
        assert(milliseconds("1500ms") == 1500, "TTML Test 3 falló: Offset ms")
        assert(milliseconds("2.5s") == 2500, "TTML Test 3 falló: Offset s")
        assert(milliseconds("1m") == 60_000, "TTML Test 3 falló: Offset m")
        assert(milliseconds(nil) == nil, "TTML Test 3 falló: nil")
        print("✅ TTML Test 3 (expresiones de tiempo) passed")

        print("🎉 Todos los tests de TTMLParser pasaron correctamente")
    }
}
#endif
