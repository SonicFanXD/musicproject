import Foundation

class Logger {
    static let shared = Logger()
    private init() {}

    func log(_ message: String) {
        #if DEBUG
        print("🔵 [AuroraPlayer] \(message)")
        #endif
    }
}