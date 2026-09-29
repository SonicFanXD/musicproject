import SwiftUI
import UIKit

// MARK: - Share Sheet (UIKit wrapper)
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Wrapper para presentar una URL compartible en .sheet(item:)
struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct LogsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategory: LogCategory? = nil
    @State private var showOnlyErrors = false
    @State private var searchText = ""
    @State private var shareItem: ShareItem? = nil
    @State private var copiedToast = false

    // Timer para refrescar la vista en vivo mientras se registran nuevos eventos
    let timer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()
    @State private var refreshTick = 0
    /// ✅ Última entrada vista: evita re-renderizar cuando no ha llegado nada.
    @State private var lastSeenEntryID: UUID?

    // ✅ Mensajes expandibles: ids de entradas con mensaje desplegado
    @State private var expandedIDs = Set<UUID>()

    // ✅ AURORA DESIGN: el buscador es INLINE (como el de ContentView). Sin
    // NavigationBar no hay dónde vivir para .searchable, así que el foco lo
    // gestiona la vista y poder reenfocar al limpiar.
    @FocusState private var searchFieldFocused: Bool

    private var filteredEntries: [InAppLogEntry] {
        var entries = AppLog.entries

        if let category = selectedCategory {
            entries = entries.filter { $0.category == category }
        }

        if showOnlyErrors {
            entries = entries.filter { $0.level == "ERROR" }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            entries = entries.filter { $0.message.lowercased().contains(query) }
        }

        return entries.reversed()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                VStack(spacing: 0) {
                    // ✅ AURORA DESIGN: el toolbar se sustituye por el header del
                    // sistema. El menú de diagnóstico (compartir/copiar/borrar)
                    // pasa al NUEVO slot `leading`: es la única pantalla con menú
                    // a la izquierda, así que el chevron.down de cierre se oculta
                    // y su hueco de 44pt lo ocupa el menú (el título no se mueve).
                    AuroraSheetHeader(
                        title: "Registros",
                        leading: AnyView(diagnosticsMenu),
                        onClose: { dismiss() },
                        titleColor: AppTheme.accent,
                        trailing: AnyView(doneButton)
                    )

                    // ✅ AURORA DESIGN: buscador INLINE (magnifyingglass + campo +
                    // clear) en vez de .searchable: escribe el MISMO `searchText`,
                    // así que `filteredEntries` (categoría, errores y texto) no
                    // cambia ni un ápice.
                    searchFieldInline
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    // Stats summary
                    statsBar

                    // Category filter
                    categoryFilter

                    // Log entries list
                    logEntriesList
                }

                // Toast de confirmación de copia
                if copiedToast {
                    VStack {
                        Spacer()
                        Label("Diagnóstico copiado", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background {
                                Capsule().fill(Color.black.opacity(0.8))
                            }
                            .padding(.bottom, 30)
                    }
                    .transition(.opacity)
                }
            }
            // ✅ AURORA DESIGN: el toolbar se sustituye por el header del sistema.
            // La barra se OCULTA: así el header ocupa SU altura (44pt) en lugar de
            // sumarse un segundo bloque de 44pt encima.
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $shareItem) { item in
                ActivityShareSheet(items: [item.url])
            }
            .onReceive(timer) { _ in
                // ✅ BATERÍA: repinta solo si de verdad entró un log nuevo (antes
                // forzaba un re-render del árbol cada 2 s aunque no hubiera nada
                // que mostrar). Se compara por id y no por número de entradas
                // porque el buffer tiene un tope: al llenarse, el contador se
                // queda fijo aunque sigan entrando líneas.
                let newest = AppLog.entries.last?.id
                guard newest != lastSeenEntryID else { return }
                lastSeenEntryID = newest
                refreshTick += 1
            }
        }
    }

    // MARK: - Exportar / Copiar

    private func shareDiagnostics() {
        if let url = AppLog.writeExportFile() {
            shareItem = ShareItem(url: url)
        }
    }

    private func copyDiagnostics() {
        AppLog.copyReportToClipboard()
        withAnimation {
            copiedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation {
                copiedToast = false
            }
        }
    }

    // MARK: - Header del sistema (menú + cerrar)

    /// ✅ AURORA DESIGN: el menú de diagnóstico que vivía en
    /// `navigationBarLeading`, ahora en el slot `leading` del header. Misma
    /// altura que el hueco del chevron para no descentrar el título.
    private var diagnosticsMenu: some View {
        Menu {
            Button {
                shareDiagnostics()
            } label: {
                Label("Compartir / Guardar diagnóstico", systemImage: "square.and.arrow.up")
            }

            Button {
                copyDiagnostics()
            } label: {
                Label("Copiar diagnóstico completo", systemImage: "doc.on.doc")
            }

            Divider()

            Button(role: .destructive) {
                AppLog.clearEntries()
            } label: {
                Label("Borrar registros", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 44, height: 44) // Bigger invisible touch target
                .contentShape(Rectangle())
        }
    }

    /// ✅ El "Listo" que vivía en `navigationBarTrailing`, ahora en el slot
    /// `trailing` del header. Mide 44pt, lo mismo que el hueco fantasma, así que
    /// el título sigue centrado.
    private var doneButton: some View {
        Button(Localization.localized("actions.done")) {
            dismiss()
        }
        .foregroundStyle(AppTheme.accent)
        .frame(width: 44, height: 44) // Bigger invisible touch target
        .contentShape(Rectangle())
    }

    /// ✅ Buscador INLINE con look nativo (lupa + campo + clear), calcado del de
    /// ContentView: sustituye al .searchable del NavigationStack sin pelear con
    /// la barra (ya oculta). Escribe el mismo `searchText` de siempre.
    private var searchFieldInline: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Buscar en logs", text: $searchText)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($searchFieldFocused)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        // ✅ AURORA DESIGN: superficie flat del sistema (radio .md, borde sutil,
        // sin sombra) — el campo vive sobre el fondo, cero blur.
        .auroraCard(radius: AuroraRadius.md, style: .flat, withShadow: false)
        .contentShape(Rectangle())
        .onTapGesture {
            searchFieldFocused = true
        }
    }

    // MARK: - Stats Bar (useful diagnostics at a glance)
    private var statsBar: some View {
        HStack(spacing: 12) {
            statCard(
                icon: "doc.text",
                title: "Total",
                value: "\(AppLog.entries.count)",
                color: .blue
            )

            statCard(
                icon: "xmark.circle.fill",
                title: "Errores",
                value: "\(AppLog.errorCount)",
                color: .red
            )

            statCard(
                icon: "exclamationmark.triangle.fill",
                title: "Advertencias",
                value: "\(AppLog.warningCount)",
                color: .orange
            )

            statCard(
                icon: "clock.fill",
                title: "Último",
                value: lastLogTime,
                color: .green
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// ✅ Un único DateFormatter reutilizado: crear uno por fila y por render era
    /// con diferencia lo más caro de la lista (inicializar DateFormatter cuesta
    /// órdenes de magnitud más que formatear con uno ya creado).
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private var lastLogTime: String {
        guard let last = AppLog.entries.last else { return "—" }
        return Self.timeFormatter.string(from: last.date)
    }

    private func statCard(icon: String, title: String, value: String, color: Color) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                // ✅ Disco con micro-gradiente del MISMO tono que el dato: mismo
                // lenguaje visual que los iconos de sección de Ajustes.
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 18, height: 18)
                    .background {
                        Circle().fill(
                            LinearGradient(
                                colors: [color.opacity(0.22), color.opacity(0.08)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                    }

                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        // ✅ AURORA DESIGN: stat card → card del sistema, radio .sm exacto (14) y
        // sin sombra (no tenía). Vidrio reactivo a "Reducir transparencia".
        .auroraCard(radius: AuroraRadius.sm, style: .glass, withBorder: true, withShadow: false)
    }

    // MARK: - Category Filter
    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(title: "Todos", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }

                ForEach(LogCategory.allCases, id: \.self) { category in
                    filterChip(title: category.displayName, isSelected: selectedCategory == category) {
                        selectedCategory = category
                    }
                }

                filterChip(title: "Solo errores", isSelected: showOnlyErrors) {
                    showOnlyErrors.toggle()
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
    }

    /// ✅ Superficie con TEXTO BLANCO encima: el secundario conserva su tono pero
    /// ancla su brillo al del primario si la diferencia es grande, para que la
    /// pastilla seleccionada no quede a medio legible con paletas de contraste.
    private func textSafeAccentGradient() -> LinearGradient {
        let primary = AppTheme.accent
        // ⚠️ El secundario solo es válido con el modo "acento desde portada"
        // activo: si no, sería el de una canción anterior (hue equivocado).
        let manager = ThemeManager.shared
        let candidate = manager.accentFromArtwork ? manager.artworkSecondaryColor : nil
        let secondary = candidate ?? primary.opacity(0.85)
        var h1: CGFloat = 0, s1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 1
        var h2: CGFloat = 0, s2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 1
        var stop = secondary
        if UIColor(primary).getHue(&h1, saturation: &s1, brightness: &b1, alpha: &a1),
           UIColor(secondary).getHue(&h2, saturation: &s2, brightness: &b2, alpha: &a2),
           abs(b1 - b2) > 0.3 {
            stop = Color(UIColor(hue: h2, saturation: s2, brightness: b1, alpha: a2))
        }
        return LinearGradient(
            colors: [primary, stop],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? .white : .secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                // ✅ Selección ANIMADA: el fondo ya no cambia de tipo de vista entre
                // estados (antes saltaba); ahora se funde el relleno de acento sobre
                // el material, con una transición suave de 0,22 s.
                .background {
                    ZStack {
                        // ✅ AURORA DESIGN: vidrio del sistema (reactivo a "Reducir transparencia").
                        Capsule().auroraGlass()

                        Capsule()
                            .fill(textSafeAccentGradient())
                            .shadow(color: AppTheme.accent.opacity(0.3), radius: 6, x: 0, y: 3)
                            .opacity(isSelected ? 1 : 0)
                    }
                }
                .animation(.easeInOut(duration: 0.22), value: isSelected)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.95))
    }

    // MARK: - Log Entries List
    private var logEntriesList: some View {
        // ✅ Se filtra UNA vez por render (antes el filtro y el reverso se
        // calculaban dos veces: para el isEmpty y para el ForEach).
        let entries = filteredEntries

        return ScrollView {
            LazyVStack(spacing: 8) {
                if entries.isEmpty {
                    VStack(spacing: 14) {
                        // ✅ Estado vacío con el acento de la app sobre un disco suave
                        // (antes era un icono gris plano).
                        ZStack {
                            Circle()
                                .fill(AppTheme.accentGradient(opacity: 0.1))
                                .frame(width: 72, height: 72)

                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 28, weight: .medium))
                                .foregroundStyle(AppTheme.accentGradient)
                        }

                        Text("No hay logs que coincidan")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)

                        Text("Prueba con otra categoría o borra el filtro de búsqueda")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ForEach(entries) { entry in
                        logEntryRow(entry: entry)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }

    private func logEntryRow(entry: InAppLogEntry) -> some View {
        let isExpanded = expandedIDs.contains(entry.id)

        return HStack(alignment: .top, spacing: 12) {
            // ✅ Columna izquierda: nivel con icono + categoría a color
            VStack(alignment: .leading, spacing: 6) {
                // Nivel + icono (ERROR/WARN/INFO/DEBUG) con material de vidrio
                Text("\(levelIcon(for: entry.level)) \(entry.level)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(levelColor(for: entry.level))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        Capsule()
                            .fill(levelColor(for: entry.level).opacity(0.15))
                            .overlay {
                                Capsule()
                                    .strokeBorder(levelColor(for: entry.level).opacity(0.12), lineWidth: 0.5)
                            }
                    }

                Text(entry.category.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(entry.category.tintColor)
                    .lineLimit(1)
            }
            .frame(width: 96, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                // ✅ Mensaje expandible: 3 líneas por defecto, tap para desplegar
                // ✅ Jerarquía: el mensaje sube a 14 (es el contenido a leer) y
                // baja a regular; la metaduría (nivel, categoría, hora) sigue en
                // 10-11 pt para que no compita con él.
                Text(entry.message)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(isExpanded ? nil : 3)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.2)) {
                            if isExpanded {
                                expandedIDs.remove(entry.id)
                            } else {
                                expandedIDs.insert(entry.id)
                            }
                        }
                    }
                    .accessibilityHint("Toca para expandir o colapsar el mensaje")

                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)

                    Text(formatDate(entry.date))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)

                    if let duration = entry.duration {
                        Spacer(minLength: 8)
                        // ✅ Pill de duración (estilo spec sheet, monospaced)
                        Text(String(format: "%.1f ms", duration * 1000))
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(entry.category.tintColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background {
                                Capsule().fill(entry.category.tintColor.opacity(0.12))
                            }
                    }
                }
            }

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        // ✅ AURORA DESIGN: fila de lista larga (LazyVStack) → superficie FLAT del
        // sistema: cero blur por fila al scrollear en el A11 (cada material es un
        // pase offscreen por frame). Radio .md (18, +2pt desde el 16 original) para
        // alinearse con las filas del resto de la app; el texto sobre gris plano se
        // lee mejor. El stat card de arriba sigue en glass (ahí sí hay vidrio).
        .auroraCard(radius: AuroraRadius.md, style: .flat, withShadow: false)
        // ✅ Raya lateral de categoría: jerarquía visual instantánea
        .overlay(alignment: .leading) {
            Capsule()
                .fill(entry.category.tintColor.opacity(0.65))
                .frame(width: 2.5)
                .padding(.vertical, 10)
                .padding(.leading, 2)
                .allowsHitTesting(false)
        }
    }

    /// Icono por nivel (jerarquía visual más rápida que leer el texto).
    private func levelIcon(for level: String) -> String {
        switch level {
        case "ERROR": return "xmark.octagon.fill"
        case "WARN": return "exclamationmark.triangle.fill"
        case "INFO": return "info.circle.fill"
        case "DEBUG": return "ladybug.fill"
        default: return "circle.fill"
        }
    }

    private func levelColor(for level: String) -> Color {
        switch level {
        case "ERROR": return .red
        case "WARN": return .orange
        case "INFO": return .blue
        case "DEBUG": return .gray
        default: return .primary
        }
    }

    private func formatDate(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }
}