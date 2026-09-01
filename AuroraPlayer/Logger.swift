import Foundation
import os

enum LogCategory: String {
    case playback, library, metadata, interface, system
}

enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.aurora.player"

    static func info(_ category: LogCategory, _ message: String) {
        os.Logger(subsystem: subsystem, category: category.rawValue)
            .info("\(message, privacy: .public)")
    }

    static func error(_ category: LogCategory, _ message: String) {
        os.Logger(subsystem: subsystem, category: category.rawValue)
            .error("\(message, privacy: .public)")
    }

    static func debug(_ category: LogCategory, _ message: String) {
        #if DEBUG
        os.Logger(subsystem: subsystem, category: category.rawValue)
            .debug("\(message, privacy: .public)")
        #endif
    }
}
