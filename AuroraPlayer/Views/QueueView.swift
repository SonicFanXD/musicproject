import SwiftUI
import UIKit

struct QueueView: View {
    @ObservedObject var audioEngine: AudioEngine
    // ✅ E3.4: el menú de "A continuación" incluye "Me gusta", así que la vista
    // necesita el servicio para leer `isLiked(song)` (misma fuente de verdad que
    // ContentView / LibraryDetailViews / PlaylistsView). Se observa para que la
    // etiqueta del corazón siga al estado real.
    @ObservedObject var fileAccessService: FileAccessService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: QueueTab = .nextUp
    // ✅ E3.2: modo edición EXPLÍCITO para el arrastre de "En cola". Con el menú
    // contextual en cada fila, el toque sostenido abre el menú y el arrastre
    // (que sin edición necesita ESE mismo gesto) no llega a arrancar. En edición
    // aparecen los tiradores y arrastrar funciona sin competir con el menú.
    @State private var editMode: EditMode = .inactive
    // ✅ E3: `editableQueue` ELIMINADO. Antes esta vista editaba una copia local
    // y al aplicarla reescribía el orden COMPLETO del álbum/playlist
    // (reorderNextUpQueue → rebuildPlaylistFromQueue): reordenar la cola del
    // usuario le cambiaba el álbum. Ahora la cola se lee y se edita DIRECTAMENTE
    // sobre `audioEngine.manualQueue` (moveInQueue/removeFromQueue/clearQueue) y
    // el resto del orden solo se MUESTRA, nunca se toca.
    // ✅ B2: disparador de la animación de las barras del ecualizador. Vive en
    // @State (y no directamente en `audioEngine.isPlaying`) porque es lo que
    // hace que la animación `repeatForever` ARRANQUE al reanudar y se DESTRUYA
    // al pausar: al aparecer la versión estática se rearma a false.
    @State private var barsExpanded = false
    // ✅ C2: escala real del dispositivo (el iPhone 8 Plus es @3x). Se lee del
    // entorno de SwiftUI (la API de pantalla global está en desuso).
    @Environment(\.displayScale) private var displayScale

    enum QueueTab: String, CaseIterable {
        case nextUp
        case history

        var localizedTitle: String {
            switch self {
            case .nextUp: return Localization.localized("queue.nextUp")
            case .history: return Localization.localized("queue.history")
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                VStack(spacing: 0) {
                    // ✅ AURORA DESIGN: header de sheet del sistema en su propia fila,
                    // por delante del selector de pestañas. Mide 44pt, exactamente lo
                    // que medía la barra a la que sustituye, así que el tabSelector se
                    // queda donde estaba y su spacing no cambia.
                    AuroraSheetHeader(
                        title: Localization.localized("queue.title"),
                        onClose: { dismiss() },
                        titleColor: AppTheme.accent,
                        trailing: AnyView(headerTrailingButtons)
                    )

                    tabSelector

                    Divider().background(Color.secondary.opacity(0.2))

                    // ✅ FIX iOS 16: era ScrollView → .swipeActions y .onMove eran
                    // inertes (solo funcionan en List). Al no poder eliminar la
                    // canción con swipe, la basura "clear queue" era la única vía.
                    List {
                        switch selectedTab {
                        case .nextUp: nextUpContent
                        case .history: historyContent
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.hidden)
                    // ✅ E3.2: el modo edición lo controla el botón "Editar" de la
                    // cabecera de "En cola" (es la sección con .onMove).
                    .environment(\.editMode, $editMode)
                }
            }
            // ✅ AURORA DESIGN: el toolbar se sustituye por el header del sistema.
            // La barra se oculta en vez de dejarse vacía: así el header ocupa SU
            // altura (44pt) y no se suma un segundo bloque de 44pt encima.
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    /// ✅ AURORA DESIGN: los botones que vivían en el toolbar pasan al slot trailing
    /// del header del sistema con sus MISMAS acciones.
    /// ✅ E3.1: aquí vivía además una papelera (limpiar la cola). Se retira porque
    /// duplicaba el "Limpiar" del header de la sección "En cola" y su alcance era
    /// ambiguo (¿la cola manual?, ¿todo?). Queda solo "Listo". Efecto lateral
    /// bueno: el trailing vuelve a medir lo mismo que el chevron de la izquierda
    /// (44pt), así que el título ya no se desplaza ~24pt y vuelve a estar centrado.
    private var headerTrailingButtons: some View {
        HStack(spacing: 8) {
            Button(Localization.localized("actions.done")) { dismiss() }
                .foregroundStyle(AppTheme.accent)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
    }

    private var tabSelector: some View {
        HStack(spacing: 6) {
            ForEach(QueueTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab == .nextUp ? "list.number" : "clock.arrow.circlepath")
                            .font(.system(size: 12, weight: .semibold))
                        Text(tab.localizedTitle)
                            .font(.system(size: 14, weight: selectedTab == tab ? .semibold : .medium, design: .rounded))
                    }
                    .foregroundStyle(selectedTab == tab ? .white : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background {
                        if selectedTab == tab {
                            Capsule().fill(AppTheme.accentGradient)
                                .shadow(color: AppTheme.accent.opacity(0.3), radius: 6, x: 0, y: 3)
                        } else {
                            // ✅ 60fps: color OPACO (sin blur) para el selector
                            Capsule().fill(Color(UIColor.secondarySystemBackground))
                        }
                    }
                }
                .buttonStyle(PressableButtonStyle(scale: 0.95))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    @ViewBuilder
    private var nextUpContent: some View {
        Section {
            if let current = audioEngine.currentSong {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Localization.localized("queue.nowPlaying"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        artworkMiniature(current.artwork, size: 48, corner: 10)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(current.title)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.accentGradient).lineLimit(1)
                            Text(current.displaySubtitle)
                                .font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                        }

                        Spacer()

                        // ✅ B2 (batería): la versión animada y la estática son
                        // subárboles DISTINTOS a propósito. `.animation(nil)` no
                        // garantiza detener un `repeatForever` ya en curso (si
                        // el valor animado no vuelve a cambiar, la transacción
                        // no llega y la oscilación sigue viva en segundo plano).
                        // Al pausar se descarta el subárbol entero y con él la
                        // animación; al reanudar nace limpia desde el reposo.
                        Group {
                            if audioEngine.isPlaying {
                                equalizerBars(animated: true)
                            } else {
                                equalizerBars(animated: false)
                            }
                        }
                    }
                    .padding(12)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AppTheme.accentGradient(opacity: 0.1))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(AppTheme.accent.opacity(0.25), lineWidth: 1)
                    }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }

            // ---- 2. "En cola": la cola MANUAL del usuario. Es la ÚNICA sección
            // editable (arrastre, swipe, menú) y edita `audioEngine.manualQueue`
            // directamente: nunca más el orden del álbum.
            // ✅ E3.3: el `if` envuelve SOLO la cabecera. El ForEach vuelve a ser
            // hijo DIRECTO del Section: dentro de un condicional, la List no lo
            // reconoce como hijo editable (ni tiradores de arrastre ni swipe).
            if !audioEngine.manualQueue.isEmpty {
                manualQueueHeader
            }

            // ✅ FIX iOS 16: las filas DEBEN ser hijas directas del Section para que
            // .swipeActions/.onMove/.onDelete funcionen (anidadas en un VStack son inertes).
            // ✅ PERF: identidad por OFFSET (enumerated, id: \.offset) y NO por
            // Song.id: la cola manual admite la misma canción dos veces
            // (addToQueue no deduplica) y un ForEach con ids duplicados
            // produce diff impredecible (filas que saltan/desaparecen) y
            // el warning "AttributeGraph: cycle detected" en runtime.
            // NOTA: el valor del par (position, song) se captura por VALOR, así que
            // ninguna edición puede dejar un índice fuera de rango.
            ForEach(Array(audioEngine.manualQueue.enumerated()), id: \.offset) { position, song in
                queueSongRow(song) {
                    // ✅ E3: el toque reproduce LA COLA como contexto. La
                    // llamada antigua construía [canción actual] + cola entera
                    // y con eso reescribía el orden del álbum: el bug de diseño.
                    audioEngine.play(song: song, from: audioEngine.manualQueue)
                }
                // ✅ E3.2: ORDEN de modificadores. El `.swipeActions` va el
                // ÚLTIMO (por FUERA del menú contextual): la List necesita ver
                // el trait de swipe en el modificador más externo de la fila.
                .contextMenu {
                    Button {
                        Haptics.light()
                        audioEngine.play(song: song, from: audioEngine.manualQueue)
                    } label: {
                        Label(Localization.localized("context.playNow"), systemImage: "play.circle.fill")
                    }
                    Button {
                        Haptics.light()
                        audioEngine.playNext(song)
                    } label: {
                        Label(Localization.localized("context.playNext"), systemImage: "text.line.first.and.arrowtriangle.forward")
                    }
                    Button {
                        Haptics.light()
                        // Por ÍNDICE y no por id: la misma canción puede estar
                        // dos veces en la cola.
                        audioEngine.removeFromQueue(at: position)
                    } label: {
                        Label(Localization.localized("queue.removeItem"), systemImage: "trash")
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Haptics.light()
                        audioEngine.removeFromQueue(at: position)
                    } label: {
                        Label(Localization.localized("queue.remove"), systemImage: "trash")
                    }
                }
            }
            .onMove { from, to in
                Haptics.light()
                moveManualQueue(from: from, to: to)
            }
            // ✅ E3.3: `.onDelete` es el trait que la List usa para el borrado del
            // modo edición (los controles rojos). Su ausencia es la razón de que al
            // pulsar "Editar" no apareciera ninguna acción de borrado.
            .onDelete { offsets in
                Haptics.light()
                deleteFromManualQueue(offsets)
            }

            // ---- 3. "A continuación": el resto del orden del álbum/playlist.
            // SOLO LECTURA a propósito: sin swipe, sin arrastre y sin menú.
            if !upcomingFromOrder.isEmpty {
                Text(Localization.localized("queue.upNext"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    // ✅ E3.1: `top` era 16 (valor NUEVO). Se alinea con el inset de
                    // header que ya usa la vista (12), para no introducir medidas.
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))

                ForEach(Array(upcomingFromOrder.enumerated()), id: \.offset) { _, song in
                    queueSongRow(song) {
                        // Contexto = el orden del álbum/lista (igual que tocar una
                        // fila del álbum). La cola manual no se pierde: el motor le
                        // sigue dando prioridad al calcular la siguiente.
                        audioEngine.play(song: song, from: audioEngine.playbackQueue)
                    }
                    // ✅ E3.4: control INDIRECTO sobre el resto del orden. La sección
                    // sigue siendo solo lectura (sin swipe, sin arrastre, sin
                    // onMove/onDelete): desde aquí se MUEVEN canciones a la cola
                    // manual, y es en "En cola" donde se editan.
                    // Mismas claves e iconos que los menús de ContentView,
                    // LibraryDetailViews y PlaylistsView (no se inventa ninguno).
                    .contextMenu {
                        Button {
                            Haptics.light()
                            // Mismo comportamiento que el toque de la fila.
                            audioEngine.play(song: song, from: audioEngine.playbackQueue)
                        } label: {
                            Label(Localization.localized("context.playNow"), systemImage: "play.circle.fill")
                        }
                        Button {
                            Haptics.light()
                            // Al PRINCIPIO de la cola manual: suena en cuanto acabe
                            // la canción actual (y desaloja lo ya encolado, E1.5).
                            audioEngine.playNext(song)
                        } label: {
                            Label(Localization.localized("context.playNext"), systemImage: "text.line.first.and.arrowtriangle.forward")
                        }
                        Button {
                            Haptics.light()
                            // Al FINAL de la cola manual.
                            audioEngine.addToQueue(song)
                        } label: {
                            Label(Localization.localized("actions.addToQueue"), systemImage: "text.badge.plus")
                        }
                        Button {
                            Haptics.light()
                            fileAccessService.toggleLike(song)
                        } label: {
                            Label(
                                Localization.localized(fileAccessService.isLiked(song) ? "actions.unlike" : "actions.like"),
                                systemImage: fileAccessService.isLiked(song) ? "heart.slash" : "heart"
                            )
                        }
                    }
                }
            }

            // Estado vacío: solo si no hay NADA que mostrar (ni cola ni resto).
            if audioEngine.manualQueue.isEmpty && upcomingFromOrder.isEmpty {
                emptyState(icon: "music.note.list", title: Localization.localized("queue.emptyQueue"), message: Localization.localized("queue.emptyQueueMessage"))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
        }
    }

    /// ✅ E3 — "A continuación" = el resto del orden del álbum/playlist, SIN la
    /// cola manual. El motor publica `nextUpQueue` como [cola manual] + [resto del
    /// orden], así que se descartan las primeras `manualQueue.count` entradas.
    /// Nota: `nextUpQueue` es la VENTANA de 10 que fija el motor (el orden interno
    /// completo es privado) → la sección muestra como máximo 10 - cola manual.
    private var upcomingFromOrder: [Song] {
        let queued = min(audioEngine.manualQueue.count, audioEngine.nextUpQueue.count)
        return Array(audioEngine.nextUpQueue.dropFirst(queued))
    }

    /// Cabecera de "En cola" con su botón "Limpiar". Limpia SOLO la cola manual:
    /// el álbum en curso no se toca (eso era lo que hacía el clearNextUpQueue viejo).
    private var manualQueueHeader: some View {
        HStack(spacing: 8) {
            Text(Localization.localized("queue.inQueue"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            // ✅ E3.2: "Limpiar" se OCULTA mientras se edita (en edición la acción
            // principal es arrastrar; vaciar la cola ahí sería un accidente).
            if editMode != .active {
                Button {
                    Haptics.light()
                    audioEngine.clearQueue()
                } label: {
                    Text(Localization.localized("queue.clear"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }
                .buttonStyle(.plain)
            }

            // ✅ E3.2: alterna el modo edición. Mismo lenguaje que "Limpiar"
            // (texto accent, sin fondo ni cápsula).
            Button {
                Haptics.light()
                withAnimation(.easeInOut(duration: 0.2)) {
                    editMode = editMode == .active ? .inactive : .active
                }
            } label: {
                Text(Localization.localized(editMode == .active ? "queue.doneEditing" : "queue.edit"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
            }
            .buttonStyle(.plain)
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))
    }

    /// ✅ E3: traduce el contrato de SwiftUI (`.onMove`: IndexSet + índice de
    /// inserción referido a la lista SIN quitar aún el elemento) al del motor
    /// (`remove(at:)` + `insert(at:)`, con el índice YA corregido). Sin la
    /// corrección, arrastrar hacia abajo dejaba la fila una posición por delante.
    /// SwiftUI entrega solo un índice por arrastre (no usamos modo edición
    /// múltiple), así que basta con el primero.
    private func moveManualQueue(from source: IndexSet, to destination: Int) {
        guard let first = source.first else { return }
        let engineDestination = destination > first ? destination - 1 : destination
        audioEngine.moveInQueue(from: first, to: engineDestination)
    }

    /// ✅ E3.3: borrado por lotes del modo edición. Los índices llegan en orden
    /// ascendente; se recorre al revés para que cada `remove(at:)` no desplace a
    /// los que quedan por borrar.
    private func deleteFromManualQueue(_ offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            audioEngine.removeFromQueue(at: index)
        }
    }

    @ViewBuilder
    private var historyContent: some View {
        Section {
            if audioEngine.playHistory.isEmpty {
                emptyState(icon: "clock.arrow.circlepath", title: Localization.localized("queue.emptyHistory"), message: Localization.localized("queue.emptyQueueMessage"))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Localization.localized("queue.historyTitle"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)

                    // ✅ PERF: el historial PUEDE repetir pista (insert sin
                    // desduplicar, playHistory.insert(at: 0)) → identidad por
                    // posición (offset), única incluso con la misma canción dos
                    // veces; \.element.id producía ids duplicados.
                    ForEach(Array(audioEngine.playHistory.enumerated()), id: \.offset) { index, song in
                        historySongRow(song, index: index)
                    }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
        }
    }

    /// ✅ E3: el diseño de la fila lo COMPARTEN "En cola" (editable) y
    /// "A continuación" (solo lectura); lo que cambia es el toque, que decide la
    /// sección que la usa. Antes el toque reconstruía la lista ([canción actual]
    /// + cola) y con ella reescribía el orden del álbum: ese era el bug de diseño.
    private func queueSongRow(_ song: Song, onTap: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            onTap()
        } label: {
            HStack(spacing: 14) {
                artworkMiniature(song.artwork, size: 48, corner: 12)

                VStack(alignment: .leading, spacing: 4) {
                    Text(song.title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary).lineLimit(1)
                    Text(song.displaySubtitle)
                        .font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                }

                Spacer()

                Text(formatDuration(song.duration))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(UIColor.secondarySystemBackground).opacity(0.6))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98))
    }

    private func historySongRow(_ song: Song, index: Int) -> some View {
        Button {
            Haptics.light()
            audioEngine.playFromHistory(song)
        } label: {
            HStack(spacing: 14) {
                artworkMiniature(song.artwork, size: 48, corner: 12)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(4)
                            .background {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [AppTheme.accent, AppTheme.accent.opacity(0.85)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing
                                        )
                                    )
                            }
                            .offset(x: 4, y: 4)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(song.title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary).lineLimit(1)
                    Text(song.displaySubtitle)
                        .font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                }

                Spacer()

                Image(systemName: "play.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(AppTheme.accentGradient)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(UIColor.secondarySystemBackground).opacity(0.6))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98))
    }

    /// ✅ B2: tres barras de ecualizador. Con `animated == false` se renderiza la
    /// versión ESTÁTICA, sin un solo modificador de animación: no queda nada que
    /// cancelar (el reposo mostrado, 6 pt, es el mismo punto de partida de la
    /// oscilación, así que reanudar no da ningún salto visual).
    @ViewBuilder
    private func equalizerBars(animated: Bool) -> some View {
        HStack(spacing: 2.5) {
            ForEach(0..<3, id: \.self) { bar in
                if animated {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(equalizerBarGradient)
                        .frame(width: 3, height: barsExpanded ? (bar % 2 == 0 ? 14 : 9) : 6)
                        .animation(
                            Animation.easeInOut(duration: 0.45 + Double(bar) * 0.12).repeatForever(autoreverses: true),
                            value: barsExpanded
                        )
                } else {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(equalizerBarGradient)
                        .frame(width: 3, height: 6)
                }
            }
        }
        .onAppear { barsExpanded = animated }
    }

    private var equalizerBarGradient: LinearGradient {
        LinearGradient(
            colors: [AppTheme.accent, AppTheme.accent.opacity(0.5)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // ✅ Componente reutilizable para miniaturas de artwork
    @ViewBuilder
    private func artworkMiniature(_ artwork: UIImage?, size: CGFloat, corner: CGFloat) -> some View {
        if let artwork = artwork {
            // ✅ ANTI-JETSAM: reescalar al tamaño real (la fuente completa de
            // 768px no debe retenerse en filas de 48pt → mucho menos RAM).
            // ✅ C2 (nitidez): el factor era ×2 fijo, pero el iPhone 8 Plus es
            // @3x, así que la miniatura de 96px se dibujaba a 144px y se veía
            // blanda. Se pide en píxeles REALES con la escala del dispositivo
            // (la del entorno de SwiftUI, no la API de pantalla global).
            let scale = max(displayScale, 1)
            Image(uiImage: AppTheme.thumbnail(from: artwork, size: CGSize(width: size * scale, height: size * scale)))
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        } else {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.32))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
        }
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.5))
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}