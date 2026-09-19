# Calidad de Audio para Audiófilos - AuroraPlayer

## Características Implementadas

### ✅ Modo Bit-Perfect
- **Indicador visual** en la vista de calidad de audio que muestra si la salida es bit-perfect (sin remuestreo)
- **Comparación en tiempo real** entre sample rate del archivo y sample rate de salida
- **Estado destacado** en verde cuando es bit-perfect, en gris cuando hay remuestreo

### ✅ Modo Measurement (AVAudioSession)
- **Opción en Ajustes** para cambiar entre modo Default y modo Measurement
- **Modo Measurement** desactiva el procesamiento del sistema (EQ, compresión dinámica, etc.)
- **Ideal para audiófilos** que quieren la señal más pura posible
- **Requiere reiniciar la sesión** de audio para aplicar el cambio

### ✅ Información de DAC USB
- **Detección automática** de DACs USB conectados
- **Muestra el nombre** del dispositivo USB conectado
- **Disponible en la sección "Audiófilo"** de la vista de calidad

### ✅ Información de Codec Bluetooth
- **Detección del tipo de conexión** Bluetooth (A2DP, BLE, HFP)
- **Documentación de limitaciones** de iOS sobre control de codecs
- **Advertencia clara** de que iOS controla automáticamente el codec

## Limitaciones de iOS (Importante para Audiófilos)

### Control de Codecs Bluetooth
**iOS NO permite que las aplicaciones controlen directamente el codec Bluetooth:**

- **AAC**: Codec por defecto de Apple para Bluetooth A2DP
- **aptX/aptX HD**: Soportados en algunos dispositivos Android, NO controlables en iOS
- **LDAC**: Codec de Sony, NO controlable en iOS
- **SBC**: Codec básico, usado como fallback

**Por qué es así:**
- Apple controla el stack de Bluetooth a nivel de sistema
- Las aplicaciones solo pueden seleccionar el perfil (A2DP vs HFP)
- El codec específico (AAC/aptX/LDAC) lo decide iOS automáticamente
- Esta es una limitación del sistema operativo, no de AuroraPlayer

**Lo que SÍ controla AuroraPlayer:**
- ✅ Exclusión de HFP (Hands-Free Profile) - evita baja calidad
- ✅ Forzar A2DP (perfil de música de alta calidad)
- ✅ Sample rate nativo del archivo (hasta que el hardware lo soporte)
- ✅ Formatos lossless (FLAC, ALAC, WAV, AIFF)

### Limitaciones de AVAudioSession
- **Modo Measurement**: Desactiva procesamiento del sistema, pero puede no funcionar con todos los dispositivos
- **Sample Rate**: `setPreferredSampleRate` es una "preferencia", iOS puede ignorarla
- **Buffer Duration**: iOS puede rechazar ciertos valores de buffer en hardware antiguo

## Comparación con Estándares Audiófilos

| Característica | AuroraPlayer | Ideal Audiófilo | Estado |
|----------------|--------------|-----------------|---------|
| Bluetooth A2DP | ✅ Exclusivo | ✅ Exclusivo | Excelente |
| Exclusión HFP | ✅ Explícito | ✅ Obligatorio | Excelente |
| Sample Rate Nativo | ✅ Intenta | ✅ Bit-perfect | Muy bien |
| Hi-Res (96kHz+) | ✅ Soportado | ✅ Requerido | Muy bien |
| Formatos Lossless | ✅ FLAC/ALAC/WAV | ✅ Requerido | Excelente |
| Bit Depth Real | ✅ 16/24/32 | ✅ Requerido | Excelente |
| Indicador Bit-Perfect | ✅ Nuevo | ✅ Deseable | ✅ Implementado |
| Modo Measurement | ✅ Nuevo | ✅ Deseable | ✅ Implementado |
| DAC USB Info | ✅ Nuevo | ✅ Deseable | ✅ Implementado |
| Codec Bluetooth Info | ✅ Nuevo | ⚠️ Limitado iOS | ✅ Implementado |
| Control Codec BT | ❌ iOS limita | ❌ iOS limita | Limitación de sistema |

## Recomendaciones para Audiófilos

### Para máxima calidad:
1. **Usar modo Measurement** en Ajustes > Audio > Modo de audio
2. **Conectar via cable** (headphones/USB DAC) para bit-perfect garantizado
3. **Evitar Bluetooth** si es posible (iOS controla el codec)
4. **Usar archivos lossless** (FLAC, ALAC) con sample rate nativo
5. **Desactivar EQ** si prefieres señal pura

### Para Bluetooth:
1. **Auriculares Apple** usan AAC automáticamente (mejor integración)
2. **Auriculares de terceros** pueden usar SBC (baja calidad) o AAC
3. **Auriculares Android** pueden no funcionar óptimamente (iOS puede forzar SBC)
4. **Ver indicador "Bit-Perfect"** para saber si hay remuestreo

### Para USB DAC:
1. **Conectar DAC USB** directamente al iPhone/iPad
2. **Usar modo Measurement** para evitar procesamiento del sistema
3. **Ver información del DAC** en la sección "Audiófilo"
4. **Archivos Hi-Res** (96kHz+) funcionarán si el DAC los soporta

## Notas Técnicas

### Implementación del Modo Measurement
```swift
let sessionMode: AVAudioSession.Mode = modeIndex == 1 ? .measurement : .default
try session.setCategory(.playback, mode: sessionMode, options: options)
```

### Detección Bit-Perfect
```swift
let sourceRate = currentSong?.sampleRate ?? 0
let bitPerfect = sourceRate > 0 && abs(outputRate - sourceRate) < 1
```

### Detección DAC USB
```swift
if portType == AVAudioSession.Port.usbAudio.rawValue {
    let route = session.currentRoute
    if let output = route.outputs.first {
        usbDACInfo = output.portName
    }
}
```

## Futuras Mejoras Posibles

1. **Integración con USB Audio Class** para control más directo de DACs
2. **Detección de capacidades del DAC** (sample rates soportados, bit depth)
3. **Perfil de audio personalizado** por tipo de dispositivo
4. **Más modos de AVAudioSession** (ej. .spatialAudio si aplica)

## Conclusión

AuroraPlayer está **diseñado para audiófilos** con todas las optimizaciones posibles dentro de las limitaciones de iOS. Las características nuevas (indicador bit-perfect, modo measurement, info DAC/Bluetooth) permiten a los usuarios entender exactamente qué está pasando con su audio y tomar decisiones informadas sobre su configuración.

La mayor limitación es el **control de codecs Bluetooth por parte de iOS**, pero esto es una restricción del sistema operativo que ninguna app puede superar. La mejor solución para audiófilos es usar conexiones cableadas cuando la máxima calidad es prioritaria.