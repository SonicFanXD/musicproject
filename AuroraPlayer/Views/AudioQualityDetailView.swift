import SwiftUI
import AVFoundation

/// Ventana emergente estilo PowerAmp: muestra la calidad del archivo fuente
/// y la cadena de procesamiento completa hasta la salida física.
struct AudioQualityDetailView: View {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject private var localization = Localization.shared
    var embeddedInCard: Bool = false
    @Environment(\.dismiss) private var dismiss

    @State private var appearAnimation = false
    // ✅ OPTIMIZACIÓN: eliminado signalFlow (48 animaciones simultáneas causaban tirones).
    // En su lugar, usamos un TimelineView para actualizar los indicadores de señal
    // sin forzar re-renders del árbol de vistas completo.
    @State private var cachedFileSize: Int = 0
    @State private var cachedDuration: TimeInterval = 0

    @Environment(\.colorScheme) private var colorScheme

    private var song: Song? { audioEngine.currentSong }

    /// ✅ Brillo del canto de las tarjetas. En MODO CLARO un blanco al 25% es
    /// prácticamente invisible sobre una tarjeta clara (el canto desaparecía y la
    /// tarjeta perdía el perfil); se usa un gris oscuro de baja opacidad, que da el
    /// mismo efecto de "luz desde arriba" y funciona en las dos apariencias.
    private var cardHairline: LinearGradient {
        colorScheme == .dark
        ? LinearGradient(
            colors: [.white.opacity(0.25), .white.opacity(0.05), .clear],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        : LinearGradient(
            colors: [.black.opacity(0.10), .black.opacity(0.03), .clear],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    var body: some View {
        Group {
            if embeddedInCard {
                embeddedContent
            } else {
                fullScreenContent
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.35)) { appearAnimation = true }
            loadFileStats()
        }
        .onChange(of: audioEngine.currentSong?.id) { _ in
            // ✅ FIX datos obsoletos: el tamaño del archivo (y el bitrate derivado
            // de él) se leían SOLO al aparecer, así que al cambiar de canción con
            // el panel abierto se seguía mostrando el tamaño de la canción
            // ANTERIOR. Ahora se recarga por canción.
            loadFileStats()
        }
    }

    /// Lee el tamaño REAL del archivo en segundo plano, una vez por canción.
    /// `cachedDuration` alimenta el bitrate derivado de tamaño/duración cuando el
    /// codec no publica su propia tasa.
    private func loadFileStats() {
        guard let song = song else {
            cachedFileSize = 0
            cachedDuration = 0
            return
        }
        // Se pone a 0 al instante: mientras llega el dato nuevo, las filas muestran
        // "—" en lugar del valor de la canción anterior.
        cachedFileSize = 0
        cachedDuration = song.duration
        let path = song.url.path
        DispatchQueue.global(qos: .userInitiated).async {
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
            DispatchQueue.main.async {
                self.cachedFileSize = size
            }
        }
    }

    // MARK: - Contenido embebido (para tarjeta modal)
    private var embeddedContent: some View {
        ScrollView {
            // ✅ OPTIMIZACIÓN: LazyVStack para que las secciones solo se
            // rendericen cuando entran en pantalla (crítico en dispositivos
            // antiguos o con muchas secciones visibles a la vez).
            LazyVStack(spacing: 16) {
                headerCard
                signalChainSection
                fileDetailsSection
                outputDetailsSection
                audiophileInfoSection
                deviceSection
            }
            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 14)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Cuerpo completo con chrome de navegación
    private var fullScreenContent: some View {
        NavigationStack {
            ZStack {
                // ✅ Fondo premium consistente con NowPlayingView
                AppBackground()

                ScrollView {
                    // ✅ OPTIMIZACIÓN: LazyVStack para lazy-loading de secciones.
                    LazyVStack(spacing: 18) {
                        headerCard
                        signalChainSection
                        fileDetailsSection
                        outputDetailsSection
                        audiophileInfoSection
                        deviceSection
                    }
                    .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(Localization.localized("audio.quality.title"))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [AppTheme.accent, AppTheme.accent.opacity(0.7)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .accessibilityLabel(Localization.localized("audio.quality.title"))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(Localization.localized("quality.done")) { dismiss() }
                        .foregroundStyle(AppTheme.accent)
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
        }
    }

    // MARK: - Header (tarjeta de especificaciones estilo DAC, optimizada 60fps)
    private var headerCard: some View {
        VStack(spacing: 14) {
            ZStack {
                // ✅ 60fps: gradiente ESTÁTICO (se rasteriza UNA vez, no por frame)
                Circle()
                    .fill(AppTheme.accentGradient(opacity: 0.15))
                    .frame(width: 88, height: 88)

                // ✅ 60fps: Anillo simple sin animación (eliminado repeatForever)
                Circle()
                    .stroke(AppTheme.accentGradient(opacity: 0.4), lineWidth: 2)
                    .frame(width: 76, height: 76)

                // ✅ 60fps: Círculo interior sólido (sin material costoso)
                Circle()
                    .fill(Color(UIColor.tertiarySystemBackground))
                    .frame(width: 66, height: 66)
                    .overlay(
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(AppTheme.accentGradient)
                    )
            }
            .drawingGroup() // ✅ Rasteriza todo el ZStack en GPU

            // ✅ Badge de calidad basado en sampleRate (kHz)
            Text(qualityCategory)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(2)
                .foregroundStyle(.white)
                // ✅ Cápsula a prueba de etiquetas largas ("CALIDAD DESCONOCIDA"):
                // un renglón, encogiendo antes que desbordar el gradiente.
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 18)
                .padding(.vertical, 7)
                .background {
                    Capsule().fill(LinearGradient(
                        colors: [AppTheme.accent, AppTheme.accent.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                }
                .drawingGroup()

            // ✅ Info de la canción
            VStack(spacing: 4) {
                Text(song?.title ?? Localization.localized("quality.noSong"))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text(song?.displaySubtitle ?? "—")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // ✅ DISPLAY AUDIÓFILO (estilo lectura de DAC): resolución exacta
            // del archivo + canales, en un panel tipo "spec sheet".
            if let song {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Localization.localized("quality.resolution"))
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .tracking(1.6)
                            .foregroundStyle(.secondary)
                        Text(dacReadout(for: song))
                            .font(.system(size: 19, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(AppTheme.accentGradient)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Localization.localized("quality.channels"))
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .tracking(1.6)
                            .foregroundStyle(.secondary)
                        Text(channelsLabel)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(UIColor.secondarySystemBackground).opacity(0.5))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(AppTheme.accent.opacity(0.14), lineWidth: 1)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground).opacity(0.45))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(cardHairline, lineWidth: 1)
        }
        .opacity(appearAnimation ? 1 : 0)
        .scaleEffect(appearAnimation ? 1 : 0.95)
        .animation(.easeOut(duration: 0.3), value: appearAnimation)
    }

    /// ✅ Lectura tipo DAC. La métrica que se enseña depende del FORMATO, porque
    /// no significan lo mismo:
    /// · SIN pérdida (FLAC/ALAC/WAV/AIFF) → profundidad real ("24-bit") + tasa.
    /// · CON pérdida (MP3/AAC) → NO existe profundidad lineal; el dato verdadero
    ///   equivalente es la tasa del codec ("~320 kbps") + tasa de muestreo.
    /// Antes se mostraba `bitDepth` siempre que fuera > 0, lo que podía anunciar
    /// "16-bit" en un MP3 (información falsa: el ASBD nunca publica profundidad
    /// para codecs con pérdida, y si alguna vez la publica, aquí se ignora).
    /// La tasa de muestreo va siempre por `khzLabel` compartido: "44.1 kHz",
    /// nunca "44100 Hz".
    private func dacReadout(for song: Song) -> String {
        var parts: [String] = []
        if let depthOrBitrate = depthOrBitratePart(song) { parts.append(depthOrBitrate) }
        if song.sampleRate > 0 {
            parts.append(AlbumDetailView.khzLabel(song.sampleRate))
        }
        if parts.isEmpty { return "—" }
        return parts.joined(separator: " · ")
    }

    private var isLossless: Bool {
        song?.isLossless ?? false
    }

    /// Categoría de calidad basada en sampleRate (kHz)
    private var qualityCategory: String {
        guard let song = song else { return Localization.localized("quality.unknownQuality") }
        let rate = song.sampleRate
        
        if rate == 0 { return Localization.localized("quality.unknownQuality") }
        
        // Hi-Res: sampleRate > 48000 kHz (96 kHz, 192 kHz, etc.)
        // CD Quality (44.1kHz) y 48kHz NO son Hi-Res, son lossless estándar
        if rate > 48000 {
            return Localization.localized("quality.hiResAudio")
        }
        
        // Lossless pero no Hi-Res (ej: CD quality 44.1kHz FLAC/WAV)
        if isLossless {
            return Localization.localized("quality.losslessQuality")
        }
        
        // Formato comprimido (MP3, AAC, etc.)
        if rate > 0 {
            return Localization.localized("quality.compressedQuality")
        }
        
        return Localization.localized("quality.standardQuality")
    }

    // MARK: - Cadena de procesamiento con flujo animado
    private var signalChainSection: some View {
        settingsSection(title: Localization.localized("quality.signalChain"), icon: "arrow.triangle.branch") {
            VStack(spacing: 0) {
                chainNode(icon: "doc.fill", title: Localization.localized("quality.sourceFile"), detail: fileSummary, color: AppTheme.accent)
                chainArrow
                chainNode(icon: "waveform", title: Localization.localized("quality.decoder"), detail: "AVAudioFile · \(isLossless ? Localization.localized("quality.lossless") : Localization.localized("quality.compressed"))", color: .indigo)
                chainArrow
                chainNode(icon: "engine.combustion", title: Localization.localized("quality.audioEngine"), detail: "AVAudioEngine · \(AlbumDetailView.khzLabel(audioEngine.sampleRateDisplay > 0 ? audioEngine.sampleRateDisplay : (song?.sampleRate ?? 0)))", color: AppTheme.accent)
                chainArrow
                chainNode(icon: "slider.horizontal.3", title: Localization.localized("quality.equalizer"), detail: audioEngine.isEQEnabled ? "\(Localization.localized("quality.active")) · \(audioEngine.eqPreset.displayName) · 10 \(Localization.localized("format.bands"))" : "\(Localization.localized("quality.bypass")) · 10 \(Localization.localized("format.bands"))", color: audioEngine.isEQEnabled ? AppTheme.accent : .gray)
                chainArrow
                chainNode(icon: outputIcon, title: Localization.localized("quality.output"), detail: outputSummary, color: .orange)
            }
        }
    }

    /// Conector entre nodos de la cadena.
    /// ✅ FIX alineación: antes iba centrado en la fila (`maxWidth: .infinity`),
    /// así que las líneas aparecían en mitad del panel sin conectar nada y el
    /// "punto de flujo" quedaba pegado al borde inferior. Ahora el conector se
    /// alinea con la COLUMNA DE ICONOS de los nodos (el icono mide 40pt y empieza
    /// a 16pt del borde → su centro cae a 36pt), y lleva una punta de flecha que
    /// marca la dirección del flujo.
    private var chainArrow: some View {
        HStack(spacing: 0) {
            ZStack {
                // ✅ 60fps: barra estática (la animación de escala/opacidad
                // forzaba re-renders constantes).
                RoundedRectangle(cornerRadius: 1)
                    .fill(
                        LinearGradient(
                            colors: [
                                AppTheme.accent.opacity(0.10),
                                AppTheme.accent.opacity(0.55),
                                AppTheme.accent.opacity(0.10)
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 2, height: 18)

                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(AppTheme.accent)
                    .offset(y: 9)
            }
            .frame(width: 40, height: 20)
            // ✅ Rasteriza gradiente + punta una sola vez (son 4 conectores).
            .drawingGroup()

            Spacer(minLength: 0)
        }
        .padding(.leading, 16)
        .frame(height: 20)
    }

    /// Resumen del archivo de origen en la cadena de procesamiento.
    /// ✅ Se compone de los CAMPOS REALES de la canción, no del `formatDescription`
    /// almacenado al indexar: aquel string guarda la tasa truncada
    /// (`Int(sampleRate / 1000)` → "44 kHz" para 44100), así que el nodo de origen
    /// mostraba "44 kHz" mientras el resto de la app dice "44.1 kHz".
    /// Además: sin pérdida → bits; con pérdida → kbps del codec (nunca bits).
    private var fileSummary: String {
        guard let song = song else { return "—" }
        var parts: [String] = [song.formatName]
        if let depthOrBitrate = depthOrBitratePart(song) { parts.append(depthOrBitrate) }
        if song.sampleRate > 0 { parts.append(AlbumDetailView.khzLabel(song.sampleRate)) }
        return parts.joined(separator: " · ")
    }

    /// Parte "profundidad o tasa" del archivo — la MISMA regla en la cabecera y en
    /// el nodo de origen, para que no puedan divergir:
    /// bits reales si el formato es sin pérdida; si no, kbps del codec.
    private func depthOrBitratePart(_ song: Song) -> String? {
        if song.isLossless, song.bitDepth > 0 { return "\(song.bitDepth)-bit" }
        if let bitrate = song.bitrate, bitrate > 0 { return "~\(bitrate) kbps" }
        return nil
    }

    private var outputIcon: String {
        switch audioEngine.outputPortType {
        case AVAudioSession.Port.airPlay.rawValue: return "airplayaudio"
        case AVAudioSession.Port.bluetoothA2DP.rawValue,
             AVAudioSession.Port.bluetoothLE.rawValue,
             AVAudioSession.Port.bluetoothHFP.rawValue: return "airpods.pro"
        case AVAudioSession.Port.builtInSpeaker.rawValue: return "hifispeaker.fill"
        case AVAudioSession.Port.usbAudio.rawValue: return "cable.connector"
        case AVAudioSession.Port.carAudio.rawValue: return "car.fill"
        default: return "headphones"
        }
    }

    private var outputSummary: String {
        var parts: [String] = [audioEngine.routeDisplay]
        if audioEngine.outputSampleRate > 0 {
            // ✅ Helper compartido: "44.1 kHz" exacto, no "44 kHz" truncado.
            parts.append(AlbumDetailView.khzLabel(audioEngine.outputSampleRate))
        }
        if audioEngine.outputChannelCount > 0 { parts.append(audioEngine.outputChannelCount >= 2 ? Localization.localized("quality.stereo") : Localization.localized("quality.mono")) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Detalles del archivo
    private var fileDetailsSection: some View {
        settingsSection(title: Localization.localized("quality.file"), icon: "info.circle") {
            detailRow(Localization.localized("quality.format"), formatLabel)
            detailRow(Localization.localized("quality.sampleRate"), sampleRateLabel)
            detailRow(Localization.localized("quality.bitDepth"), bitDepthLabel)
            detailRow(Localization.localized("quality.channels"), channelsLabel)
            detailRow(Localization.localized("quality.duration"), durationLabel)
            detailRow(Localization.localized("quality.fileSize"), fileSizeLabel)
            detailRow(Localization.localized("quality.estBitrate"), bitrateLabel)
        }
    }

    // MARK: - Detalles de salida
    private var outputDetailsSection: some View {
        settingsSection(title: Localization.localized("quality.outputDetails"), icon: "hifispeaker") {
            detailRow(Localization.localized("quality.route"), audioEngine.routeDisplay)
            // ✅ FIX coherencia de unidades: esta fila mostraba "44100 Hz" mientras
            // el resto de la app (cadena de procesamiento, cabecera, NowPlaying)
            // usa "44.1 kHz". Mismo helper compartido en toda la vista.
            detailRow(Localization.localized("quality.outputFrequency"),
                      audioEngine.outputSampleRate > 0
                      ? AlbumDetailView.khzLabel(audioEngine.outputSampleRate)
                      : "—")
            detailRow(Localization.localized("quality.outputChannels"), audioEngine.outputChannelCount > 0 ? audioEngine.outputChannelCount.description : "—")
            detailRow(Localization.localized("quality.routeType"), outputTypeLabel)
            // ✅ 3.0.2: el modo de respaldo (AVPlayer) deja de ser invisible. Si el
            // motor propio falló, el EQ, el mono y el headroom NO están aplicándose
            // y el indicador de bit-perfect no puede afirmarse: había que poder
            // verlo sin abrir los logs.
            detailRow(Localization.localized("quality.playbackEngine"),
                      audioEngine.isUsingFallback
                      ? Localization.localized("quality.fallbackEngine")
                      : "AVAudioEngine")
            // ✅ 3.0.1: telemetría REAL del enlace (lo único que iOS expone del
            // dispositivo conectado): canales máximos, latencia y buffer concedido.
            detailRow(Localization.localized("quality.maxOutputChannels"), maxOutputChannelsLabel)
            detailRow(Localization.localized("quality.outputLatency"), outputLatencyLabel)
            detailRow(Localization.localized("quality.ioBufferDuration"), ioBufferDurationLabel)
            // ✅ Se dice explícitamente qué NO se puede saber, en vez de insinuar
            // capacidades del DAC que iOS no publica.
            noteRow(Localization.localized("quality.dacLimitNote"))
        }
    }

    // MARK: - Información Audiófila
    private var audiophileInfoSection: some View {
        // ✅ i18n: este título estaba escrito a mano en español (con la app en
        // inglés seguía diciendo "Audiófilo").
        settingsSection(title: Localization.localized("quality.audiophile"), icon: "waveform.circle") {
            // ✅ AUDIÓFILO: Indicador Bit-Perfect
            detailRow(Localization.localized("quality.bitPerfect"), 
                      audioEngine.isBitPerfect ? Localization.localized("quality.bitPerfectYes") : Localization.localized("quality.bitPerfectNo"),
                      isHighlighted: audioEngine.isBitPerfect)

            // ✅ Nota: explica POR QUÉ el indicador puede estar apagado (antes no
            // había ninguna pista y parecía un fallo de la app).
            if !audioEngine.isBitPerfect {
                noteRow(Localization.localized("quality.bitPerfectHint"), systemImage: "questionmark.circle.fill")
            }
            
            // ✅ AUDIÓFILO: Codec Bluetooth (si aplica). El motor publica el perfil
            // (A2DP / LE / HFP); aquí se explica qué implica cada uno, en el idioma
            // de la app. HFP es el perfil de LLAMADAS (mono, banda estrecha), así
            // que recibe su propia nota: la genérica mentiría para ese caso.
            if !audioEngine.bluetoothCodec.isEmpty {
                detailRow(Localization.localized("quality.bluetoothCodec"), audioEngine.bluetoothCodec)
                let isCallProfile = audioEngine.outputPortType == AVAudioSession.Port.bluetoothHFP.rawValue
                noteRow(
                    Localization.localized(isCallProfile ? "quality.btCallProfileLimit" : "quality.iosBluetoothLimit"),
                    systemImage: "antenna.radiowaves.left.and.right"
                )
            }
            
            // ✅ AUDIÓFILO: DAC USB (si aplica)
            if !audioEngine.usbDACInfo.isEmpty {
                detailRow(Localization.localized("quality.usbDAC"), audioEngine.usbDACInfo)
            }
            
            // ✅ AUDIÓFILO: Modo de sesión (localizado; antes el motor publicaba
            // la etiqueta "Measurement (bit-perfect)" ya en un idioma fijo).
            if !audioEngine.audioSessionMode.isEmpty {
                detailRow(Localization.localized("quality.sessionMode"), sessionModeLabel)
            }
        }
    }

    // MARK: - Dispositivo
    private var deviceSection: some View {
        settingsSection(title: Localization.localized("quality.device"), icon: "iphone") {
            detailRow(Localization.localized("quality.model"), audioEngine.deviceModelName)
            detailRow(Localization.localized("quality.system"), "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
        }
    }

    // MARK: - Labels de telemetría de salida (3.0.1)

    private var maxOutputChannelsLabel: String {
        audioEngine.maximumOutputChannels > 0 ? audioEngine.maximumOutputChannels.description : "—"
    }

    private var outputLatencyLabel: String {
        audioEngine.outputLatencyMs > 0 ? String(format: "%.1f ms", audioEngine.outputLatencyMs) : "—"
    }

    private var ioBufferDurationLabel: String {
        audioEngine.ioBufferDurationMs > 0 ? String(format: "%.2f ms", audioEngine.ioBufferDurationMs) : "—"
    }

    /// Modo REAL de `AVAudioSession`, localizado. El motor publica el token de
    /// AVFoundation (`Measurement` / `Default`, los mismos que devuelve
    /// `session.mode.rawValue`), así que la traducción se hace aquí y no en el motor.
    private var sessionModeLabel: String {
        switch audioEngine.audioSessionMode {
        case AVAudioSession.Mode.measurement.rawValue:
            return Localization.localized("quality.sessionMeasurement")
        case AVAudioSession.Mode.default.rawValue:
            return Localization.localized("quality.sessionDefault")
        default:
            // Cualquier otro modo (voz, vídeo, juego…) se muestra tal cual: es su
            // identificador oficial y no hay equivalencia traducida fiable.
            return audioEngine.audioSessionMode
        }
    }

    // MARK: - Labels calculados
    private var formatLabel: String {
        guard let song = song else { return "—" }
        let ext = song.url.pathExtension.uppercased()
        switch ext {
        case "FLAC": return Localization.localized("format.flac")
        case "ALAC", "M4A": return Localization.localized("format.alac")
        case "MP3": return Localization.localized("format.mp3")
        case "WAV", "WAVE": return Localization.localized("format.wav")
        case "AIFF", "AIF": return Localization.localized("format.aiff")
        case "AAC": return Localization.localized("format.aac")
        default: return ext.isEmpty ? Localization.localized("quality.unknown") : ext
        }
    }

    private var sampleRateLabel: String {
        guard let song = song, song.sampleRate > 0 else { return "—" }
        let base = AlbumDetailView.khzLabel(song.sampleRate)
        return song.sampleRate > 48000 ? "\(base) (Hi-Res)" : base
    }

    private var channelsLabel: String {
        guard let song = song, song.channelCount > 0 else { return "—" }
        switch song.channelCount {
        case 1: return "1 (\(Localization.localized("quality.mono")))"
        case 2: return "2 (\(Localization.localized("quality.stereo")))"
        default: return "\(song.channelCount) (\(Localization.localized("quality.surround")))"
        }
    }

    private var durationLabel: String {
        guard let song = song, song.duration > 0 else { return "—" }
        let minutes = Int(song.duration) / 60
        let seconds = Int(song.duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var fileSizeLabel: String {
        guard song != nil, cachedFileSize > 0 else { return "—" }
        if cachedFileSize > 1_048_576 { return String(format: "%.1f MB", Double(cachedFileSize) / 1_048_576) }
        return String(format: "%.0f KB", Double(cachedFileSize) / 1024)
    }

    /// ✅ Bitrate: si el CODEC publica su tasa (MP3/AAC vía
    /// `AVAssetTrack.estimatedDataRate`), ESE es el dato real del archivo y se
    /// muestra sin estimar nada. El valor derivado de tamaño ÷ duración queda
    /// como respaldo (marcado con "~"): antes se usaba siempre, así que un VBR
    /// real de 256 kbps podía leerse como 320.
    private var bitrateLabel: String {
        if let bitrate = song?.bitrate, bitrate > 0 { return "\(bitrate) kbps" }
        guard cachedDuration > 0, cachedFileSize > 0 else { return "—" }
        let kbps = Int((Double(cachedFileSize) * 8) / cachedDuration / 1000)
        return "~\(kbps) kbps"
    }

    // ✅ Profundidad REAL, y SOLO para formatos sin pérdida: solo ellos tienen
    // profundidad lineal (16/24/32). En MP3/AAC no existe, así que se muestra
    // "—" (su calidad equivalente ya tiene su propia fila, "Bitrate estimado").
    // La comprobación explícita de `isLossless` sustituye a depender de que
    // `bitDepth` llegue a 0 desde la indexación.
    private var bitDepthLabel: String {
        guard let song = song, song.isLossless, song.bitDepth > 0 else { return "—" }
        return "\(song.bitDepth) bits"
    }

    // ✅ Detección por portType, independiente del idioma del sistema
    private var outputTypeLabel: String {
        switch audioEngine.outputPortType {
        case AVAudioSession.Port.bluetoothA2DP.rawValue,
             AVAudioSession.Port.bluetoothLE.rawValue,
             AVAudioSession.Port.bluetoothHFP.rawValue: return Localization.localized("quality.wirelessBt")
        case AVAudioSession.Port.airPlay.rawValue: return Localization.localized("quality.wirelessAirPlay")
        case AVAudioSession.Port.builtInSpeaker.rawValue: return Localization.localized("quality.internalSpeaker")
        case AVAudioSession.Port.builtInReceiver.rawValue: return Localization.localized("quality.internalReceiver")
        case AVAudioSession.Port.headphones.rawValue: return Localization.localized("quality.wiredHeadphones")
        case AVAudioSession.Port.usbAudio.rawValue: return Localization.localized("quality.wiredUsb")
        case AVAudioSession.Port.carAudio.rawValue: return Localization.localized("quality.wirelessCar")
        default: return Localization.localized("quality.internal")
        }
    }

    // MARK: - Componentes reutilizables (optimizados con drawingGroup)
    @ViewBuilder
    // ✅ Sin parámetro `index`: solo lo usaba el flujo animado de la versión
    // anterior (eliminado por coste de re-render).
    private func chainNode(icon: String, title: String, detail: String, color: Color) -> some View {
        HStack(spacing: 14) {
            ZStack {
                // ✅ 60fps: Fondo sólido (sin gradiente costoso)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: 40, height: 40)

                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(color)
            }
            .drawingGroup()

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer()

            // ✅ 60fps: indicador de estado estático
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground).opacity(0.5))
        )
    }

    @ViewBuilder
    private func detailRow(_ title: String, _ value: String, isHighlighted: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            // ✅ Título con un solo renglón: si el label crece en un idioma, se
            // encoge en vez de partir la fila en dos y desalinear el valor.
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 10)
            // ✅ `firstTextBaseline` + dígitos monoespaciados: los valores numéricos
            // (kHz, bits, ms, kbps) quedan alineados entre filas.
            Text(value)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(isHighlighted ? AppTheme.accent : .primary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                // `AnyShapeStyle` (un solo nivel, no anidado): las dos ramas tienen
                // tipos distintos (gradiente vs. color) y `fill` exige uno solo.
                .fill(isHighlighted
                      ? AnyShapeStyle(AppTheme.accentGradient(opacity: 0.1))
                      : AnyShapeStyle(Color(UIColor.tertiarySystemBackground).opacity(0.4)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isHighlighted ? AppTheme.accent.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }

    /// ✅ FILA DE NOTA explicativa: texto completo, sin truncar.
    /// Antes estas frases iban por `detailRow("ℹ️", …)`, donde el valor lleva
    /// `lineLimit(2)` y tipografía de dato → una explicación de 120 caracteres se
    /// CORTABA a media frase (y los modificadores de tamaño que se aplicaban por
    /// fuera no tenían efecto, porque los `Text` internos fijan su propia fuente).
    /// Aquí el icono va a la izquierda y el texto ocupa el ancho completo.
    @ViewBuilder
    private func noteRow(_ text: String, systemImage: String = "info.circle.fill") -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.accent.opacity(0.9))
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.accent.opacity(0.07))
        )
    }

    // MARK: - Section Builder (optimizado para 60fps)
    @ViewBuilder
    private func settingsSection<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(LinearGradient(
                                colors: [AppTheme.accent, AppTheme.accent.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                    }
                    .drawingGroup()

                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 6)

            VStack(spacing: 8) {
                content()
            }
            .padding(8)
            .background {
                // ✅ Cristal: 0.5 de opacidad para que el material del panel
                // (y el artwork borroso detrás) se vea a través de la sección.
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(UIColor.secondarySystemBackground).opacity(0.5))
            }
        }
    }
}