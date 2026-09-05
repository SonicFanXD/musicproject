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
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(UIColor.systemBackground).opacity(0.92), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                // Título personalizado consistente con la app
                ToolbarItem(placement: .principal) {
                    Text("Registros")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.75)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .accessibilityLabel("Registros")
                }

                ToolbarItem(placement: .topBarLeading) {
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
                            .frame(width: 44, height: 44) // Bigger invisible touch target
                            .contentShape(Rectangle())
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") {
                        dismiss()
                    }
                    .frame(width: 44, height: 44) // Bigger invisible touch target
                    .contentShape(Rectangle())
                }
            }
            .searchable(
                text: $searchText,
                prompt: "Buscar en logs"
            )
            .sheet(item: $shareItem) { item in
                ActivityShareSheet(items: [item.url])
            }
            .onReceive(timer) { _ in
                refreshTick += 1 // fuerza re-render para logs en vivo
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

    private var lastLogTime: String {
        guard let last = AppLog.entries.last else { return "—" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: last.date)
    }

    private func statCard(icon: String, title: String, value: String, color: Color) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)

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
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        }
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

    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? .white : .secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.accentColor)
                    } else {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.secondary.opacity(0.12))
                    }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Log Entries List
    private var logEntriesList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if filteredEntries.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundStyle(.tertiary)

                        Text("No hay logs que coincidan")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ForEach(filteredEntries) { entry in
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
        HStack(alignment: .top, spacing: 10) {
            // Level indicator
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.level)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(levelColor(for: entry.level))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background {
                        Capsule()
                            .fill(levelColor(for: entry.level).opacity(0.15))
                    }

                Text(entry.category.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 80, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.message)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(4)

                HStack(spacing: 8) {
                    Text(formatDate(entry.date))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    if let duration = entry.duration {
                        Text("· \(String(format: "%.1f", duration * 1000))ms")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
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
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}