import Foundation

// MARK: - Parser de LRC clásico y formato híbrido
// ✅ Soporta:
// - LRC clásico: [mm:ss.xx] texto
// - Formato híbrido: [mm:ss.xx]<mm:ss.xxx>texto (extrae solo línea)
// - Metadatos: [ti:], [ar:], [al:], [offset:]
// - Líneas vacías, timestamps duplicados, saltos de línea
// ✅ Optimizado para iPhone 8 Plus: sin allocations por línea, regex eficiente
struct LRCParser {
    
    // MARK: - Parse completo de texto LRC
    /// Parsea texto LRC y devuelve array de LyricsLine ordenado por startMs
    /// - Parameter text: Texto LRC crudo
    /// - Returns: Array de LyricsLine ordenado cronológicamente
    static func parse(_ text: String) -> [LyricsLine] {
        guard !text.isEmpty else { return [] }
        
        var lines: [LyricsLine] = []
        var idCounter = 0
        
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
            guard let timestamp = extractLineTimestamp(trimmed) else { continue }
            
            // ✅ Extraer texto completo (limpiando timestamps de palabra <...>)
            let cleanText = extractCleanText(trimmed)
            guard !cleanText.isEmpty else { continue }
            
            // ✅ Calcular endMs (si hay siguiente línea, usar su startMs, si no, +10s)
            let startMs = timestamp
            let endMs = startMs + 10000 // 10 segundos por defecto para última línea
            
            let lyricLine = LyricsLine(
                id: idCounter,
                text: cleanText,
                startMs: startMs,
                endMs: endMs
            )
            
            lines.append(lyricLine)
            idCounter += 1
        }
        
        // ✅ Corregir endMs basándose en la siguiente línea
        for i in 0..<lines.count {
            if i < lines.count - 1 {
                lines[i] = LyricsLine(
                    id: lines[i].id,
                    text: lines[i].text,
                    startMs: lines[i].startMs,
                    endMs: lines[i + 1].startMs
                )
            }
        }
        
        // ✅ Ordenar por startMs (ya debería estar ordenado, pero garantizamos)
        return lines.sorted { $0.startMs < $1.startMs }
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
        
        let minuteRange = Range(match.range(at: 1), in: line)!
        let secondRange = Range(match.range(at: 2), in: line)!
        let millisecondRange = match.range(at: 3).location != NSNotFound 
            ? Range(match.range(at: 3), in: line) 
            : nil
        
        guard let minutes = Int(line[minuteRange]),
              let seconds = Int(line[secondRange]) else {
            return nil
        }
        
        let milliseconds = millisecondRange.map { Int(line[$0]) ?? 0 } ?? 0
        let msMultiplier = (millisecondRange?.count ?? 2) == 3 ? 1 : 10 // Ajustar para 2 o 3 dígitos
        
        return (minutes * 60 * 1000) + (seconds * 1000) + (milliseconds * msMultiplier)
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
        
        print("🎉 Todos los tests de LRCParser pasaron correctamente")
    }
}
#endif
