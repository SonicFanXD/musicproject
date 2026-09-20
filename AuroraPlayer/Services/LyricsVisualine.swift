import Foundation

/// Agrupación de tokens por línea, para el render. No confundir con
/// `LyricLine` (en LyricsModels.swift): esa es la línea "cruda" del parser
/// (time/text en segundos); esta es la agrupación derivada de LyricsToken
/// (ms) que usa el motor y la vista para dibujar y hacer scroll.
struct LyricsVisualLine: Identifiable, Equatable {
    let id: String
    let lineIndex: Int
    let startMs: Int
    let endMs: Int
    let tokenIDs: [String]
}