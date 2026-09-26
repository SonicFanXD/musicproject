import SwiftUI
import AVFoundation

/// Ventana emergente estilo PowerAmp: muestra la calidad del archivo fuente y
/// TODA la cadena de audio (archivo → decoder → motor → EQ → salida), con el
/// diseño de Aurora (tipografía .rounded, acento de la portada, glass y los
/// paddings de la app).
///
/// ✅ FASE C — 60 fps en iPhone 8 Plus (A11):
///   · El `body` NO formatea NADA: todos los textos y números se calculan una vez
///     en `QualitySnapshot` (onAppear + cambios REALES de estado).
///   · No observa `audioEngine.clock`, así que los ticks de 0.4 s del reloj de
///     reproducción no la re-renderizan (verificado: el reloj vive aislado en
///     `PlaybackClock` y esta vista solo lee estado del motor).
///   · Sin `DateFormatter` ni formateo de strings en el render: todo ocurre en
///     `refreshSnapshot()`.
///   · Los degradados estáticos (círculo del header, iconos de la cadena) usan
///     `.drawingGroup()`: se rasterizan una vez en GPU, no por frame.
struct AudioQualityDetailView: View {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject private var localization = Localization.shared
    var embeddedInCard: Bool = false
    @Environment(\.dismiss) private var dismiss

    @State private var appearAnimation = false
    /// ✅ FASE C6: foto inmutable de TODO lo que pinta la vista.
    @State private var snapshot = QualitySnapshot()
    @State private var cachedFileSize: Int = 0

    private var song: Song? { audioEngine.currentSong }

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
            refreshSnapshot(loadFileSize: true)
        }
        // ✅ FASE C6: un ÚNICO punto de recálculo, disparado por cambios REALES
        // (canción, ruta, tasas, EQ, limiter, bit-perfect, idioma). Ninguno de
        // estos observe dispara por frame ni por tick del reloj.
        .onChange(of: audioEngine.currentSong?.id) { _ in refreshSnapshot(loadFileSize: true) }
        .onChange(of: audioEngine.outputSampleRate) { _ in refreshSnapshot() }
        .onChange(of: audioEngine.hardwareSampleRate) { _ in refreshSnapshot() }
        .onChange(of: audioEngine.outputPortType) { _ in refreshSnapshot() }
        .onChange(of: audioEngine.outputChannelCount) { _ in refreshSnapshot() }
        .onChange(of: audioEngine.outputLatencyMs) { _ in refreshSnapshot() }
        .onChange(of: audioEngine.ioBufferDurationMs) { _ in refreshSnapshot() }
        .onChange(of: audioEngine.requestedIOBufferDurationMs) { _ in refreshSnapshot() }
        .onChange(of: audioEngine.isEQEnabled) { _ in refreshSnapshot() }
        .onChange(of: audioEngine.eqPreset) { _ in refreshSnapshot() }
        .onChange(of: audioEngine.isLimiterEnabled) { _ in refreshSnapshot() }
        .onChange(of: audioEngine.isMonoAudioEnabled) { _ in refreshSnapshot() }
        .onChange(of: audioEngine.isBitPerfect) { _ in refreshSnapshot() }
        .onChange(of: audioEngine.isUsingFallback) { _ in refreshSnapshot() }
        .onChange(of: localization.currentLanguage) { _ in refreshSnapshot() }
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
                gainSection
                bufferSection
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
                    LazyVStack(spacing: 18) {
                        headerCard
                        signalChainSection
                        gainSection
                        bufferSection
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

    // MARK: - Header + spec sheet del archivo (C2)
    private var headerCard: some View {
        VStack(spacing: 14) {
            ZStack {
                // ✅ 60fps: gradiente ESTÁTICO (se rasteriza UNA vez, no por frame)
                Circle()
                    .fill(AppTheme.accentGradient(opacity: 0.15))
                    .frame(width: 88, height: 88)

                Circle()
                    .stroke(AppTheme.accentGradient(opacity: 0.4), lineWidth: 2)
                    .frame(width: 76, height: 76)

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

            // ✅ Badge de calidad (Hi-Res / Lossless / Comprimido)
            Text(snapshot.qualityCategory)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(2)
                .foregroundStyle(.white)
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
                Text(snapshot.title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text(snapshot.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if snapshot.hasSong {
                specSheet
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground).opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.25), .white.opacity(0.05), .clear],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .opacity(appearAnimation ? 1 : 0)
        .scaleEffect(appearAnimation ? 1 : 0.95)
        .animation(.easeOut(duration: 0.3), value: appearAnimation)
    }

    /// ✅ C2 — Spec sheet tipo DAC en tres niveles de lectura:
    ///   1. La resolución REAL ("24-bit / 96 kHz") en 28 pt monoespaciado con el
    ///      acento de la portada: el dato que el usuario audiófilo busca primero.
    ///   2. El resumen del archivo ("ALAC · 2 canales · 6:42 · 189 MB") en 12 pt.
    ///   3. El códec exacto con su FourCC ("Codec: ALAC (FourCC 'alac')") en 10 pt.
    private var specSheet: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(snapshot.resolution)
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundStyle(AppTheme.accentGradient)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityLabel(snapshot.resolution)

            Text(snapshot.fileLine)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(snapshot.codecLine)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: - C3: Cadena de procesamiento con iconos y subtítulos
    private var signalChainSection: some View {
        settingsSection(title: Localization.localized("quality.signalChain"), icon: "arrow.triangle.branch") {
            VStack(spacing: 0) {
                chainNode(icon: "doc.fill",
                          title: Localization.localized("quality.sourceFile"),
                          detail: snapshot.sourceDetail,
                          color: AppTheme.accent)
                chainArrow
                chainNode(icon: "waveform.badge.magnifyingglass",
                          title: Localization.localized("quality.decoder"),
                          detail: snapshot.decoderDetail,
                          color: .indigo)
                chainArrow
                chainNode(icon: "engine.combustion",
                          title: Localization.localized("quality.audioEngine"),
                          detail: snapshot.engineDetail,
                          color: audioEngine.isUsingFallback ? .orange : AppTheme.accent)
                chainArrow
                chainNode(icon: "slider.horizontal.3",
                          title: Localization.localized("quality.equalizer"),
                          detail: snapshot.eqDetail,
                          color: audioEngine.isEQEnabled && audioEngine.eqPreset != .flat ? AppTheme.accent : .gray)
                chainArrow
                chainNode(icon: outputIcon,
                          title: Localization.localized("quality.output"),
                          detail: snapshot.outputDetail,
                          color: .orange)

                // ✅ C3: chips de estado de la cadena ("Limiter: ON (0.99)",
                // "Bit-perfect: SÍ", "Mono: ON"), solo los que aplican.
                if !snapshot.chainChips.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(snapshot.chainChips, id: \.self) { chip in
                            Text(chip)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.accent)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background {
                                    Capsule().fill(AppTheme.accent.opacity(0.12))
                                }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 10)
                }
            }
        }
    }

    private var chainArrow: some View {
        ZStack {
            // ✅ 60fps: barra de conexión estática (sin animación por frame)
            RoundedRectangle(cornerRadius: 1)
                .fill(
                    LinearGradient(
                        colors: [AppTheme.accent.opacity(0), AppTheme.accent.opacity(0.5), AppTheme.accent.opacity(0)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 2, height: 18)
                .opacity(1)

            // ✅ 60fps: punto de flujo estático
            Circle()
                .fill(LinearGradient(
                    colors: [AppTheme.accent, AppTheme.accent.opacity(0.5)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .frame(width: 4, height: 4)
                .offset(y: 9)
                .opacity(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 20)
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

    // MARK: - C4: Ganancia y procesamiento (audiófila)
    private var gainSection: some View {
        settingsSection(title: Localization.localized("quality.gainProcessing"), icon: "dial.high") {
            detailRow(Localization.localized("quality.baseGain"), snapshot.baseGainLabel)
            detailRow(Localization.localized("quality.eqHeadroom"), snapshot.eqHeadroomLabel)
            detailRow(Localization.localized("quality.effectiveGain"), snapshot.effectiveGainLabel)
            detailRow(Localization.localized("quality.route"), snapshot.processingRouteLabel)
            detailRow(Localization.localized("quality.bluetoothCodec"), snapshot.bluetoothCodecLabel)
            detailRow(Localization.localized("quality.bitPerfect"),
                      snapshot.bitPerfectLabel,
                      isHighlighted: audioEngine.isBitPerfect)
            if let cause = snapshot.bitPerfectCauseLabel {
                detailRow("ℹ️", cause)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - C5: Búfer y latencia (telemetría REAL de la sesión)
    private var bufferSection: some View {
        settingsSection(title: Localization.localized("quality.bufferLatency"), icon: "waveform.path.ecg") {
            detailRow(Localization.localized("quality.outputLatency"), snapshot.outputLatencyLabel)
            detailRow(Localization.localized("quality.ioBufferDuration"), snapshot.ioBufferLabel)
            detailRow(Localization.localized("quality.requestedBuffer"), snapshot.requestedBufferLabel)
            detailRow(Localization.localized("quality.fileRate"), snapshot.fileRateLabel)
            detailRow(Localization.localized("quality.negotiatedRate"), snapshot.negotiatedRateLabel)
            detailRow(Localization.localized("quality.hardwareRate"), snapshot.hardwareRateLabel)
        }
    }

    // MARK: - Detalles del archivo
    private var fileDetailsSection: some View {
        settingsSection(title: Localization.localized("quality.file"), icon: "info.circle") {
            detailRow(Localization.localized("quality.format"), snapshot.formatLabel)
            detailRow(Localization.localized("quality.sampleRate"), snapshot.sampleRateLabel)
            detailRow(Localization.localized("quality.bitDepth"), snapshot.bitDepthLabel)
            detailRow(Localization.localized("quality.channels"), snapshot.channelsLabel)
            detailRow(Localization.localized("quality.duration"), snapshot.durationLabel)
            detailRow(Localization.localized("quality.fileSize"), snapshot.fileSizeLabel)
            detailRow(Localization.localized("quality.estBitrate"), snapshot.bitrateLabel)
        }
    }

    // MARK: - Detalles de salida
    private var outputDetailsSection: some View {
        settingsSection(title: Localization.localized("quality.outputDetails"), icon: "hifispeaker") {
            detailRow(Localization.localized("quality.route"), snapshot.routeLabel)
            detailRow(Localization.localized("quality.outputFrequency"), snapshot.outputFrequencyLabel)
            detailRow(Localization.localized("quality.outputChannels"), snapshot.outputChannelsLabel)
            detailRow(Localization.localized("quality.routeType"), snapshot.routeTypeLabel)
            // ✅ 3.0.1: telemetría REAL del enlace (lo único que iOS expone del
            // dispositivo conectado): canales máximos, latencia y buffer concedido.
            detailRow(Localization.localized("quality.maxOutputChannels"), snapshot.maxChannelsLabel)
            detailRow(Localization.localized("quality.outputLatency"), snapshot.outputLatencyLabel)
            detailRow(Localization.localized("quality.ioBufferDuration"), snapshot.ioBufferLabel)
            // ✅ Se dice explícitamente qué NO se puede saber, en vez de insinuar
            // capacidades del DAC que iOS no publica.
            detailRow("ℹ️", Localization.localized("quality.dacLimitNote"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Información Audiófila
    private var audiophileInfoSection: some View {
        settingsSection(title: "Audiófilo", icon: "waveform.circle") {
            // ✅ A9+C3: el fallback a AVPlayer deja de ser invisible. Si el motor
            // propio falló (formato no soportado, archivo ilegible, engine que no
            // arranca), la reproducción sigue por AVPlayer perdiendo EQ, mono,
            // headroom y bit-perfect: había que poder verlo sin abrir los logs.
            // Aparece y desaparece SOLO (condición isUsingFallback): `audioEngine`
            // es @ObservedObject y el flag es @Published.
            if audioEngine.isUsingFallback {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Localization.localized("quality.fallbackEngine"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(Localization.localized("quality.fallbackEngineHint"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18).padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(UIColor.tertiarySystemBackground).opacity(0.4))
                )
            }

            // ✅ AUDIÓFILO: Indicador Bit-Perfect (la causa exacta vive en la
            // sección de ganancia, junto al resto de la aritmética de señal).
            detailRow(Localization.localized("quality.bitPerfect"),
                      snapshot.bitPerfectLabel,
                      isHighlighted: audioEngine.isBitPerfect)

            // ✅ AUDIÓFILO: Codec Bluetooth (si aplica)
            if !audioEngine.bluetoothCodec.isEmpty {
                detailRow(Localization.localized("quality.bluetoothCodec"), audioEngine.bluetoothCodec)
                detailRow("ℹ️", Localization.localized("quality.iosBluetoothLimit"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            // ✅ AUDIÓFILO: DAC USB (si aplica)
            if !audioEngine.usbDACInfo.isEmpty {
                detailRow(Localization.localized("quality.usbDAC"), audioEngine.usbDACInfo)
            }

            // ✅ AUDIÓFILO: Modo de sesión
            if !audioEngine.audioSessionMode.isEmpty {
                detailRow(Localization.localized("quality.sessionMode"), audioEngine.audioSessionMode)
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

    // MARK: - C6: construcción de la foto inmutable (FUERA del body)
    /// Recalcula TODOS los strings/números de la vista. `loadFileSize` lanza la
    /// lectura de disco (solo al aparecer o al cambiar de canción: el tamaño del
    /// archivo no cambia por sí solo mientras suena).
    private func refreshSnapshot(loadFileSize: Bool = false) {
        let engine = audioEngine
        let song = engine.currentSong
        var s = QualitySnapshot()

        s.title = song?.title ?? Localization.localized("quality.noSong")
        s.subtitle = song?.displaySubtitle ?? "—"
        s.qualityCategory = qualityCategory(for: song)
        s.hasSong = song != nil

        // ---- Archivo fuente (C2) ----
        if let song {
            s.resolution = resolutionText(for: song)
            s.fileLine = fileLineText(for: song)
            s.codecLine = codecLineText(for: song)
            s.sourceDetail = "\(formatShort(for: song)) · \(bitDepthRateShort(for: song))"
            s.formatLabel = formatLabel(for: song)
            s.sampleRateLabel = sampleRateLabel(for: song)
            s.bitDepthLabel = bitDepthLabel(for: song)
            s.channelsLabel = channelsLabel(for: song)
            s.durationLabel = durationLabel(for: song)
            s.bitrateLabel = bitrateLabel()
        }
        s.fileSizeLabel = fileSizeLabel()

        // ---- Cadena (C3) ----
        s.decoderDetail = engine.isUsingFallback
            ? Localization.localized("quality.decoderFallback")
            : Localization.localized("quality.decoderNative")
        let engineRate = engine.outputSampleRate > 0
            ? AlbumDetailView.khzLabel(engine.outputSampleRate)
            : "—"
        s.engineDetail = engine.isUsingFallback
            ? "AVPlayer · \(engineRate)"
            : "AVAudioEngine · \(engineRate)"
        s.eqDetail = eqDetailText()
        s.outputDetail = outputDetailText()
        s.chainChips = chainChips()

        // ---- Salida ----
        s.routeLabel = engine.routeDisplay
        s.outputFrequencyLabel = engine.outputSampleRate > 0 ? "\(Int(engine.outputSampleRate)) Hz" : "—"
        s.outputChannelsLabel = engine.outputChannelCount > 0 ? engine.outputChannelCount.description : "—"
        s.routeTypeLabel = outputTypeLabel()
        s.maxChannelsLabel = engine.maximumOutputChannels > 0 ? engine.maximumOutputChannels.description : "—"

        // ---- Ganancia y procesamiento (C4) ----
        s.baseGainLabel = engine.isLimiterEnabled
            ? String(format: "0.99 (%@)", Localization.localized("quality.gainLimiter"))
            : String(format: "1.00 (%@)", Localization.localized("quality.gainBitPerfectPossible"))
        s.eqHeadroomLabel = String(format: "%.2f dB", engine.appliedEQHeadroomDB)
        s.effectiveGainLabel = String(format: "%.2f", engine.effectiveOutputGain)
        s.processingRouteLabel = processingRouteLabel()
        s.bluetoothCodecLabel = processingBluetoothCodecLabel()
        s.bitPerfectLabel = engine.isBitPerfect
            ? Localization.localized("quality.bitPerfectYes")
            : Localization.localized("quality.bitPerfectNo")
        s.bitPerfectCauseLabel = bitPerfectCauseText()

        // ---- Búfer y latencia (C5) ----
        s.outputLatencyLabel = msLabel(engine.outputLatencyMs)
        s.ioBufferLabel = msLabel(engine.ioBufferDurationMs)
        s.requestedBufferLabel = engine.requestedIOBufferDurationMs > 0
            ? String(format: "%.2f ms", engine.requestedIOBufferDurationMs)
            : Localization.localized("quality.bufferDecidedByIOS")
        let fileRate = engine.sampleRateDisplay > 0 ? engine.sampleRateDisplay : (song?.sampleRate ?? 0)
        s.fileRateLabel = hertzLabel(fileRate)
        s.negotiatedRateLabel = hertzLabel(engine.outputSampleRate)
        s.hardwareRateLabel = hertzLabel(engine.hardwareSampleRate)

        snapshot = s

        // ✅ FASE C6: el tamaño en disco se lee en background UNA vez por canción
        // (no en el render) y, al llegar, se recalcula la foto: así la spec sheet
        // aparece completa sin tocar el hilo principal.
        if loadFileSize, let url = song?.url {
            DispatchQueue.global(qos: .userInitiated).async {
                let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
                DispatchQueue.main.async {
                    guard self.cachedFileSize != size else { return }
                    self.cachedFileSize = size
                    self.refreshSnapshot()
                }
            }
        }
    }

    /// ✅ C5: "48,000 Hz" (miles con separador, como las spec sheets de DAC).
    private func hertzLabel(_ value: Double) -> String {
        guard value > 0 else { return "—" }
        let formatted = Self.integerFormatter.string(from: NSNumber(value: Int(value.rounded())))
        return "\(formatted ?? "\(Int(value))") Hz"
    }

    /// ✅ Formateador compartido y creado UNA vez (nunca dentro del body).
    private static let integerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private func msLabel(_ value: Double) -> String {
        value > 0 ? String(format: "%.2f ms", value) : "—"
    }

    // MARK: - Textos del archivo (C2)

    /// Resolución REAL: "24-bit / 96 kHz". Usa khzLabel para no truncar (44.1 kHz).
    private func resolutionText(for song: Song) -> String {
        var parts: [String] = []
        if song.bitDepth > 0 { parts.append("\(song.bitDepth)-bit") }
        if song.sampleRate > 0 { parts.append(AlbumDetailView.khzLabel(song.sampleRate)) }
        guard !parts.isEmpty else { return "—" }
        return parts.joined(separator: " / ")
    }

    /// Resumen de una línea: "ALAC · 2 canales · 6:42 · 189 MB".
    private func fileLineText(for song: Song) -> String {
        var parts: [String] = [formatShort(for: song)]
        if song.channelCount > 0 {
            parts.append("\(song.channelCount) \(Localization.localized("quality.channelsPlural"))")
        }
        if song.duration > 0 {
            parts.append(durationLabel(for: song))
        }
        if cachedFileSize > 0 {
            parts.append(sizeShortText())
        }
        return parts.joined(separator: " · ")
    }

    /// Códec exacto con su FourCC: "Codec: ALAC (FourCC 'alac')".
    private func codecLineText(for song: Song) -> String {
        let label = Localization.localized("quality.codec")
        if let codec = song.codecDisplayName, let fourCC = song.codecName, !fourCC.isEmpty {
            return "\(label): \(codec) (FourCC '\(fourCC)')"
        }
        if let codec = song.codecDisplayName {
            return "\(label): \(codec)"
        }
        // Caché antiguo sin FourCC: se dice el formato deducido, sin inventar codec.
        return "\(label): \(formatShort(for: song))"
    }

    /// Etiqueta CORTA del formato ("ALAC", "FLAC", "MP3"...) para las líneas
    /// compactas de la cadena.
    private func formatShort(for song: Song) -> String {
        if let codec = song.codecDisplayName { return codec }
        let ext = song.url.pathExtension.uppercased()
        return ext.isEmpty ? Localization.localized("quality.unknown") : ext
    }

    /// "24/96" (bits/tasa), como lo escribe PowerAmp en la cadena.
    private func bitDepthRateShort(for song: Song) -> String {
        let bits = song.bitDepth > 0 ? "\(song.bitDepth)" : "—"
        guard song.sampleRate > 0 else { return bits }
        let rate = song.sampleRate / 1000
        let rateText = rate == rate.rounded() ? "\(Int(rate))" : String(format: "%.1f", rate)
        return "\(bits)/\(rateText)"
    }

    /// "10 bandas · Rock" si el EQ procesa; "Bypass (Flat)" si no.
    private func eqDetailText() -> String {
        let bands = audioEngine.eqPreset.gains.count
        let bandsText = "\(bands) \(Localization.localized("format.bands"))"
        if audioEngine.isEQEnabled && audioEngine.eqPreset != .flat {
            return "\(bandsText) · \(audioEngine.eqPreset.displayName)"
        }
        return "\(Localization.localized("quality.bypass")) (\(EQPreset.flat.displayName))"
    }

    private func outputDetailText() -> String {
        var parts: [String] = [audioEngine.routeDisplay]
        if audioEngine.outputSampleRate > 0 {
            // ✅ Helper compartido: "44.1 kHz" exacto, no "44 kHz" truncado.
            parts.append(AlbumDetailView.khzLabel(audioEngine.outputSampleRate))
        }
        if audioEngine.outputChannelCount > 0 {
            parts.append(audioEngine.outputChannelCount >= 2
                         ? Localization.localized("quality.stereo")
                         : Localization.localized("quality.mono"))
        }
        return parts.joined(separator: " · ")
    }

    /// ✅ C3: chips de estado SOLO cuando aplican (limiter, bit-perfect, mono).
    private func chainChips() -> [String] {
        var chips: [String] = []
        if audioEngine.isLimiterEnabled {
            chips.append("\(Localization.localized("quality.limiter")): ON (0.99)")
        }
        if audioEngine.isBitPerfect {
            chips.append("\(Localization.localized("quality.bitPerfect")): \(Localization.localized("quality.shortYes"))")
        }
        if audioEngine.isMonoAudioEnabled {
            chips.append("\(Localization.localized("quality.mono")): ON")
        }
        return chips
    }

    /// ✅ C4: "Cable" / "Bluetooth" / "Interna" según el portType real.
    private func processingRouteLabel() -> String {
        switch audioEngine.outputPortType {
        case AVAudioSession.Port.bluetoothA2DP.rawValue,
             AVAudioSession.Port.bluetoothLE.rawValue,
             AVAudioSession.Port.bluetoothHFP.rawValue,
             AVAudioSession.Port.airPlay.rawValue:
            return Localization.localized("quality.routeBluetooth")
        case AVAudioSession.Port.headphones.rawValue,
             AVAudioSession.Port.usbAudio.rawValue,
             AVAudioSession.Port.carAudio.rawValue:
            return Localization.localized("quality.routeWired")
        default:
            return Localization.localized("quality.internal")
        }
    }

    /// ✅ C4: codec del enlace Bluetooth (iOS lo gestiona → A2DP/HFP/BLE o "—").
    private func processingBluetoothCodecLabel() -> String {
        switch audioEngine.outputPortType {
        case AVAudioSession.Port.bluetoothA2DP.rawValue:
            return Localization.localized("quality.bluetoothA2DP")
        case AVAudioSession.Port.bluetoothHFP.rawValue:
            return Localization.localized("quality.bluetoothHFP")
        case AVAudioSession.Port.bluetoothLE.rawValue:
            return Localization.localized("quality.bluetoothLE")
        default:
            return "—"
        }
    }

    /// ✅ C4: causa EXACTA de la pérdida de bit-perfect, localizada desde el enum
    /// estructurado que publica el motor (no una cadena en español).
    private func bitPerfectCauseText() -> String? {
        guard let reason = audioEngine.bitPerfectBlockReason else { return nil }
        switch reason {
        case .dolbyAVPlayer:
            return Localization.localized("quality.causeDolby")
        case .fallbackPlayer:
            return Localization.localized("quality.causeFallback")
        case .unknownSourceRate:
            return Localization.localized("quality.causeUnknownRate")
        case .resampling(let source, let output):
            return String(
                format: Localization.localized("quality.causeResampling"),
                AlbumDetailView.khzLabel(source),
                AlbumDetailView.khzLabel(output)
            )
        case .eqOrMono:
            return Localization.localized("quality.causeProcessing")
        case .limiter:
            return Localization.localized("quality.causeLimiter")
        case .nonWiredRoute:
            return Localization.localized("quality.causeRoute")
        }
    }

    // MARK: - Labels de archivo

    private func formatLabel(for song: Song) -> String {
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

    private func sampleRateLabel(for song: Song) -> String {
        guard song.sampleRate > 0 else { return "—" }
        let base = AlbumDetailView.khzLabel(song.sampleRate)
        return song.sampleRate > 48000 ? "\(base) (Hi-Res)" : base
    }

    private func channelsLabel(for song: Song) -> String {
        guard song.channelCount > 0 else { return "—" }
        switch song.channelCount {
        case 1: return "1 (\(Localization.localized("quality.mono")))"
        case 2: return "2 (\(Localization.localized("quality.stereo")))"
        default: return "\(song.channelCount) (\(Localization.localized("quality.surround")))"
        }
    }

    /// ✅ Profundidad REAL: lossless muestra sus bits (16/24/32). Los codecs con
    /// pérdida (MP3/AAC, bitDepth == 0) NO tienen profundidad lineal: "—" en vez
    /// de un valor inventado (los kbps ya tienen su propia fila).
    private func bitDepthLabel(for song: Song) -> String {
        song.bitDepth > 0 ? "\(song.bitDepth) bits" : "—"
    }

    private func durationLabel(for song: Song) -> String {
        guard song.duration > 0 else { return "—" }
        let minutes = Int(song.duration) / 60
        let seconds = Int(song.duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func fileSizeLabel() -> String {
        guard song != nil, cachedFileSize > 0 else { return "—" }
        return sizeShortText()
    }

    /// "189.0 MB" / "8.4 MB" / "740 KB".
    private func sizeShortText() -> String {
        if cachedFileSize > 1_048_576 { return String(format: "%.1f MB", Double(cachedFileSize) / 1_048_576) }
        return String(format: "%.0f KB", Double(cachedFileSize) / 1024)
    }

    private func bitrateLabel() -> String {
        guard let song = song, song.duration > 0, cachedFileSize > 0 else { return "—" }
        let kbps = Int((Double(cachedFileSize) * 8) / song.duration / 1000)
        return "\(kbps) kbps"
    }

    /// ✅ Detección por portType, independiente del idioma del sistema.
    private func outputTypeLabel() -> String {
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

    /// Categoría de calidad: Hi-Res (>48 kHz), Lossless (CD/48) o Comprimido.
    private func qualityCategory(for song: Song?) -> String {
        guard let song, song.sampleRate > 0 else { return Localization.localized("quality.unknownQuality") }
        if song.sampleRate > 48000 { return Localization.localized("quality.hiResAudio") }
        if song.isLossless { return Localization.localized("quality.losslessQuality") }
        return Localization.localized("quality.compressedQuality")
    }

    // MARK: - Componentes reutilizables (optimizados con drawingGroup)
    @ViewBuilder
    private func chainNode(icon: String, title: String, detail: String, color: Color) -> some View {
        HStack(spacing: 14) {
            ZStack {
                // ✅ 60fps: fondo sólido (sin gradiente costoso por frame)
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
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(isHighlighted ? AppTheme.accent : .primary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AnyShapeStyle(isHighlighted ? AnyShapeStyle(AppTheme.accentGradient(opacity: 0.1)) : AnyShapeStyle(Color(UIColor.tertiarySystemBackground).opacity(0.4))))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isHighlighted ? AppTheme.accent.opacity(0.3) : Color.clear, lineWidth: 1)
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

// MARK: - C6: foto inmutable de la vista
/// Todos los textos que pinta `AudioQualityDetailView`, ya formateados. El body
/// solo lee campos de esta estructura: ningún cálculo de strings ni de disco
/// ocurre durante el render (clave para 60 fps estables en el A11).
private struct QualitySnapshot {
    // Cabecera y spec sheet (C2)
    var title = "—"
    var subtitle = "—"
    var qualityCategory = ""
    var resolution = "—"
    var fileLine = "—"
    var codecLine = "—"
    var hasSong = false
    // Cadena de procesamiento (C3)
    var sourceDetail = "—"
    var decoderDetail = "—"
    var engineDetail = "—"
    var eqDetail = "—"
    var outputDetail = "—"
    var chainChips: [String] = []
    // Archivo
    var formatLabel = "—"
    var sampleRateLabel = "—"
    var bitDepthLabel = "—"
    var channelsLabel = "—"
    var durationLabel = "—"
    var fileSizeLabel = "—"
    var bitrateLabel = "—"
    // Salida
    var routeLabel = "—"
    var outputFrequencyLabel = "—"
    var outputChannelsLabel = "—"
    var routeTypeLabel = "—"
    var maxChannelsLabel = "—"
    // Ganancia y procesamiento (C4)
    var baseGainLabel = "—"
    var eqHeadroomLabel = "—"
    var effectiveGainLabel = "—"
    var processingRouteLabel = "—"
    var bluetoothCodecLabel = "—"
    var bitPerfectLabel = "—"
    var bitPerfectCauseLabel: String?
    // Búfer y latencia (C5)
    var outputLatencyLabel = "—"
    var ioBufferLabel = "—"
    var requestedBufferLabel = "—"
    var fileRateLabel = "—"
    var negotiatedRateLabel = "—"
    var hardwareRateLabel = "—"
}
