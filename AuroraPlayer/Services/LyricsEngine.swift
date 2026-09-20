import Foundation

/// Motor puro de sincronización. Sin side effects: state(at:) siempre
/// devuelve lo mismo para el mismo timeMs. Cero allocations en el hot path.
///
/// ✅ Reemplaza a la clase privada LyricsEngine que vivía dentro de
/// LyricsView.swift. Diferencias respecto a esa versión:
/// - progress SIEMPRE clamped a 0...1 (la anterior podía superar 1.0
///   durante huecos entre palabras).
/// - lineIndex correcto por construcción (viene de LyricsTokenBuilder ya
///   arreglado, no de la conversión rota anterior).
/// - Diseño de huecos: STICKY (confirmado) — durante un silencio, el token
///   activo se mantiene en la última palabra sonada con progress = 1.0.
struct LyricsEngine {
    private let tokens: [LyricsToken]
    private let lineIndexRanges: [Int: Range<Int>]

    init(tokens: [LyricsToken]) {
        self.tokens = tokens
        var ranges: [Int: Range<Int>] = [:]
        if !tokens.isEmpty {
            var groupStart = 0
            for i in 1...tokens.count {
                let isBoundary = i == tokens.count || tokens[i].lineIndex != tokens[groupStart].lineIndex
                guard isBoundary else { continue }
                ranges[tokens[groupStart].lineIndex] = groupStart..<i
                groupStart = i
            }
        }
        self.lineIndexRanges = ranges
    }

    func state(at timeMs: Int) -> LyricsState {
        guard !tokens.isEmpty else {
            return LyricsState(activeTokenID: nil, progress: 0, activeLineIndex: 0, previousTokenID: nil, nextTokenID: nil)
        }
        guard let index = lastTokenIndex(startingAtOrBefore: timeMs) else {
            // Anterior a la primera palabra: ningún token activo aún.
            return LyricsState(activeTokenID: nil, progress: 0, activeLineIndex: 0, previousTokenID: nil, nextTokenID: tokens.first?.id)
        }
        let token = tokens[index]
        let previousID = index > 0 ? tokens[index - 1].id : nil
        let nextID = index + 1 < tokens.count ? tokens[index + 1].id : nil

        // Sticky: clamp del tiempo al rango del token en vez de dejar que el
        // progreso se dispare en el silencio hasta la siguiente palabra.
        let clampedTimeMs = min(max(timeMs, token.startMs), token.endMs)
        let span = token.endMs - token.startMs
        let rawProgress = span > 0 ? Double(clampedTimeMs - token.startMs) / Double(span) : 1.0

        return LyricsState(
            activeTokenID: token.id,
            progress: min(max(rawProgress, 0), 1),
            activeLineIndex: token.lineIndex,
            previousTokenID: previousID,
            nextTokenID: nextID
        )
    }

    /// Progreso de cada palabra de UNA línea, para el render por línea activa.
    func lineWordProgress(lineIndex: Int, at timeMs: Int) -> [(token: LyricsToken, progress: Double)] {
        guard let range = lineIndexRanges[lineIndex] else { return [] }
        return range.map { i in
            let token = tokens[i]
            if timeMs < token.startMs { return (token, 0.0) }
            if timeMs >= token.endMs { return (token, 1.0) }
            let span = token.endMs - token.startMs
            let p = span > 0 ? Double(timeMs - token.startMs) / Double(span) : 1.0
            return (token, min(max(p, 0), 1))
        }
    }

    /// Búsqueda binaria: índice del ÚLTIMO token con startMs <= timeMs.
    private func lastTokenIndex(startingAtOrBefore timeMs: Int) -> Int? {
        var low = 0
        var high = tokens.count - 1
        var result: Int? = nil
        while low <= high {
            let mid = (low + high) / 2
            if tokens[mid].startMs <= timeMs {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }
}