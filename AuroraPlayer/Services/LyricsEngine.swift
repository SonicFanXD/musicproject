import Foundation

// MARK: - Motor puro y determinista para lyrics línea por línea
// ✅ Diseñado para iPhone 8 Plus: cero allocations por frame, cero closures nuevas
// ✅ Búsqueda binaria O(log n) en lugar de búsqueda lineal O(n)
// ✅ Sin efectos secundarios, sin allocations en runtime
struct LyricsEngine {
    /// ✅ Buffer de transición ADAPTATIVO: la línea sigue activa un poco más
    /// allá de su fin real, en proporción al hueco REAL hasta la siguiente
    /// línea (gap / 2, máximo 60ms). No es un valor fijo: un hueco corto da
    /// una transición corta, y un hueco largo nunca deja la línea "pegada".
    private static let maxTransitionBufferMs = 60

    private let lines: [LyricsLine]

    init(lines: [LyricsLine]) {
        // ✅ Ordenar por startMs. Desempate por id para que el orden sea
        // determinista con timestamps duplicados (id == índice siempre).
        self.lines = lines.sorted { ($0.startMs, $0.id) < ($1.startMs, $1.id) }
    }

    // MARK: - Ventana de una línea
    /// Fin EFECTIVO de la línea `index`: `endMs` + buffer adaptativo, sin
    /// invadir nunca el inicio de la siguiente línea.
    private func effectiveEndMs(for index: Int) -> Int {
        let line = lines[index]
        guard index + 1 < lines.count else { return line.endMs }
        let nextStartMs = lines[index + 1].startMs
        let gap = max(0, nextStartMs - line.endMs)
        let buffer = min(gap / 2, Self.maxTransitionBufferMs)
        return min(nextStartMs, line.endMs + buffer)
    }

    /// Ventana (inicio + fin efectivo) de una línea: la usa el relleno
    /// progresivo de la UI para saber hasta cuándo debe crecer la máscara.
    func window(for index: Int) -> (startMs: Int, endMs: Int)? {
        guard index >= 0 && index < lines.count else { return nil }
        return (lines[index].startMs, effectiveEndMs(for: index))
    }

    // MARK: - Búsqueda de línea activa
    /// Devuelve el índice de la línea activa en un tiempo dado
    /// - Parameter timeMs: Tiempo en milisegundos
    /// - Returns: Índice de la línea activa, o nil si timeMs cae en un gap o fuera de rango
    /// ✅ Búsqueda binaria O(log n): cero allocations, cero closures, puramente determinista
    func activeIndex(at timeMs: Int) -> Int? {
        guard !lines.isEmpty else { return nil }

        // ✅ Casos borde: tiempo antes de primera línea o después de última
        if timeMs < lines[0].startMs { return nil }
        if timeMs >= effectiveEndMs(for: lines.count - 1) { return nil }

        // ✅ Búsqueda binaria optimizada
        var low = 0
        var high = lines.count - 1

        while low <= high {
            let mid = low + (high - low) / 2
            let line = lines[mid]

            if timeMs < line.startMs {
                high = mid - 1
            } else if timeMs >= effectiveEndMs(for: mid) {
                low = mid + 1
            } else {
                // ✅ timeMs está dentro de [startMs, fin efectivo)
                return mid
            }
        }

        // ✅ Gap entre líneas: timeMs no está en ninguna línea
        return nil
    }

    // MARK: - Resaltado durante huecos
    /// Última línea que YA empezó en `timeMs` (nil antes de la primera línea).
    /// ✅ En huecos largos (intro, interludio) mantiene resaltada la línea
    /// anterior en vez de atenuar toda la vista, como hace Apple Music.
    func lastStartedIndex(at timeMs: Int) -> Int? {
        guard !lines.isEmpty, timeMs >= lines[0].startMs else { return nil }

        var low = 0
        var high = lines.count - 1
        var result = 0

        while low <= high {
            let mid = low + (high - low) / 2
            if lines[mid].startMs <= timeMs {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        return result
    }

    /// Inicio de la siguiente línea después de `timeMs` (nil si no queda
    /// ninguna). ✅ Permite despertar EXACTAMENTE en el cambio de línea sin
    /// esperar al tick de 0.4s del reloj de reproducción.
    func nextStartMs(afterMs timeMs: Int) -> Int? {
        guard !lines.isEmpty else { return nil }

        var low = 0
        var high = lines.count - 1
        var result: Int? = nil

        while low <= high {
            let mid = low + (high - low) / 2
            if lines[mid].startMs > timeMs {
                result = lines[mid].startMs
                high = mid - 1
            } else {
                low = mid + 1
            }
        }

        return result
    }

    // MARK: - Seek a tiempo específico
    /// Devuelve el índice de la línea activa después de un seek
    /// - Parameter timeMs: Tiempo en milisegundos
    /// - Returns: Índice de la línea activa, o nil si timeMs cae en un gap
    /// ✅ Usa la misma lógica de búsqueda binaria que activeIndex
    func seekIndex(at timeMs: Int) -> Int? {
        return activeIndex(at: timeMs)
    }

    // MARK: - Información de líneas
    /// Número total de líneas
    var count: Int {
        lines.count
    }

    /// Línea en un índice específico (safe access)
    func line(at index: Int) -> LyricsLine? {
        guard index >= 0 && index < lines.count else { return nil }
        return lines[index]
    }
}

// MARK: - Tests unitarios para LyricsEngine
// ✅ Casos borde: gaps, seek, inicio, fin, array vacío, búsqueda binaria
#if DEBUG
extension LyricsEngine {
    static func runTests() {
        print("🧪 Ejecutando tests de LyricsEngine...")
        
        // Test 1: Array vacío
        let emptyEngine = LyricsEngine(lines: [])
        assert(emptyEngine.activeIndex(at: 1000) == nil, "Test 1 falló: Expected nil for empty engine")
        print("✅ Test 1 (Array vacío) passed")
        
        // Test 2: Línea única
        let singleLine = LyricsLine(id: 0, text: "Test", startMs: 1000, endMs: 5000)
        let singleEngine = LyricsEngine(lines: [singleLine])
        assert(singleEngine.activeIndex(at: 2000) == 0, "Test 2 falló: Expected index 0")
        assert(singleEngine.activeIndex(at: 500) == nil, "Test 2 falló: Expected nil before start")
        assert(singleEngine.activeIndex(at: 6000) == nil, "Test 2 falló: Expected nil after end")
        print("✅ Test 2 (Línea única) passed")
        
        // Test 3: Múltiples líneas con gaps
        let lines = [
            LyricsLine(id: 0, text: "Línea 1", startMs: 1000, endMs: 3000),
            LyricsLine(id: 1, text: "Línea 2", startMs: 5000, endMs: 7000), // Gap de 2s
            LyricsLine(id: 2, text: "Línea 3", startMs: 8000, endMs: 10000)
        ]
        let gapEngine = LyricsEngine(lines: lines)
        assert(gapEngine.activeIndex(at: 2000) == 0, "Test 3 falló: Expected index 0")
        assert(gapEngine.activeIndex(at: 4000) == nil, "Test 3 falló: Expected nil in gap")
        assert(gapEngine.activeIndex(at: 6000) == 1, "Test 3 falló: Expected index 1")
        print("✅ Test 3 (Gaps entre líneas) passed")
        
        // Test 4: Seek a tiempo específico
        assert(gapEngine.seekIndex(at: 4500) == nil, "Test 4 falló: Expected nil for seek in gap")
        assert(gapEngine.seekIndex(at: 5500) == 1, "Test 4 falló: Expected index 1 for seek")
        print("✅ Test 4 (Seek) passed")
        
        // Test 5: Inicio y fin
        assert(gapEngine.activeIndex(at: 0) == nil, "Test 5 falló: Expected nil at time 0")
        assert(gapEngine.activeIndex(at: 11000) == nil, "Test 5 falló: Expected nil after last line")
        print("✅ Test 5 (Inicio y fin) passed")
        
        // Test 6: Líneas ordenadas automáticamente
        let unsortedLines = [
            LyricsLine(id: 2, text: "Tercera", startMs: 8000, endMs: 10000),
            LyricsLine(id: 0, text: "Primera", startMs: 1000, endMs: 3000),
            LyricsLine(id: 1, text: "Segunda", startMs: 5000, endMs: 7000)
        ]
        let unsortedEngine = LyricsEngine(lines: unsortedLines)
        assert(unsortedEngine.activeIndex(at: 2000) == 0, "Test 6 falló: Expected index 0 after sorting")
        assert(unsortedEngine.activeIndex(at: 6000) == 1, "Test 6 falló: Expected index 1 after sorting")
        print("✅ Test 6 (Ordenamiento automático) passed")

        // Test 7: Buffer de transición ADAPTATIVO (gap/2, máx 60ms)
        let wideGap = LyricsEngine(lines: [
            LyricsLine(id: 0, text: "A", startMs: 0, endMs: 1000),
            LyricsLine(id: 1, text: "B", startMs: 3000, endMs: 4000)
        ])
        // gap = 2000ms → buffer = 60ms (tope) → fin efectivo 1060ms
        assert(wideGap.activeIndex(at: 1050) == 0, "Test 7 falló: Expected buffered line at 1050ms")
        assert(wideGap.activeIndex(at: 1100) == nil, "Test 7 falló: Expected nil past buffered end")
        assert(wideGap.window(for: 0)?.endMs == 1060, "Test 7 falló: Expected effective end 1060ms")
        let narrowGap = LyricsEngine(lines: [
            LyricsLine(id: 0, text: "A", startMs: 0, endMs: 1000),
            LyricsLine(id: 1, text: "B", startMs: 1040, endMs: 2000)
        ])
        // gap = 40ms → buffer = 20ms → fin efectivo 1020ms
        assert(narrowGap.activeIndex(at: 1015) == 0, "Test 7 falló: Expected buffered line at 1015ms")
        assert(narrowGap.activeIndex(at: 1025) == nil, "Test 7 falló: Expected nil past buffered end")
        print("✅ Test 7 (Buffer adaptativo) passed")

        // Test 8: Resaltado durante huecos (última línea que ya empezó)
        assert(gapEngine.lastStartedIndex(at: 500) == nil, "Test 8 falló: Expected nil before first line")
        assert(gapEngine.lastStartedIndex(at: 3500) == 0, "Test 8 falló: Expected index 0 in gap")
        assert(gapEngine.lastStartedIndex(at: 4000) == 0, "Test 8 falló: Expected index 0 in gap")
        assert(gapEngine.lastStartedIndex(at: 9000) == 2, "Test 8 falló: Expected index 2")
        print("✅ Test 8 (Resaltado en huecos) passed")

        // Test 9: Próximo inicio de línea (despertar exacto)
        assert(gapEngine.nextStartMs(afterMs: 500) == 1000, "Test 9 falló: Expected 1000ms")
        assert(gapEngine.nextStartMs(afterMs: 3500) == 5000, "Test 9 falló: Expected 5000ms")
        assert(gapEngine.nextStartMs(afterMs: 9000) == nil, "Test 9 falló: Expected nil after last line")
        print("✅ Test 9 (Próximo inicio) passed")
        
        print("🎉 Todos los tests de LyricsEngine pasaron correctamente")
    }
}
#endif
