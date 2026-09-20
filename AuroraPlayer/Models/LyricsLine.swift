import Foundation

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
    
    // ✅ Texto completo de la línea (sin timestamps de palabra)
    // El parser de formato híbrido eliminará los timestamps <mm:ss.xxx>
    var cleanText: String {
        text.replacingOccurrences(of: "<[0-9:.]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
