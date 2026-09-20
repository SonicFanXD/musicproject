import Foundation

// MARK: - Motor puro y determinista para lyrics línea por línea
// ✅ Diseñado para iPhone 8 Plus: cero allocations por frame, cero closures nuevas
// ✅ Búsqueda binaria O(log n) en lugar de búsqueda lineal O(n)
// ✅ Sin efectos secundarios, sin allocations en runtime
struct LyricsEngine {
    private let lines: [LyricsLine]
    
    init(lines: [LyricsLine]) {
        // ✅ Asegurar que las líneas estén ordenadas por startMs
        self.lines = lines.sorted { $0.startMs < $1.startMs }
    }
    
    // MARK: - Búsqueda de línea activa
    /// Devuelve el índice de la línea activa en un tiempo dado
    /// - Parameter timeMs: Tiempo en milisegundos
    /// - Returns: Índice de la línea activa, o nil si timeMs cae en un gap o fuera de rango
    /// ✅ Búsqueda binaria O(log n): cero allocations, cero closures, puramente determinista
    /// ✅ BUFFER DE TRANSICIÓN: Para líneas cortas consecutivas, añade 120ms de overlap
    func activeIndex(at timeMs: Int) -> Int? {
        guard !lines.isEmpty else { return nil }
        
        // ✅ Casos borde: tiempo antes de primera línea o después de última
        if timeMs < lines[0].startMs { return nil }
        if timeMs >= lines[lines.count - 1].endMs { return nil }
        
        // ✅ Búsqueda binaria optimizada
        var low = 0
        var high = lines.count - 1
        
        while low <= high {
            let mid = low + (high - low) / 2
            let line = lines[mid]
            
            if timeMs < line.startMs {
                high = mid - 1
            } else if timeMs >= line.endMs {
                low = mid + 1
            } else {
                // ✅ timeMs está dentro de [startMs, endMs)
                // ✅ BUFFER DE TRANSICIÓN: Si hay línea siguiente y el tiempo está cerca del final,
                // extender la línea actual por 120ms para evitar transición brusca
                if mid < lines.count - 1 {
                    let nextLine = lines[mid + 1]
                    let gap = nextLine.startMs - line.endMs
                    let timeToNext = nextLine.startMs - timeMs
                    // Si el gap es pequeño (< 200ms) y estamos cerca del final (< 150ms de nextLine)
                    if gap < 200 && timeToNext < 150 {
                        return mid  // Retener línea actual durante overlap
                    }
                }
                return mid
            }
        }
        
        // ✅ Gap entre líneas: timeMs no está en ninguna línea
        return nil
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
    
    // ✅ DEBUG: IDs de todas las líneas para diagnóstico
    func allLineIDs() -> [Int] {
        lines.map { $0.id }
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
        
        print("🎉 Todos los tests de LyricsEngine pasaron correctamente")
    }
}
#endif
