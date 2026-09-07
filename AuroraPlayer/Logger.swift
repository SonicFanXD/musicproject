import Foundation
import os
import UIKit
import AVFoundation

enum LogCategory: String, CaseIterable {
    case playback, library, metadata, interface, system, network, equalizer, artwork
    // ✅ Nuevas categorías técnicas/visuales (diagnóstico completo de la app)
    case performance   // FPS, memoria, advertencias del sistema, térmico
    case cache         // guardado/carga del caché de biblioteca
    case settings      // cambios de ajustes del usuario
    case lifecycle     // foreground/background/terminación de la app

    var displayName: String {
        switch self {
        case .playback: return "Reproducción"
        case .library: return "Biblioteca"
        case .metadata: return "Metadatos"
        case .interface: return "Interfaz"
        case .system: return "Sistema"
        case .network: return "Red"
        case .equalizer: return "Ecualizador"
        case .artwork: return "Portadas"
        case .performance: return "Rendimiento"
        case .cache: return "Caché"
        case .settings: return "Ajustes"
        case .lifecycle: return "Ciclo de vida"
        }
    }

    /// Color asociado para la UI de logs (hex). nil = color por defecto.
    var tintHex: String {
        switch self {
        case .playback: return "#7C5CFF"   // morado
        case .library: return "#2E9E5B"    // verde
        case .metadata: return "#0A84FF"   // azul
        case .interface: return "#FF9F0A"  // naranja
        case .system: return "#8E8E93"     // gris
        case .network: return "#32ADE6"    // celeste
        case .equalizer: return "#FF375F"  // rosa
        case .artwork: return "#BF5AF2"    // violeta
        case .performance: return "#FFD60A"// amarillo
        case .cache: return "#30D158"      // verde claro
        case .settings: return "#64D2FF"   // cian
        case .lifecycle: return "#FF453A"  // rojo
        }
    }
}

struct InAppLogEntry: Identifiable {
    let id = UUID()
    let date: Date
    let level: String
    let category: LogCategory
    let message: String
    let duration: TimeInterval?
}

enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.aurora.player"
    private static let bufferLock = NSLock()
    private static var buffer: [InAppLogEntry] = []
    private static let maximumBufferedEntries = 800

    // MARK: - Persistencia en disco (los logs sobreviven reinicios de la app)
    private static let fileQueue = DispatchQueue(label: "com.aurora.logfile", qos: .utility)
    private static let maxPersistedBytes = 1_500_000 // rotación a ~1.5 MB
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static var logFileURL: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return dir.appendingPathComponent("aurora-logs.txt")
    }

    // MARK: - Acceso al buffer

    static var entries: [InAppLogEntry] {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        return buffer
    }

    static var errorCount: Int { countForLevel("ERROR") }
    static var warningCount: Int { countForLevel("WARN") }

    private static func countForLevel(_ level: String) -> Int {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        return buffer.filter { $0.level == level }.count
    }

    static func entries(for category: LogCategory) -> [InAppLogEntry] {
        entries.filter { $0.category == category }
    }

    static func clearEntries() {
        bufferLock.lock()
        buffer.removeAll(keepingCapacity: true)
        bufferLock.unlock()

        fileQueue.async {
            guard let url = logFileURL else { return }
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Observación técnica global (memoria, térmico, ciclo de vida)

    private static var bootstrapped = false

    /// Registra observadores de eventos técnicos del sistema. Llamar UNA vez
    /// al arrancar la app (AuroraPlayerApp). Loguea:
    /// - Advertencias de memoria (performance)
    /// - Estado térmico del dispositivo (performance)
    /// - Entrada/salida a segundo plano (lifecycle)
    /// - Cambios de ruta de audio (auriculares/Bluetooth) (system)
    static func bootstrap() {
        bufferLock.lock()
        if bootstrapped {
            bufferLock.unlock()
            return
        }
        bootstrapped = true
        bufferLock.unlock()

        let center = NotificationCenter.default

        // Advertencia de memoria del sistema (precursor de jetsam kill)
        center.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main
        ) { _ in
            AppLog.warning(.performance, "⚠️ Advertencia de memoria del sistema (didReceiveMemoryWarning)")
        }

        // Estado térmico: nominal / fair / serious / critical
        center.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil, queue: .main
        ) { _ in
            let state = ProcessInfo.processInfo.thermalState
            let name: String
            switch state {
            case .nominal: name = "nominal (frío)"
            case .fair: name = "fair (templado)"
            case .serious: name = "serious (caliente)"
            case .critical: name = "critical (muy caliente)"
            @unknown default: name = "desconocido"
            }
            AppLog.info(.performance, "Estado térmico del dispositivo: \(name)")
        }

        // Ciclo de vida: background / foreground
        center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main
        ) { _ in
            AppLog.info(.lifecycle, "App pasó a segundo plano")
        }
        center.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main
        ) { _ in
            AppLog.info(.lifecycle, "App volvió a primer plano")
        }
        center.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { _ in
            AppLog.info(.lifecycle, "App será terminada")
        }

        // Cambio de ruta de audio (auriculares conectados/desconectados, Bluetooth)
        center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil, queue: .main
        ) { notification in
            guard let info = notification.userInfo,
                  let reasonRaw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw) else { return }
            let reasonName: String
            switch reason {
            case .newDeviceAvailable: reasonName = "nueva salida disponible"
            case .oldDeviceUnavailable: reasonName = "salida desconectada"
            case .categoryChange: reasonName = "cambio de categoría"
            case .override: reasonName = "override (ej. altavoz)"
            case .routeConfigurationChange: reasonName = "reconfiguración de ruta"
            default: reasonName = "otro (\(reasonRaw))"
            }
            AppLog.info(.system, "Ruta de audio cambió: \(reasonName)")
        }

        AppLog.info(.system, "Observadores técnicos de logs registrados (memoria, térmico, ciclo de vida, rutas)")
    }

    // MARK: - API de registro

    static func info(_ category: LogCategory, _ message: String) {
        record("INFO", category, message)
        os.Logger(subsystem: subsystem, category: category.rawValue).info("\(message, privacy: .public)")
    }

    static func warning(_ category: LogCategory, _ message: String) {
        record("WARN", category, message)
        os.Logger(subsystem: subsystem, category: category.rawValue).warning("\(message, privacy: .public)")
    }

    static func error(_ category: LogCategory, _ message: String) {
        record("ERROR", category, message)
        os.Logger(subsystem: subsystem, category: category.rawValue).error("\(message, privacy: .public)")
    }

    /// Registra un Error con dominio y código: clave para diagnosticar fallos de reproducción
    static func error(_ category: LogCategory, _ sourceError: Error, context: String) {
        let nsError = sourceError as NSError
        AppLog.error(category, "\(context) — [\(nsError.domain) · código \(nsError.code)] \(nsError.localizedDescription)")
    }

    /// DEBUG ahora también se guarda en el buffer y en disco, para poder
    /// diagnosticar problemas incluso en builds de release.
    static func debug(_ category: LogCategory, _ message: String) {
        record("DEBUG", category, message)
        os.Logger(subsystem: subsystem, category: category.rawValue).debug("\(message, privacy: .public)")
    }

    static func timed(_ category: LogCategory, _ operation: String, _ block: () -> Void) {
        let start = Date()
        block()
        let elapsed = Date().timeIntervalSince(start)
        record("INFO", category, "\(operation) (\(String(format: "%.1f", elapsed * 1000))ms)", duration: elapsed)
    }

    private static func record(_ level: String, _ category: LogCategory, _ message: String, duration: TimeInterval? = nil) {
        let entry = InAppLogEntry(date: Date(), level: level, category: category, message: message, duration: duration)

        bufferLock.lock()
        if buffer.count >= maximumBufferedEntries {
            buffer.removeFirst(buffer.count - maximumBufferedEntries + 1)
        }
        buffer.append(entry)
        bufferLock.unlock()

        appendToDisk(entry: entry)
    }

    // MARK: - Escritura en disco (cola serial, fuera del hilo principal)

    private static func appendToDisk(entry: InAppLogEntry) {
        let line = "\(isoFormatter.string(from: entry.date)) [\(entry.level)] [\(entry.category.rawValue)] \(entry.message)\n"

        fileQueue.async {
            guard let url = logFileURL else { return }
            let fm = FileManager.default

            // Rotación: si el archivo crece demasiado, conserva la mitad más reciente
            if let attrs = try? fm.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int, size > maxPersistedBytes,
               let data = try? String(contentsOf: url, encoding: .utf8) {
                let lines = data.split(separator: "\n", omittingEmptySubsequences: true)
                let tail = lines.suffix(max(1, lines.count / 2)).joined(separator: "\n")
                try? (tail + "\n").write(to: url, atomically: true, encoding: .utf8)
            }

            if !fm.fileExists(atPath: url.path) {
                try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            }

            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data(line.utf8))
            } else {
                try? line.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    // MARK: - Exportación / Copia de diagnóstico

    /// Reporte completo: información del dispositivo y app + todos los logs persistidos
    /// (incluye sesiones anteriores, a diferencia del buffer en memoria)
    static func exportReportText() -> String {
        var report = """
        ====== DIAGNÓSTICO AURORA PLAYER ======
        Generado: \(Date())
        Versión app: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] ?? "?"))
        Sistema: iOS \(UIDevice.current.systemVersion)
        Dispositivo: \(UIDevice.current.model) — \(UIDevice.current.name)
        Entradas en memoria: \(entries.count)
        Errores: \(errorCount) · Advertencias: \(warningCount)

        ------ REGISTRO ------
        """

        let persisted = readPersistedLines()
        if persisted.isEmpty {
            for entry in entries {
                report += "\n\(isoFormatter.string(from: entry.date)) [\(entry.level)] [\(entry.category.rawValue)] \(entry.message)"
            }
        } else {
            report += "\n" + persisted.joined(separator: "\n")
        }

        report += "\n\n===== FIN DEL DIAGNÓSTICO =====\n"
        return report
    }

    private static func readPersistedLines() -> [String] {
        guard let url = logFileURL,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    /// Copia el diagnóstico completo al portapapeles
    static func copyReportToClipboard() {
        UIPasteboard.general.string = exportReportText()
    }

    /// Escribe el diagnóstico a un archivo temporal (.txt) para compartirlo o guardarlo en Archivos
    static func writeExportFile() -> URL? {
        let text = exportReportText()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("aurora-diagnostico.txt")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            AppLog.error(.system, error, context: "writeExportFile")
            return nil
        }
    }
}