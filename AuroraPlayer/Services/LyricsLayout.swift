import SwiftUI
import UIKit

/// Métricas y `Text` precalculados por token, UNA sola vez al cargar la
/// letra — nunca por frame. Evita medir texto (CTLine) en el hot path.
struct LyricsLayout {
    struct TokenEntry {
        let token: LyricsToken
        let text: Text
        let width: CGFloat
    }

    let tokensByLine: [Int: [TokenEntry]]
    let tokenOrder: [String: Int]   // id -> posición global, para saber "ya pasó"
    let leftInset: CGFloat
    let wordSpacing: CGFloat

    static func build(tokens: [LyricsToken], font: UIFont, wordSpacing: CGFloat = 8, leftInset: CGFloat = 16) -> LyricsLayout {
        var byLine: [Int: [TokenEntry]] = [:]
        var order: [String: Int] = [:]
        let attributes: [NSAttributedString.Key: Any] = [.font: font]

        for (index, token) in tokens.enumerated() {
            let width = (token.text as NSString).size(withAttributes: attributes).width
            byLine[token.lineIndex, default: []].append(
                TokenEntry(token: token, text: Text(token.text).font(Font(font)), width: width)
            )
            order[token.id] = index
        }

        return LyricsLayout(tokensByLine: byLine, tokenOrder: order, leftInset: leftInset, wordSpacing: wordSpacing)
    }
}

/// Vista de render PURO: no calcula tiempos, solo consulta LyricsEngine y
/// dibuja. `currentTimeMs` es un closure inyectado desde afuera (ver nota
/// de arquitectura al inicio de la respuesta) llamado en cada tick de
/// TimelineView(.animation) — así la animación corre a 60fps reales,
/// independiente de la cadencia (0.4s/3s) del @Published del AudioEngine.
struct LyricsCanvasView: View {
    let engine: LyricsEngine
    let layout: LyricsLayout
    let currentTimeMs: () -> Int

    var body: some View {
        TimelineView(.animation) { _ in
            Canvas { context, size in
                let state = engine.state(at: currentTimeMs())
                draw(context: context, size: size, state: state)
            }
        }
    }

    private func draw(context: GraphicsContext, size: CGSize, state: LyricsState) {
        guard let lineIndex = state.activeLineIndex,
              let lineTokens = layout.tokensByLine[lineIndex] else { return }

        let activeOrder = state.activeTokenID.flatMap { layout.tokenOrder[$0] } ?? -1
        var xCursor = layout.leftInset
        let baselineY = size.height / 2

        for entry in lineTokens {
            let order = layout.tokenOrder[entry.token.id] ?? 0
            let isActive = entry.token.id == state.activeTokenID
            let isPast = order < activeOrder

            // Mapeo puramente visual de progress → estilo. Sin cálculo
            // temporal aquí: progress ya viene resuelto por el motor.
            let localProgress: Double = isActive ? state.progress : (isPast ? 1.0 : 0.0)
            let scale = 1.0 + 0.06 * localProgress
            let opacity = 0.45 + 0.55 * localProgress

            let resolved = context.resolve(entry.text)

            // ✅ drawLayer aísla la transformación de cada palabra: la
            // API "bendecida" de GraphicsContext para esto (en vez de
            // mutar `context` directamente y arrastrar el transform a la
            // siguiente palabra).
            context.drawLayer { layerContext in
                layerContext.opacity = opacity
                layerContext.translateBy(x: xCursor, y: baselineY)
                layerContext.scaleBy(x: scale, y: scale)
                layerContext.draw(resolved, at: .zero, anchor: .topLeading)
            }

            xCursor += entry.width + layout.wordSpacing
        }
    }
}