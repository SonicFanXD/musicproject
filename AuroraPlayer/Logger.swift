import Foundation
import os

enum LogCategory: String, CaseIterable {
    case playback, library, metadata, interface, system
}

struct InAppLogEntry: Identifiable {
    let id = UUID()
    let date: Date
    let level: String
    let category: LogCategory
    let message: String
}

enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.aurora.player"
    private static let bufferLock = NSLock()
    private static var buffer: [InAppLogEntry] = []
    private static let maximumBufferedEntries = 300

    static var entries: [InAppLogEntry] {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        return buffer
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

    static func debug(_ category: LogCategory, _ message: String) {
        #if DEBUG
        addToBuffer(level: "DEBUG", category: category, message: message)
        os.Logger(subsystem: subsystem, category: category.rawValue)
            .debug("\(message, privacy: .public)")
        #endif
    }

    private static func addToBuffer(level: String, category: LogCategory, message: String) {
        bufferLock.lock()
        if buffer.count == maximumBufferedEntries { buffer.removeFirst() }
        buffer.append(InAppLogEntry(date: Date(), level: level, category: category, message: message))
        bufferLock.unlock()
    }
}
