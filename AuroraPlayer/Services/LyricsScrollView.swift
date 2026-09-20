import SwiftUI

/// Hace scroll automático a la línea activa. Solo esa línea se redibuja a
/// 60fps; el resto son Text estáticos precomputados (sin costo por frame).
/// LazyVStack: las líneas fuera de pantalla ni siquiera se renderizan.
struct LyricsScrollView: View {
    let engine: LyricsEngine
    let layout: LyricsLayout
    let lines: [LyricsLine]
    let currentTimeMs: () -> Int

    // ✅ Solo se reasigna cuando la línea activa CAMBIA de verdad. SwiftUI
    // no invalida la vista si el valor asignado es igual al actual, así que
    // aunque el tracker "pregunte" 60 veces/seg, el ForEach de abajo solo
    // se reevalúa las pocas veces por canción que hay un cambio real de
    // línea — no hay recreación de vistas por frame.
    @State private var activeLineIndex: Int?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(lines) { line in
                        lineRow(for: line)
                            .id(line.id)
                    }
                }
                .padding(.vertical, 140) // hueco arriba/abajo para poder centrar la primera/última línea
            }
            .overlay(activeLineTracker)
            .onChange(of: activeLineIndex) { newValue in
                guard let newValue, let line = lines.first(where: { $0.lineIndex == newValue }) else { return }
                // ✅ Única animación explícita del sistema: dispara SOLO al
                // cambiar de línea (pocas veces por canción), nunca por frame.
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(line.id, anchor: .center)
                }
            }
        }
    }

    /// Vista invisible (tamaño cero): el único propósito es preguntarle al
    /// motor, en cada tick de TimelineView(.animation), cuál es la línea
    /// activa AHORA — y solo escribir el @State si de verdad cambió.
    /// TimelineView(.animation) es el driver permitido por el contrato;
    /// nunca Timer ni asyncAfter.
    private var activeLineTracker: some View {
        TimelineView(.animation) { context in
            Color.clear
                .frame(width: 0, height: 0)
                .onChange(of: context.date) { _ in
                    let newIndex = engine.state(at: currentTimeMs()).activeLineIndex
                    if newIndex != activeLineIndex {
                        activeLineIndex = newIndex
                    }
                }
        }
    }

    @ViewBuilder
    private func lineRow(for line: LyricsLine) -> some View {
        if line.lineIndex == activeLineIndex {
            LyricsCanvasView(engine: engine, layout: layout, lineIndex: line.lineIndex, currentTimeMs: currentTimeMs)
                .frame(height: 44)
        } else {
            staticText(for: line)
                .frame(height: 44)
        }
    }

    /// Texto estático precomputado (los Text ya existen en layout, creados
    /// una sola vez al cargar la letra) — cero costo por frame para las
    /// líneas que no están sonando.
    private func staticText(for line: LyricsLine) -> some View {
        let isPast = (activeLineIndex ?? -1) > line.lineIndex
        let entries = layout.tokensByLine[line.lineIndex] ?? []
        return HStack(spacing: layout.wordSpacing) {
            ForEach(entries, id: \.token.id) { entry in
                entry.text
            }
        }
        .opacity(isPast ? 0.35 : 0.55)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, layout.leftInset)
    }
}