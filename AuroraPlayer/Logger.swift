import Foundation
import os

enum LogCategory: String, CaseIterable {
    case playback, library, metadata, interface, system

    var displayName: String {
        switch self {
        case .playback: return "Reproducción"
        case .library: return "Biblioteca"
        case .metadata: return "Metadatos"
        case .interface: return "Interfaz"
        case .system: return "Sistema"
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
    private static let maximumBufferedEntries = 500

    static var entries: [InAppLogEntry] {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        return buffer
    }

    static var errorCount: Int {
        entries.filter { $0.level == "ERROR" }.count
    }

    static var warningCount: Int {
        entries.filter { $0.level == "WARN" }.count
    }

    static func entries(for category: LogCategory) -> [InAppLogEntry] {
        entries.filter { $0.category == category }
    }

    static func clearEntries() {
        bufferLock.lock()
        buffer.removeAll(keepingCapacity: true)
        bufferLock.unlock()
    }

    static func info(_ category: LogCategory, _ message: String) {
        addToBuffer(level: "INFO", category: category, message: message)
        os.Logger(subsystem: subsystem, category: category.rawValue)
            .info("\(message, privacy: .public)")
    }

    static func error(_ category: LogCategory, _ message: String) {
        addToBuffer(level: "ERROR", category: category, message: message)
        os.Logger(subsystem: subsystem, category: category.rawValue)
            .error("\(message, privacy: .public)")
    }

    static func warning(_ category: LogCategory, _ message: String) {
        addToBuffer(level: "WARN", category: category, message: message)
        os.Logger(subsystem: subsystem, category: category.rawValue)
            .warning("\(message, privacy: .public)")
    }

    static func debug(_ category: LogCategory, _ message: String) {
        #if DEBUG
        addToBuffer(level: "DEBUG", category: category, message: message)
        os.Logger(subsystem: subsystem, category: category.rawValue)
            .debug("\(message, privacy: .public)")
        #endif
    }

    static func timed(_ category: LogCategory, _ operation: String, _ block: () -> Void) {
        let start = Date()
        block()
        let elapsed = Date().timeIntervalSince(start)
        addToBuffer(level: "INFO", category: category, message: "\(operation) (\(String(format: "%.1f", elapsed * 1000))ms)", duration: elapsed)
    }

    private static func addToBuffer(level: String, category: LogCategory, message: String, duration: TimeInterval? = nil) {
        bufferLock.lock()
        if buffer.count == maximumBufferedEntries { buffer.removeFirst() }
        buffer.append(InAppLogEntry(date: Date(), level: level, category: category, message: message, duration: duration))
        bufferLock.unlock()
    }
}
