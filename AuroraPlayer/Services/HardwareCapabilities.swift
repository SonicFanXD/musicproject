import Foundation
import UIKit

/// Detección de capacidades de hardware para optimizaciones adaptativas
/// Permite aplicar mejoras de rendimiento solo en dispositivos que las necesitan
/// (iPhone 8 Plus/A11) sin sacrificar calidad visual en dispositivos más potentes.
final class HardwareCapabilities {
    static let shared = HardwareCapabilities()
    
    private let deviceModel: String
    let isA11Chip: Bool
    private let memoryClass: Int
    let isLowEndDevice: Bool
    
    private init() {
        self.deviceModel = Self.resolveDeviceModel()
        self.isA11Chip = Self.isA11Device(model: deviceModel)
        self.memoryClass = UIDevice.current.memoryClass
        // Dispositivos de gama baja: A11 o menos, o dispositivos con poca memoria
        self.isLowEndDevice = isA11Chip || memoryClass <= 2
    }
    
    /// Determina si el dispositivo es iPhone 8/8 Plus (A11 Bionic)
    private static func isA11Device(model: String) -> Bool {
        let a11Models = ["iPhone9,1", "iPhone9,3", "iPhone9,4", "iPhone9,2"] // iPhone 8/8 Plus
        return a11Models.contains(model)
    }
    
    /// Obtiene el modelo del dispositivo (ej. "iPhone9,4" para iPhone 8 Plus)
    private static func resolveDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0)
            }
        }
        return machine ?? "unknown"
    }
    
    /// Versión pública del modelo para uso externo
    var deviceModelPublic: String {
        deviceModel
    }
    
    // MARK: - Configuraciones adaptativas
    
    /// Número óptimo de barras para el visualizador según hardware
    var optimalVisualizerBars: Int {
        isA11Chip ? 16 : 24
    }
    
    /// Si debe usar blur de alta calidad o versión optimizada
    var useHighQualityBlur: Bool {
        !isLowEndDevice
    }
    
    /// Si debe usar interpolación de alta calidad para artwork
    var useHighQualityInterpolation: Bool {
        !isA11Chip
    }
    
    /// Resolución de artwork para PlayerBar (A11 usa miniaturas más pequeñas)
    var playerBarArtworkSize: CGFloat {
        isA11Chip ? 72 : 96
    }
    
    /// Número de canciones para activar carga diferida de artwork
    var lazyArtworkThreshold: Int {
        isA11Chip ? 100 : 200
    }
    
    /// Si debe usar drawingGroup() agresivo para optimización GPU
    var useAggressiveGPUOptimization: Bool {
        isA11Chip
    }
    
    /// Threshold térmico para desactivar visualizador (serious vs critical)
    var thermalVisualizerThreshold: ProcessInfo.ThermalState {
        isA11Chip ? .fair : .serious
    }
    
    /// Si debe usar precarga de artwork agresiva
    var useAggressiveArtworkPrewarm: Bool {
        !isA11Chip
    }
    
    /// Límite de caché de artwork ajustado según memoria disponible
    var artworkCacheLimit: Int {
        isA11Chip ? 20 : 32
    }
    
    /// Límite de memoria total para caché de artwork (en bytes)
    var artworkCacheMemoryLimit: Int {
        isA11Chip ? 32 * 1024 * 1024 : 48 * 1024 * 1024
    }
    
    /// Número de lotes concurrentes para indexación
    var maxConcurrentIndexingBatches: Int {
        isA11Chip ? 1 : 2
    }
    
    /// Tamaño de lote para indexación
    var indexingBatchSize: Int {
        isA11Chip ? 6 : 8
    }
    
    /// Propiedad pública para acceder a isLowEndDevice desde otros módulos
    var isLowEnd: Bool {
        isLowEndDevice
    }
    
    /// Descripción del dispositivo para logs
    var deviceDescription: String {
        if isA11Chip {
            return "iPhone 8/8 Plus (A11) - Optimizaciones activas"
        } else if isLowEndDevice {
            return "Dispositivo gama baja - Optimizaciones activas"
        } else {
            return "Dispositivo gama alta - Calidad máxima"
        }
    }
    
    /// Versión simplificada del modelo para mostrar en UI
    var friendlyModelName: String {
        if deviceModel.contains("iPhone9") {
            return "iPhone 8/8 Plus"
        } else if deviceModel.contains("iPhone10") {
            return "iPhone X"
        } else if deviceModel.contains("iPhone11") {
            return "iPhone XS/XR"
        } else if deviceModel.contains("iPhone12") {
            return "iPhone 12"
        } else if deviceModel.contains("iPhone13") {
            return "iPhone 13"
        } else if deviceModel.contains("iPhone14") {
            return "iPhone 14"
        } else if deviceModel.contains("iPhone15") {
            return "iPhone 15"
        } else if deviceModel.contains("iPhone16") {
            return "iPhone 16"
        }
        return "iPhone"
    }
}

// MARK: - Extensiones de UIKit para detección de memoria
extension UIDevice {
    /// Clase de memoria del dispositivo (estimación)
    var memoryClass: Int {
        // A11 (iPhone 8) tiene 3GB RAM -> memoryClass 3
        // A12-A14 tienen 4GB+ -> memoryClass 4+
        // A15+ tienen 6GB+ -> memoryClass 6+
        // Esta es una estimación basada en modelos conocidos
        let model = HardwareCapabilities.shared.deviceModelPublic
        
        if model.contains("iPhone9") { // iPhone 8
            return 3
        } else if model.contains("iPhone10") || model.contains("iPhone11") { // iPhone X/XS/XR
            return 4
        } else if model.contains("iPhone12") || model.contains("iPhone13") { // iPhone 12/13
            return 4
        } else if model.contains("iPhone14") { // iPhone 14
            return 6
        } else if model.contains("iPhone15") || model.contains("iPhone16") { // iPhone 15/16
            return 8
        }
        
        return 3 // Default conservador
    }
}