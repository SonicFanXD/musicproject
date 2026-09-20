import SwiftUI

/// Dibuja UNA línea concreta, palabra por palabra, animada a 60fps.
/// No calcula tiempos: llama a engine.lineWordProgress() y solo dibuja.
struct LyricsCanvasView: View {
    let engine: LyricsEngine
    let layout: LyricsLayout
    let lineIndex: Int
    let currentTimeMs: () -> Int

    var body: some View {
        TimelineView(.animation) { _ in
            Canvas { context, size in
                let progresses = engine.lineWordProgress(lineIndex: lineIndex, at: currentTimeMs())
                draw(context: context, size: size, progresses: progresses)
            }
        }
    }

    private func draw(context: GraphicsContext, size: CGSize, progresses: [(token: LyricsToken, progress: Double, isPast: Bool)]) {
        guard let entries = layout.tokensByLine[lineIndex] else { return }
        var xCursor = layout.leftInset
        let baselineY = size.height / 2

        for entry in entries {
            let match = progresses.first { $0.token.id == entry.token.id }
            let progress = match?.progress ?? 0
            let scale = 1.0 + 0.06 * progress
            let opacity = 0.45 + 0.55 * progress
            let resolved = context.resolve(entry.text)

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