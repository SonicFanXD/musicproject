import Foundation

// MARK: - Timing de una palabra (TTML / LRC híbrido)
// ✅ SOLO DATOS: la UI no hace karaoke por palabra en esta iteración.
struct LyricWordToken: Equatable {
    let text: String
    let startMs: Int
    let endMs: Int
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

    init(id: Int, text: String, startMs: Int, endMs: Int, words: [LyricWordToken] = []) {
        self.id = id
        self.text = text
        self.startMs = startMs
        self.endMs = endMs
        self.words = words
        self.displayText = LyricsLine.cleaned(text)
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
}
