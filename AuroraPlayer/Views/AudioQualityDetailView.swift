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
    @State private var signalFlow = false
    @State private var headerPulse = false
    // ✅ OPTIMIZACIÓN: cachear valores que requieren acceso a disco para no
    // leer el archivo en cada renderizado (fileSizeLabel, bitrateLabel).
    @State private var cachedFileSize: Int = 0
    @State private var cachedDuration: TimeInterval = 0

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
            withAnimation(.easeOut(duration: 0.5)) { appearAnimation = true }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { headerPulse = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeInOut(duration: 0.8)) { signalFlow = true }
            }
            // ✅ OPTIMIZACIÓN: cargar valores de disco UNA VEZ en background.
            if let song = song {
                let path = song.url.path
                DispatchQueue.global(qos: .userInitiated).async {
                    let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
                    DispatchQueue.main.async {
                        self.cachedFileSize = size
                        self.cachedDuration = song.duration
                    }
                }
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
                // ✅ Fondo con gradiente sutil y profundidad
                LinearGradient(
                    colors: [
                        Color(UIColor.systemBackground),
                        Color(UIColor.tertiarySystemBackground).opacity(0.5),
                        Color(UIColor.systemBackground)
                    ],
                    startPoint: .top, endPoint: .bottom
                ).ignoresSafeArea()

                ScrollView {
                    // ✅ OPTIMIZACIÓN: LazyVStack para lazy-loading de secciones.
                    LazyVStack(spacing: 18) {
                        headerCard
                        signalChainSection
                        fileDetailsSection
                        outputDetailsSection
                        deviceSection
                    }
                    .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(UIColor.systemBackground).opacity(0.92), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button(Localization.localized("quality.done")) { dismiss() }
                        .foregroundStyle(AppTheme.accent)
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
        }
    }

    // MARK: - Header (resumen de calidad con animación, optimizado con drawingGroup)
    private var headerCard: some View {
        VStack(spacing: 18) {
            ZStack {
                // ✅ Halo animado con AngularGradient (drawingGroup para GPU)
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [
                                AppTheme.accent.opacity(0.4),
                                Color(red: 0.3, green: 0.6, blue: 1.0).opacity(0.2),
                                AppTheme.accent.opacity(0.1),
                                AppTheme.accent.opacity(0.4)
                            ],
                            center: .center,
                            startAngle: .degrees(headerPulse ? 360 : 0),
                            endAngle: .degrees(headerPulse ? 720 : 360)
                        )
                    )
                    .frame(width: 100, height: 100)
                    .blur(radius: 12)
                    .drawingGroup() // ✅ Rasteriza en GPU

                // ✅ Anillo pulsante
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [AppTheme.accent, AppTheme.accent.opacity(0.3)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 84, height: 84)
                    .scaleEffect(headerPulse ? 1.08 : 0.94)

                // ✅ Círculo interior con material
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 74, height: 74)
                    .overlay(
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 34, weight: .medium))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [AppTheme.accent, AppTheme.accent.opacity(0.5)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                    )
                    .shadow(color: AppTheme.accent.opacity(0.25), radius: 12, x: 0, y: 4)
            }
            .opacity(appearAnimation ? 1 : 0)
            .scaleEffect(appearAnimation ? 1 : 0.5)

            // ✅ Badge de calidad mejorado
            Text(qualityBadge)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(2)
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background {
                    Capsule().fill(
                        LinearGradient(
                            colors: [AppTheme.accent, AppTheme.accent.opacity(0.65)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .shadow(color: AppTheme.accent.opacity(0.35), radius: 10, y: 4)
                }
                .opacity(appearAnimation ? 1 : 0)
                .scaleEffect(appearAnimation ? 1 : 0.8)

            // ✅ Info de la canción
            VStack(spacing: 5) {
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
            .opacity(appearAnimation ? 1 : 0)
            .offset(y: appearAnimation ? 0 : 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.06), radius: 12, y: 5)
        }
        .animation(.easeOut(duration: 0.5).delay(0.1), value: appearAnimation)
    }

    private var isLossless: Bool {
        guard let song = song else { return false }
        let ext = song.url.pathExtension.uppercased()
        return ["FLAC", "WAV", "WAVE", "AIFF", "AIF", "ALAC", "M4A"].contains(ext)
    }

    private var qualityBadge: String {
        guard let song = song else { return "—" }
        let rate = song.sampleRate
        let bits = song.bitDepth
        let bitrate = estimatedBitrateKBPS(song)
        if bits >= 24 && rate >= 96000 { return Localization.localized("quality.hiResAudio") }
        if bitrate >= 700 { return Localization.localized("quality.losslessQuality") }
        if bitrate > 0 { return Localization.localized("quality.compressedQuality") }
        if rate > 0 { return Localization.localized("quality.standardQuality") }
        return Localization.localized("quality.unknownQuality")
    }

    private func estimatedBitrateKBPS(_ song: Song) -> Int {
        guard song.sampleRate > 0 && song.bitDepth > 0 && song.channelCount > 0 else {
            return 0
        }
        return Int(song.sampleRate * Double(song.bitDepth) * Double(song.channelCount) / 1000)
    }

    // MARK: - Cadena de procesamiento con flujo animado
    private var signalChainSection: some View {
        settingsSection(title: Localization.localized("quality.signalChain"), icon: "arrow.triangle.branch") {
            VStack(spacing: 0) {
                chainNode(icon: "doc.fill", title: Localization.localized("quality.sourceFile"), detail: fileSummary, color: .accentColor, index: 0)
                chainArrow
                chainNode(icon: "waveform", title: Localization.localized("quality.decoder"), detail: "AVAudioFile · \(isLossless ? Localization.localized("quality.lossless") : Localization.localized("quality.compressed"))", color: .indigo, index: 1)
                chainArrow
                chainNode(icon: "engine.combustion", title: Localization.localized("quality.audioEngine"), detail: "AVAudioEngine · \(Int(audioEngine.sampleRateDisplay / 1000)) kHz", color: .accentColor, index: 2)
                chainArrow
                chainNode(icon: "slider.horizontal.3", title: Localization.localized("quality.equalizer"), detail: audioEngine.isEQEnabled ? "\(Localization.localized("quality.active")) · \(audioEngine.eqPreset.displayName) · 10 \(Localization.localized("format.bands"))" : "\(Localization.localized("quality.bypass")) · 10 \(Localization.localized("format.bands"))", color: audioEngine.isEQEnabled ? .accentColor : .gray, index: 3)
                chainArrow
                chainNode(icon: outputIcon, title: Localization.localized("quality.output"), detail: outputSummary, color: .orange, index: 4)
            }
        }
    }

    private var chainArrow: some View {
        ZStack {
            // ✅ Línea de conexión animada
            RoundedRectangle(cornerRadius: 1)
                .fill(
                    LinearGradient(
                        colors: [AppTheme.accent.opacity(0), AppTheme.accent.opacity(0.5), AppTheme.accent.opacity(0)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 2, height: signalFlow ? 18 : 8)
                .opacity(signalFlow ? 1 : 0.3)

            // ✅ Punto de flujo animado
            Circle()
                .fill(AppTheme.accent)
                .frame(width: 4, height: 4)
                .offset(y: signalFlow ? 9 : 0)
                .opacity(signalFlow ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 20)
        .animation(.easeInOut(duration: 0.8).delay(0.3), value: signalFlow)
    }

    private var fileSummary: String {
        guard let song = song else { return "—" }
        var parts: [String] = []
        let format = song.formatDescription.isEmpty ? song.url.pathExtension.uppercased() : song.formatDescription
        parts.append(format)
        if song.bitDepth > 0 { parts.append("\(song.bitDepth)-bit") }
        if song.sampleRate > 0 { parts.append(song.sampleRate >= 48000 ? "\(Int(song.sampleRate / 1000)) kHz" : "\(Int(song.sampleRate)) Hz") }
        return parts.joined(separator: " · ")
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
        if audioEngine.outputSampleRate > 0 { parts.append("\(Int(audioEngine.outputSampleRate / 1000)) kHz") }
        if audioEngine.outputChannelCount > 0 { parts.append(audioEngine.outputChannelCount >= 2 ? Localization.localized("quality.stereo") : Localization.localized("quality.mono")) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Detalles del archivo
    private var fileDetailsSection: some View {
        settingsSection(title: Localization.localized("quality.file"), icon: "info.circle") {
            detailRow(Localization.localized("quality.format"), formatLabel)
            detailRow(Localization.localized("quality.sampleRate"), sampleRateLabel)
            detailRow(Localization.localized("quality.bitDepth"), song?.bitDepth.description ?? "—")
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
            detailRow(Localization.localized("quality.outputFrequency"), audioEngine.outputSampleRate > 0 ? "\(Int(audioEngine.outputSampleRate)) Hz" : "—")
            detailRow(Localization.localized("quality.outputChannels"), audioEngine.outputChannelCount > 0 ? audioEngine.outputChannelCount.description : "—")
            detailRow(Localization.localized("quality.routeType"), outputTypeLabel)
        }
    }

    // MARK: - Dispositivo
    private var deviceSection: some View {
        settingsSection(title: Localization.localized("quality.device"), icon: "iphone") {
            detailRow(Localization.localized("quality.model"), audioEngine.deviceModelName)
            detailRow(Localization.localized("quality.system"), "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
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
        return song.sampleRate >= 48000 ? "\(Int(song.sampleRate / 1000)) kHz (Hi-Res)" : "\(Int(song.sampleRate)) Hz"
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

    private var bitrateLabel: String {
        guard let song = song, cachedDuration > 0, cachedFileSize > 0 else { return "—" }
        let kbps = Int((Double(cachedFileSize) * 8) / cachedDuration / 1000)
        return "\(kbps) kbps"
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
    private func chainNode(icon: String, title: String, detail: String, color: Color, index: Int) -> some View {
        HStack(spacing: 14) {
            ZStack {
                // ✅ Fondo con gradiente sutil y borde
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.12), color.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(color.opacity(0.15), lineWidth: 0.5)
                    )

                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(color)
            }
            .drawingGroup() // ✅ Rasteriza icono + fondo

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

            // ✅ Indicador de estado activo con pulse
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .opacity(signalFlow ? 1 : 0.25)
                .scaleEffect(signalFlow ? 1.2 : 0.8)
                .animation(.easeInOut(duration: 0.6).delay(Double(index) * 0.1), value: signalFlow)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground).opacity(0.5))
        )
        .opacity(appearAnimation ? 1 : 0)
        .offset(x: appearAnimation ? 0 : -15)
        .animation(.spring(response: 0.5, dampingFraction: 0.88).delay(Double(index) * 0.06), value: appearAnimation)
    }

    @ViewBuilder
    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(UIColor.tertiarySystemBackground).opacity(0.4))
        )
    }

    // MARK: - Section Builder (mejorado visualmente)
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
                            .fill(
                                LinearGradient(
                                    colors: [AppTheme.accent, AppTheme.accent.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
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
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
            }
        }
        .opacity(appearAnimation ? 1 : 0)
        .offset(y: appearAnimation ? 0 : 18)
        .animation(.easeOut(duration: 0.45).delay(0.2), value: appearAnimation)
    }
}