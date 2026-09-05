import SwiftUI

/// Ventana emergente estilo PowerAmp: muestra la calidad del archivo fuente
/// y la cadena de procesamiento completa hasta la salida física.
struct AudioQualityDetailView: View {
    @ObservedObject var audioEngine: AudioEngine
    var embeddedInCard: Bool = false
    @Environment(\.dismiss) private var dismiss

    private var song: Song? { audioEngine.currentSong }

    var body: some View {
        if embeddedInCard {
            embeddedContent
        } else {
            fullScreenContent
        }
    }

    // MARK: - Contenido embebido (para tarjeta modal)
    private var embeddedContent: some View {
        ScrollView {
            VStack(spacing: 18) {
                headerCard
                signalChainSection
                fileDetailsSection
                outputDetailsSection
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Cuerpo completo con chrome de navegación
    private var fullScreenContent: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(UIColor.systemBackground), Color(UIColor.secondarySystemBackground)],
                    startPoint: .top, endPoint: .bottom
                ).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        headerCard
                        signalChainSection
                        fileDetailsSection
                        outputDetailsSection
                    }
                    .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(UIColor.systemBackground).opacity(0.92), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Calidad de audio")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.75)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .accessibilityLabel("Calidad de audio")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") { dismiss() }
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
        }
    }

    // MARK: - Header (resumen de calidad)
    private var headerCard: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 72, height: 72)
                Image(systemName: "waveform.badge.magnifyingglass")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            Text(qualityBadge)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )

            Text(song?.title ?? "Sin canción")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary).lineLimit(2).multilineTextAlignment(.center)

            Text(song?.displaySubtitle ?? "—")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 20)
        .nativeGlass(cornerRadius: 24)
    }

    private var qualityBadge: String {
        guard let song = song else { return "—" }
        if song.sampleRate > 48000 || song.bitDepth > 16 { return "HI-RES AUDIO" }
        if song.sampleRate > 0 { return "CALIDAD LOSSLESS" }
        return "CALIDAD ESTÁNDAR"
    }

    // MARK: - Cadena de procesamiento
    private var signalChainSection: some View {
        settingsSection(title: "Cadena de procesamiento", icon: "arrow.triangle.branch") {
            VStack(spacing: 0) {
                chainNode(icon: "doc.fill", title: "Archivo fuente", detail: fileSummary, color: .purple, isFirst: true)
                chainArrow
                chainNode(icon: "square.stack.3d.up.badge.down", title: "Decodificador", detail: "AVAudioFile · Lossless", color: .indigo)
                chainArrow
                chainNode(icon: "engine.combustion", title: "Motor de audio", detail: "AVAudioEngine · \(Int(audioEngine.sampleRateDisplay / 1000)) kHz", color: .blue)
                chainArrow
                chainNode(icon: "slider.horizontal.3", title: "Ecualizador", detail: audioEngine.isEQEnabled ? "Activo · \(audioEngine.eqPreset.displayName) · 10 bandas" : "Bypass · 10 bandas", color: audioEngine.isEQEnabled ? .pink : .gray)
                chainArrow
                chainNode(icon: "forward.end.fill", title: "Crossfade", detail: audioEngine.isCrossfadeEnabled ? "Activo · \(Int(audioEngine.currentCrossfadeDuration)) s" : "Desactivado", color: audioEngine.isCrossfadeEnabled ? .teal : .gray)
                chainArrow
                chainNode(icon: outputIcon, title: "Salida", detail: outputSummary, color: .orange, isLast: true)
            }
        }
    }

    private var chainArrow: some View {
        Image(systemName: "arrow.down")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color.secondary.opacity(0.5))
            .frame(maxWidth: .infinity).padding(.vertical, 2)
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
        let route = audioEngine.currentRouteName.lowercased()
        if route.contains("bluetooth") { return "airpods.pro" }
        if route.contains("airplay") { return "airplayaudio" }
        if route.contains("altavoz") || route.contains("speaker") { return "hifispeaker.fill" }
        return "headphones"
    }

    private var outputSummary: String {
        var parts: [String] = [audioEngine.currentRouteName]
        if audioEngine.outputSampleRate > 0 { parts.append("\(Int(audioEngine.outputSampleRate / 1000)) kHz") }
        if audioEngine.outputChannelCount > 0 { parts.append(audioEngine.outputChannelCount >= 2 ? "Estéreo" : "Mono") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Detalles del archivo
    private var fileDetailsSection: some View {
        settingsSection(title: "Archivo", icon: "info.circle") {
            detailRow("Formato", formatLabel)
            detailRow("Tasa de muestreo", sampleRateLabel)
            detailRow("Profundidad de bits", song?.bitDepth.description ?? "—")
            detailRow("Canales", channelsLabel)
            detailRow("Duración", durationLabel)
            detailRow("Tamaño", fileSizeLabel)
            detailRow("Bitrate estimado", bitrateLabel)
        }
    }

    // MARK: - Detalles de salida
    private var outputDetailsSection: some View {
        settingsSection(title: "Salida", icon: "hifispeaker") {
            detailRow("Ruta", audioEngine.currentRouteName)
            detailRow("Frecuencia de salida", audioEngine.outputSampleRate > 0 ? "\(Int(audioEngine.outputSampleRate)) Hz" : "—")
            detailRow("Canales de salida", audioEngine.outputChannelCount > 0 ? audioEngine.outputChannelCount.description : "—")
            detailRow("Tipo de ruta", outputTypeLabel)
        }
    }

    // MARK: - Labels calculados
    private var formatLabel: String {
        guard let song = song else { return "—" }
        let ext = song.url.pathExtension.uppercased()
        switch ext {
        case "FLAC": return "FLAC (Free Lossless Audio Codec)"
        case "ALAC", "M4A": return "ALAC/M4A (Apple Lossless)"
        case "MP3": return "MP3 (MPEG Layer III)"
        case "WAV", "WAVE": return "WAV (PCM sin comprimir)"
        case "AIFF", "AIF": return "AIFF (PCM sin comprimir)"
        case "AAC": return "AAC (Advanced Audio Coding)"
        default: return ext.isEmpty ? "Desconocido" : ext
        }
    }

    private var sampleRateLabel: String {
        guard let song = song, song.sampleRate > 0 else { return "—" }
        return song.sampleRate >= 48000 ? "\(Int(song.sampleRate / 1000)) kHz (Hi-Res)" : "\(Int(song.sampleRate)) Hz"
    }

    private var channelsLabel: String {
        guard let song = song, song.channelCount > 0 else { return "—" }
        switch song.channelCount {
        case 1: return "1 (Mono)"
        case 2: return "2 (Estéreo)"
        default: return "\(song.channelCount) (Multicanal)"
        }
    }

    private var durationLabel: String {
        guard let song = song, song.duration > 0 else { return "—" }
        let minutes = Int(song.duration) / 60
        let seconds = Int(song.duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var fileSizeLabel: String {
        guard let song = song else { return "—" }
        let size = (try? FileManager.default.attributesOfItem(atPath: song.url.path)[.size] as? Int) ?? 0
        guard size > 0 else { return "—" }
        if size > 1_048_576 { return String(format: "%.1f MB", Double(size) / 1_048_576) }
        return String(format: "%.0f KB", Double(size) / 1024)
    }

    private var bitrateLabel: String {
        guard let song = song, song.duration > 0,
              let size = (try? FileManager.default.attributesOfItem(atPath: song.url.path)[.size] as? Int), size > 0 else { return "—" }
        let kbps = Int((Double(size) * 8) / song.duration / 1000)
        return "\(kbps) kbps"
    }

    private var outputTypeLabel: String {
        let route = audioEngine.currentRouteName.lowercased()
        if route.contains("bluetooth") { return "Inalámbrica (Bluetooth)" }
        if route.contains("airplay") { return "Inalámbrica (AirPlay)" }
        if route.contains("altavoz") || route.contains("speaker") { return "Interna (Altavoz)" }
        if route.contains("audífonos") || route.contains("headphones") { return "Conectada (Audífonos)" }
        if route.contains("usb") { return "Conectada (USB/DAC)" }
        return "Interna"
    }

    // MARK: - Componentes reutilizables
    @ViewBuilder
    private func chainNode(icon: String, title: String, detail: String, color: Color, isFirst: Bool = false, isLast: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(color.opacity(0.12))
                }

            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary)
                Text(detail).font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.85)
            }

            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, isFirst || isLast ? 14 : 12)
    }

    @ViewBuilder
    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(.primary).multilineTextAlignment(.trailing).lineLimit(2)
        }
        .padding(.horizontal, 16).padding(.vertical, 12).contentShape(Rectangle())
    }

    // MARK: - Section Builder
    @ViewBuilder
    private func settingsSection<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28, height: 28)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.accentColor.opacity(0.12))
                    }
                Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(.primary)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content()
            }
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial)
            }
        }
    }
}