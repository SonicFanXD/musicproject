import Foundation

class Logger {
    static let shared = Logger()
    private let logFileURL: URL
    
    private init() {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        logFileURL = documentsDirectory.appendingPathComponent("aurora_log.txt")
        clearLog() // Opcional: borra logs anteriores al iniciar
    }
    
    func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
        let logMessage = "[\(timestamp)] \(message)\n"
        print(logMessage) // También imprime en consola (útil si usas Xcode)
        
        if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
            fileHandle.seekToEndOfFile()
            if let data = logMessage.data(using: .utf8) {
                fileHandle.write(data)
            }
            fileHandle.closeFile()
        } else {
            try? logMessage.data(using: .utf8)?.write(to: logFileURL)
        }
    }
    
    func clearLog() {
        try? "".data(using: .utf8)?.write(to: logFileURL)
    }
    
    func getLogContent() -> String? {
        return try? String(contentsOf: logFileURL, encoding: .utf8)
    }
}