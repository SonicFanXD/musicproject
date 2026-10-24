import SwiftUI
import UIKit

// ═══════════════════════════════════════════════════════════════════════════
// LOG ENTRY ROW — una fila del registro como VIEW VALOR (Equatable).
//
// POR QUÉ EXISTE (Prioridad 5, tanda 4):
// `logEntriesList` ya usaba `LazyVStack`, pero las filas eran funciones dentro
// de `LogsView`: el `Timer` de 2 s (y cada tecla del buscador, cada cambio de
// filtro, cada expansión de un mensaje) reevaluaba el body del padre y, con él,
// las ~50-300 filas del buffer. Cada fila pinta un chip de nivel, un color de
// categoría, el mensaje con `lineLimit` variable y una hora formateada, así que
// ese trabajo se nota al escribir en el campo de búsqueda.
//
// Con la fila aislada + `.equatable()`:
//  · El timer de refresco solo repinta la fila NUEVA (las demás devuelven
//    `false` en `==` y SwiftUI ni evalúa su body).
//  · Expandir un mensaje repinta esa fila y ninguna más.
//
// ✅ El color del hairline de categoría y el relleno del chip salen de
// `levelColor`/`tintColor`: no hay blur ni material por fila (superficie flat),
// que era el objetivo de batería en el A11.
// ═══════════════════════════════════════════════════════════════════════════

struct LogEntryRow: View, Equatable {
    let entry: InAppLogEntry
    let isExpanded: Bool
    let onToggleExpanded: () -> Void

    /// ✅ Igualdad = "¿pinta lo mismo?". `InAppLogEntry` es inmutable en el
    /// buffer (nunca se edita in situ; borrar y volver a entrar crea otra
    /// entrada con otro `id`), así que comparar el `id` + el estado de
    /// expansión es exacto y O(1). El closure se ignora a propósito.
    static func == (lhs: LogEntryRow, rhs: LogEntryRow) -> Bool {
        lhs.entry.id == rhs.entry.id && lhs.isExpanded == rhs.isExpanded
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // ✅ Columna izquierda: nivel con icono + categoría a color
            VStack(alignment: .leading, spacing: 6) {
                Text("\(Self.levelIcon(for: entry.level)) \(entry.level)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Self.levelColor(for: entry.level))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        Capsule()
                            .fill(Self.levelColor(for: entry.level).opacity(0.15))
                            .overlay {
                                Capsule()
                                    .strokeBorder(Self.levelColor(for: entry.level).opacity(0.12), lineWidth: 0.5)
                            }
                    }

                Text(entry.category.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(entry.category.tintColor)
                    .lineLimit(1)
            }
            .frame(width: 96, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                // ✅ Mensaje expandible: 3 líneas por defecto, tap para desplegar.
                // ✅ M3E: el despliegue usa el spring rápido de AuroraMotion
                // (antes `.easeOut` lineal); el `lineLimit` cambia con la misma
                // curva, así que la fila crece de forma elástica y no "salta".
                Text(entry.message)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(isExpanded ? nil : 3)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Haptics.light()
                        withAnimation(AuroraMotion.quick) {
                            onToggleExpanded()
                        }
                    }
                    .accessibilityHint("Toca para expandir o colapsar el mensaje")

                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)

                    Text(Self.timeFormatter.string(from: entry.date))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)

                    if let duration = entry.duration {
                        Spacer(minLength: 8)
                        // ✅ Pill de duración (monospaced)
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
        // sistema: cero blur por fila al scrollear en el A11.
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

    // MARK: - Helpers (antes vivían en LogsView, solo los usaba la fila)

    /// ✅ Un único DateFormatter reutilizado: crear uno por fila y por render era
    /// con diferencia lo más caro de la lista.
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    /// Icono por nivel (jerarquía visual más rápida que leer el texto).
    private static func levelIcon(for level: String) -> String {
        switch level {
        case "ERROR": return "xmark.octagon.fill"
        case "WARN": return "exclamationmark.triangle.fill"
        case "INFO": return "info.circle.fill"
        case "DEBUG": return "ladybug.fill"
        default: return "circle.fill"
        }
    }

    private static func levelColor(for level: String) -> Color {
        switch level {
        case "ERROR": return .red
        case "WARN": return .orange
        case "INFO": return .blue
        case "DEBUG": return .gray
        default: return .primary
        }
    }
}
