import Foundation
import os

// MARK: - Sistema de logs
class Logger {
    static let shared = Logger()
    private let logFileURL: URL
    
    private init() {
        // Directorio de documentos de la app
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        logFileURL = documents.appendingPathComponent("aurora_log.txt")
        
        // Si el archivo no existe, lo creamos
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil, attributes: nil)
        }
        
        // Escribir encabezado
        write("=== INICIO DE SESIÓN: \(Date()) ===\n")
    }
    
    func log(_ message: String, function: String = #function, file: String = #file, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
        let entry = "[\(timestamp)] \(fileName):\(line) - \(function) -> \(message)\n"
        
        // Escribir en el archivo
        write(entry)
        
        // También imprimir en consola (para debug en Xcode)
        print(entry)
    }
    
    private func write(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: logFileURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? data.write(to: logFileURL, options: .atomic)
        }
    }
    
    // Método para obtener el contenido del log
    func getLogs() -> String {
        return (try? String(contentsOf: logFileURL, encoding: .utf8)) ?? "No hay logs disponibles"
    }
    
    // Método para limpiar logs
    func clearLogs() {
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        write("=== LOGS LIMPIADOS ===\n")
    }
}