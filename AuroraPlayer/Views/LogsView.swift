import SwiftUI

struct LogsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries = AppLog.entries

    var body: some View {
        NavigationStack {
            List(entries.reversed()) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(entry.level).font(.caption.bold()).foregroundStyle(color(for: entry.level))
                        Text(entry.category.rawValue.uppercased()).font(.caption.monospaced()).foregroundStyle(.secondary)
                        Spacer()
                        Text(entry.date, format: .dateTime.hour().minute().second()).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Text(entry.message).font(.footnote).textSelection(.enabled)
                }
                .padding(.vertical, 2)
            }
            .overlay { if entries.isEmpty { ContentUnavailableView("Sin registros", systemImage: "text.alignleft") } }
            .navigationTitle("Registros")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cerrar") { dismiss() } }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { entries = AppLog.entries } label: { Image(systemName: "arrow.clockwise") }
                    Button(role: .destructive) { AppLog.clearEntries(); entries = [] } label: { Image(systemName: "trash") }
                }
            }
        }
    }

    private func color(for level: String) -> Color {
        level == "ERROR" ? .red : level == "DEBUG" ? .secondary : .accentColor
    }
}
