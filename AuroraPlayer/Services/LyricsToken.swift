import Foundation

/// Palabra individual con sincronización en milisegundos absolutos.
/// Struct puro (sin lógica) para que viva barato en el hot path del motor.
struct LyricsToken: Identifiable, Equatable {
    let id: String
    let text: String
    let startMs: Int
    let endMs: Int
    let lineIndex: Int
    let wordIndex: Int
    /// Carril para voces simultáneas o traducciones (0 = principal).
    /// El parser actual no produce datos de traducción, así que hoy
    /// siempre es 0; el campo queda listo para cuando exista esa fuente.
    let lane: Int
}

/// Línea agrupando tokens de su carril principal. startMs/endMs se derivan
/// del primer y último token, no se calculan en el render.
struct LyricsLine: Identifiable, Equatable {
    let id: String
    let lineIndex: Int
    let startMs: Int
    let endMs: Int
    let tokenIDs: [String]
}

/// Estado calculado por el motor para un instante dado. Puramente
/// descriptivo: la vista solo lo lee, nunca lo produce.
struct LyricsState: Equatable {
    let activeTokenID: String?
    let previousTokenID: String?
    let nextTokenID: String?
    let activeLineIndex: Int?
    /// Progreso 0...1 del token activo. Saturado a 1.0 durante huecos
    /// (ver diseño "sticky" en LyricsEngine.state(at:)).
    let progress: Double
}