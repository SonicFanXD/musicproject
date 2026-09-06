import SwiftUI
import AVFoundation
import AVKit

struct NowPlayingView: View {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var fileAccessService: FileAccessService
    // ✅ Observar el idioma: al cambiar, esta vista se re-renderiza al instante
    @ObservedObject private var localization = Localization.shared
    @Environment(\.dismiss) private var dismiss

    // Configuraciones de personalización
    @AppStorage("com.aurora.showVisualizer") private var showVisualizer = true
    @AppStorage("com.aurora.keepScreenOn") private var keepScreenOn = false
    @AppStorage("com.aurora.dynamicColor") private var dynamicColor = true
    @AppStorage("com.aurora.artworkCorner") private var artworkCorner: Double = 22
    @AppStorage("com.aurora.reduceTransparency") private var reduceTransparency = false
    // ✅ Ajuste "Mostrar letras" (antes no se aplicaba)
    @AppStorage("com.aurora.showLyricsByDefault") private var showLyricsByDefault = false

    @State private var showLyrics = false
    @State private var showEqualizer = false
    @State private var showQueue = false
    @State private var showQualityDetail = false
    @State private var isAirPlayAvailable = false
    @State private var artworkScale: CGFloat = 1.0
    @State private var progressBarWidth: CGFloat = 0
    @State private var extractedColor: Color = Color.accentColor
    // ✅ Guardamos el UIColor dominante crudo para calcular contraste
    // ✅ FIX: usar accentUIColor en vez de systemPurple hardcodeado
    @State private var extractedUIColor: UIColor = AppTheme.accentUIColor

    // ✅ Caché de color dominante por canción: evita recalcular el histograma
    // HSB al reabrir NowPlaying o re-entrar a la misma pista (60fps sin hitch)
    private static let colorCache = NSCache<NSString, UIColor>()

    // ✅ Scrub optimizado: preview local a 60fps, seek real solo al soltar
    @State private var isScrubbing = false
    @State private var scrubPreviewTime: TimeInterval = 0

    // MARK: - Adaptive sizing for iOS 16 & iPhone 8 Plus
    private var isCompactScreen: Bool {
        UIScreen.main.bounds.height < 800
    }

    private var artworkSize: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        // ✅ MEJORADO: Portada más grande y mejor centrada
        let maxByWidth = screenWidth - 40
        let maxByHeight = screenHeight * (isCompactScreen ? 0.32 : 0.42)
        return min(340, maxByWidth, maxByHeight)
    }

    private var progress: Double {
        if isScrubbing {
            guard audioEngine.duration > 0 else { return 0 }
            return min(max(scrubPreviewTime / audioEngine.duration, 0), 1)
        }
        guard audioEngine.duration > 0 else { return 0 }
        return min(max(audioEngine.currentTime / audioEngine.duration, 0), 1)
    }

    private var scrubPreviewText: String {
        formatTime(isScrubbing ? scrubPreviewTime : audioEngine.currentTime)
    }

    // ✅ Contraste: si el color dominante es claro → texto oscuro; si es oscuro → texto blanco
    private var playIconColor: Color { AppTheme.contrastingText(on: extractedUIColor) }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundView

                // ✅ DISEÑO MEJORADO: distribución equilibrada con Spacers
                // flexibles (la proporción se adapta a cualquier pantalla,
                // iPhone 8 Plus incluido) en lugar de espaciados fijos.
                VStack(spacing: 0) {
                    Spacer(minLength: isCompactScreen ? 4 : 10)

                    artworkView
                        .scaleEffect(artworkScale)
                        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: audioEngine.isPlaying)
                        .animation(.easeInOut(duration: 0.25), value: audioEngine.currentSong?.id)

                    Spacer(minLength: isCompactScreen ? 10 : 16)

                    if audioEngine.isPlaying && showVisualizer {
                        AudioVisualizer(audioEngine: audioEngine, tintColor: extractedColor)
                            .frame(height: isCompactScreen ? 30 : 44)
                            .padding(.horizontal, 40)
                            // ✅ 60fps: rasteriza las 24 barras en la GPU una vez
                            .drawingGroup()
                    }

                    Spacer(minLength: isCompactScreen ? 8 : 14)

                    songInfoView
                        .animation(.easeInOut(duration: 0.25), value: audioEngine.currentSong?.id)

                    Spacer(minLength: isCompactScreen ? 8 : 14)

                    progressView

                    Spacer(minLength: isCompactScreen ? 10 : 18)

                    controlsView

                    Spacer(minLength: isCompactScreen ? 8 : 14)

                    featureButtonsView

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
                .fixedSize(horizontal: false, vertical: true)
            }
            .onAppear {
                extractColorFromArtwork()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    artworkScale = 1.0
                }
                audioEngine.isKeepScreenOnEnabled = keepScreenOn
                // ✅ Abrir letras automáticamente si el ajuste está activado
                // y la canción tiene letras sincronizadas/plain
                if showLyricsByDefault, audioEngine.currentSong?.lyrics.isEmpty == false, !showLyrics {
                    showLyrics = true
                }
            }
            .onChange(of: audioEngine.isPlaying) { isPlaying in
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                    artworkScale = isPlaying ? 1.02 : 1.0
                }
                UIApplication.shared.isIdleTimerDisabled = keepScreenOn && isPlaying
            }
            .onChange(of: audioEngine.currentSong?.id) { _ in
                extractColorFromArtwork()
            }
            .presentationDetents([.large])
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(UIColor.systemBackground).opacity(0.92), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(Localization.localized("nowPlaying.title"))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [extractedColor, extractedColor.opacity(0.75)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .accessibilityLabel(Localization.localized("nowPlaying.title"))
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .foregroundStyle(extractedColor)
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                }
                // ✅ Botón de me gusta en la barra de navegación
                ToolbarItem(placement: .navigationBarTrailing) {
                    if let song = audioEngine.currentSong {
                        Button {
                            Haptics.light()
                            fileAccessService.toggleLike(song)
                        } label: {
                            Image(systemName: fileAccessService.isLiked(song) ? "heart.fill" : "heart")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(fileAccessService.isLiked(song) ? .red : playIconColor)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .sheet(isPresented: $showLyrics) {
                LyricsView(song: audioEngine.currentSong, audioEngine: audioEngine)
            }
            .sheet(isPresented: $showEqualizer) {
                EqualizerView(audioEngine: audioEngine)
            }
            .sheet(isPresented: $showQueue) {
                QueueView(audioEngine: audioEngine)
            }
            .overlay {
                if showQualityDetail {
                    qualityCardModal
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showQualityDetail)
        }
    }

    // MARK: - Background (respeta "Reducir transparencia")
    private var backgroundView: some View {
        Group {
            if let artwork = audioEngine.currentSong?.artwork, !reduceTransparency {
                GeometryReader { geometry in
                    ZStack {
                        Image(uiImage: artwork)
                            .resizable()
                            .interpolation(.medium)
                            .scaledToFit()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .blur(radius: 25)
                            .opacity(0.45)

                        extractedColor.opacity(0.12)
                    }
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .drawingGroup(opaque: false)
            } else {
                LinearGradient(
                    colors: [
                        Color(UIColor.systemBackground),
                        Color(UIColor.secondarySystemBackground)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Artwork (mejorado con mejor sombras y efectos)
    private var artworkView: some View {
        Group {
            if let artwork = audioEngine.currentSong?.artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .interpolation(.high) // ✅ Mejor calidad de interpolación
                    .scaledToFill()
                    .frame(width: artworkSize, height: artworkSize)
                    .clipShape(RoundedRectangle(cornerRadius: CGFloat(artworkCorner), style: .continuous))
                    // ✅ 60fps: sombra ÚNICA consolidada (la doble sombra forzaba
                    // 2 pasadas de offscreen rendering por frame; visualmente
                    // equivalente con radius medio + borde luminoso).
                    .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8)
                    .overlay(
                        // ✅ Borde con brillo sutil
                        RoundedRectangle(cornerRadius: CGFloat(artworkCorner), style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.15), extractedColor.opacity(0.2), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: CGFloat(artworkCorner), style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [extractedColor.opacity(0.3), extractedColor.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: artworkSize, height: artworkSize)

                    Image(systemName: "music.note")
                        .font(.system(size: artworkSize * 0.15, weight: .light))
                        .foregroundStyle(extractedColor.opacity(0.8))
                }
                .shadow(color: .black.opacity(0.15), radius: 15, x: 0, y: 8)
                .shadow(color: extractedColor.opacity(0.15), radius: 8, x: 0, y: 4)
            }
        }
    }

    // MARK: - Song Info (mejorado con mejor tipografía y espaciado)
    private var songInfoView: some View {
        VStack(spacing: 6) {
            // ✅ Título con gradiente sutil del color extraído (mejor tipografía)
            // ✅ 60fps: shadow removido del texto con gradiente (forzaba blur
            // offscreen por frame; el gradiente ya da suficiente profundidad).
            Text(audioEngine.currentSong?.displayName ?? "Sin canción")
                .font(.system(size: isCompactScreen ? 20 : 24, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(
                    LinearGradient(
                        colors: [playIconColor, playIconColor.opacity(0.85)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .lineLimit(2)

            Text(audioEngine.currentSong?.displaySubtitle ?? "—")
                .font(.system(size: isCompactScreen ? 14 : 16, weight: .medium))
                .foregroundStyle(AppTheme.contrastingText(on: extractedUIColor).opacity(0.75))
                .lineLimit(1)
                .padding(.horizontal, 20)

            if let song = audioEngine.currentSong, !song.audioQualityDescription.isEmpty {
                Button {
                    Haptics.light()
                    showQualityDetail = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 10, weight: .semibold))

                        Text(song.audioQualityDescription)
                            .font(.system(size: 10, weight: .medium).monospacedDigit())

                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(extractedColor.opacity(0.6))
                    }
                    .foregroundStyle(playIconColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background {
                        Capsule().fill(extractedColor.opacity(0.2))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ver detalles de calidad de audio")
            }
        }
        .padding(.horizontal, 6)
    }

    // MARK: - Progress View (scrub fluido a 60fps)
    private var progressView: some View {
        VStack(spacing: 8) {
            // ✅ FIX: .frame(maxWidth: .infinity) para que el GeometryReader
            // se expanda al ancho completo disponible. El gesture usa
            // progressBarWidth (actualizado por onAppear/onChange del
            // GeometryReader) para calcular el porcentaje de scrub.
            GeometryReader { geometry in
                // ✅ Feedback táctil: la barra engrosa al hacer scrub
                // (animación de frame → GPU, sin costo de calidad)
                let barHeight: CGFloat = isScrubbing ? 10 : 6
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: barHeight)

                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [extractedColor.opacity(0.85), extractedColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * progress, height: barHeight)
                        // ✅ Glow más notorio mientras se arrastra
                        .shadow(color: isScrubbing ? extractedColor.opacity(0.6) : extractedColor.opacity(0.3), radius: isScrubbing ? 8 : 4, x: 0, y: 0)
                        // ✅ Indicador circular al final de la barra
                        .overlay {
                            Circle()
                                .fill(.white)
                                .frame(width: isScrubbing ? 14 : 10, height: isScrubbing ? 14 : 10)
                                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 1)
                                .offset(x: (geometry.size.width * progress) - (isScrubbing ? 7 : 5))
                                .opacity(progress > 0 && progress < 1 ? 1 : 0)
                        }
                }
                .onAppear {
                    progressBarWidth = geometry.size.width
                }
                .onChange(of: geometry.size.width) { newWidth in
                    progressBarWidth = newWidth
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 10)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
            // ✅ FIX animación rara: antes había UNA animación spring sobre
            // todo el subárbol disparada por isScrubbing, lo que hacía que el
            // indicador circular "botara" cada vez que el reloj (0.3s) movía
            // el progreso. Ahora: easing lineal suave para el avance normal
            // del reloj + spring SOLO para el cambio de tamaño al arrastrar.
            .animation(.linear(duration: 0.25), value: progress)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isScrubbing)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isScrubbing = true
                        let percentage = max(0, min(1, value.location.x / progressBarWidth))
                        scrubPreviewTime = audioEngine.duration * percentage
                    }
                    .onEnded { value in
                        let percentage = max(0, min(1, value.location.x / progressBarWidth))
                        let newTime = audioEngine.duration * percentage
                        isScrubbing = false
                        audioEngine.seek(to: newTime)
                    }
            )

            HStack {
                Text(scrubPreviewText)
                    .font(.system(size: isCompactScreen ? 12 : 13, weight: isScrubbing ? .bold : .medium))
                    .foregroundStyle(isScrubbing ? playIconColor : AppTheme.contrastingText(on: extractedUIColor).opacity(0.75))
                    .monospacedDigit()
                    .animation(.easeInOut(duration: 0.15), value: isScrubbing)

                Spacer()

                Text(formatTime(audioEngine.duration))
                    .font(.system(size: isCompactScreen ? 12 : 13, weight: .medium))
                    .foregroundStyle(AppTheme.contrastingText(on: extractedUIColor).opacity(0.75))
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Controls
    private var controlsView: some View {
        HStack(spacing: isCompactScreen ? 8 : 14) {
            // Shuffle
            Button {
                Haptics.light()
                audioEngine.toggleShuffle()
            } label: {
                ZStack {
                    Capsule()
                        .fill(audioEngine.isShuffleEnabled ? extractedColor.opacity(0.25) : Color.clear)
                        .frame(width: isCompactScreen ? 42 : 46, height: isCompactScreen ? 30 : 36)

                    Image(systemName: "shuffle")
                        .font(.system(size: isCompactScreen ? 15 : 17, weight: audioEngine.isShuffleEnabled ? .bold : .semibold))
                        .foregroundStyle(audioEngine.isShuffleEnabled ? playIconColor : AppTheme.contrastingText(on: extractedUIColor).opacity(0.7))
                }
                .frame(width: isCompactScreen ? 56 : 64, height: isCompactScreen ? 56 : 64)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Previous
            Button {
                Haptics.light()
                audioEngine.playPrevious()
            } label: {
                ZStack {
                    Circle().fill(controlBackground).frame(width: isCompactScreen ? 44 : 50, height: isCompactScreen ? 44 : 50)
                    Image(systemName: "backward.fill")
                        .font(.system(size: isCompactScreen ? 16 : 18, weight: .semibold))
                        .foregroundStyle(playIconColor)
                }
                .frame(width: isCompactScreen ? 56 : 64, height: isCompactScreen ? 56 : 64)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Play/Pause (icono con contraste)
            Button {
                Haptics.medium()
                if audioEngine.isPlaying {
                    audioEngine.pause()
                } else {
                    audioEngine.resume()
                }
            } label: {
                ZStack {
                    Circle().fill(extractedColor).frame(width: isCompactScreen ? 62 : 72, height: isCompactScreen ? 62 : 72)
                    Image(systemName: audioEngine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: isCompactScreen ? 22 : 26, weight: .bold))
                        .foregroundStyle(playIconColor)
                        // ✅ Micro-animación del icono al cambiar estado (GPU)
                        .scaleEffect(audioEngine.isPlaying ? 1.0 : 1.08)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: audioEngine.isPlaying)
                }
                .shadow(color: extractedColor.opacity(audioEngine.isPlaying ? 0.4 : 0.25), radius: audioEngine.isPlaying ? 12 : 8, x: 0, y: 4)
                .animation(.easeInOut(duration: 0.3), value: audioEngine.isPlaying)
                .frame(width: isCompactScreen ? 76 : 88, height: isCompactScreen ? 76 : 88)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Next
            Button {
                Haptics.light()
                audioEngine.playNext()
            } label: {
                ZStack {
                    Circle().fill(controlBackground).frame(width: isCompactScreen ? 44 : 50, height: isCompactScreen ? 44 : 50)
                    Image(systemName: "forward.fill")
                        .font(.system(size: isCompactScreen ? 16 : 18, weight: .semibold))
                        .foregroundStyle(playIconColor)
                }
                .frame(width: isCompactScreen ? 56 : 64, height: isCompactScreen ? 56 : 64)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Repeat
            Button {
                Haptics.light()
                audioEngine.cycleRepeatMode()
            } label: {
                ZStack {
                    Capsule()
                        .fill(audioEngine.repeatMode != .off ? extractedColor.opacity(0.25) : Color.clear)
                        .frame(width: isCompactScreen ? 42 : 46, height: isCompactScreen ? 30 : 36)

                    Image(systemName: repeatIcon)
                        .font(.system(size: isCompactScreen ? 15 : 17, weight: audioEngine.repeatMode != .off ? .bold : .semibold))
                        .foregroundStyle(audioEngine.repeatMode != .off ? playIconColor : AppTheme.contrastingText(on: extractedUIColor).opacity(0.7))
                }
                .frame(width: isCompactScreen ? 56 : 64, height: isCompactScreen ? 56 : 64)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .fixedSize()
    }

    // MARK: - Feature Buttons (EQ · Letras · Cola · AirPlay en una sola línea)
    private var featureButtonsView: some View {
        let buttonSize: CGFloat = isCompactScreen ? 60 : 68
        let capsuleWidth: CGFloat = isCompactScreen ? 44 : 50
        let capsuleHeight: CGFloat = isCompactScreen ? 34 : 38
        let iconSize: CGFloat = isCompactScreen ? 15 : 17

        return HStack(spacing: isCompactScreen ? 10 : 14) {
            // Equalizador
            Button {
                Haptics.light()
                showEqualizer = true
            } label: {
                ZStack {
                    Capsule()
                        .fill(audioEngine.isEQEnabled ? extractedColor.opacity(0.25) : Color.clear)
                        .frame(width: capsuleWidth, height: capsuleHeight)

                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: iconSize, weight: audioEngine.isEQEnabled ? .bold : .semibold))
                        .foregroundStyle(audioEngine.isEQEnabled ? playIconColor : AppTheme.contrastingText(on: extractedUIColor).opacity(0.7))
                }
                .frame(width: buttonSize, height: buttonSize)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ecualizador")

            // Letras
            Button {
                Haptics.light()
                showLyrics = true
            } label: {
                ZStack {
                    Capsule()
                        .fill(audioEngine.currentSong?.lyrics.isEmpty == false ? extractedColor.opacity(0.25) : Color.clear)
                        .frame(width: capsuleWidth, height: capsuleHeight)

                    Image(systemName: audioEngine.currentSong?.lyrics.isEmpty == false ? "quote.bubble.fill" : "quote.bubble")
                        .font(.system(size: iconSize, weight: audioEngine.currentSong?.lyrics.isEmpty == false ? .bold : .semibold))
                        .foregroundStyle(audioEngine.currentSong?.lyrics.isEmpty == false ? playIconColor : AppTheme.contrastingText(on: extractedUIColor).opacity(0.7))
                }
                .frame(width: buttonSize, height: buttonSize)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Letras")

            // Cola
            Button {
                Haptics.light()
                showQueue = true
            } label: {
                ZStack {
                    Capsule()
                        .fill(audioEngine.nextUpQueue.isEmpty ? Color.clear : extractedColor.opacity(0.25))
                        .frame(width: capsuleWidth, height: capsuleHeight)

                    Image(systemName: "list.bullet")
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundStyle(audioEngine.nextUpQueue.isEmpty ? AppTheme.contrastingText(on: extractedUIColor).opacity(0.7) : playIconColor)
                }
                .frame(width: buttonSize, height: buttonSize)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cola de reproducción")

            // ✅ AirPlay (FIX): en vez de abrir un sheet con un AVRoutePickerView
            // gigante que fallaba, el picker NATIVO de iOS va superpuesto e
            // invisible sobre el botón: al tocar, iOS muestra directamente su
            // menú emergente de AirPlay (comportamiento estándar del sistema).
            ZStack {
                // Botón visual (icono + resaltado si la salida es AirPlay)
                Capsule()
                    .fill(audioEngine.outputPortType == AVAudioSession.Port.airPlay.rawValue ? extractedColor.opacity(0.25) : Color.clear)
                    .frame(width: capsuleWidth, height: capsuleHeight)

                Image(systemName: "airplayaudio")
                    .font(.system(size: iconSize, weight: audioEngine.outputPortType == AVAudioSession.Port.airPlay.rawValue ? .bold : .semibold))
                    .foregroundStyle(audioEngine.outputPortType == AVAudioSession.Port.airPlay.rawValue ? playIconColor : AppTheme.contrastingText(on: extractedUIColor).opacity(0.7))

                // ✅ Picker nativo invisible encima: captura el toque y muestra
                // el menú de AirPlay del sistema. opacity 0.011 (no 0) para que
                // UIKit siga entregando los toques al AVRoutePickerView.
                AirPlayRoutePickerView()
                    .frame(width: buttonSize, height: buttonSize)
                    .opacity(0.011)
                    .contentShape(Rectangle())
            }
            .frame(width: buttonSize, height: buttonSize)
            .contentShape(Rectangle())
            .accessibilityLabel("AirPlay")
        }
        .frame(maxWidth: .infinity)
        .fixedSize()
    }

    // MARK: - Modal centrado con X (ventana emergente sobre el NowPlaying)
    private var qualityCardModal: some View {
        ZStack {
            // ✅ Backdrop con blur (más premium que solo opacidad)
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .background(.ultraThinMaterial)
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showQualityDetail = false
                    }
                }
                .transition(.opacity)

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "waveform.badge.magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.accentColor)

                    Text("Calidad de audio")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Spacer()

                    Button {
                        Haptics.light()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            showQualityDetail = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background {
                                Circle().fill(Color.secondary.opacity(0.15))
                            }
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cerrar")
                }
                .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 8)

                AudioQualityDetailView(audioEngine: audioEngine, embeddedInCard: true)
            }
            .frame(maxWidth: 480, maxHeight: 640)
            .background {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(Color(UIColor.systemBackground))
                    // ✅ Sombra doble para mayor profundidad
                    .shadow(color: .black.opacity(0.35), radius: 30, x: 0, y: 15)
                    .shadow(color: Color.accentColor.opacity(0.08), radius: 20, x: 0, y: 5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .padding(.horizontal, 24)
            // ✅ ANIMACIÓN DE ENTRADA/SALIDA: scale + opacity + blur
            .scaleEffect(showQualityDetail ? 1.0 : 0.88)
            .opacity(showQualityDetail ? 1.0 : 0)
            .blur(radius: showQualityDetail ? 0 : 8)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showQualityDetail)
    }

    // MARK: - Helpers
    private var controlBackground: AnyShapeStyle {
        reduceTransparency
            ? AnyShapeStyle(Color(UIColor.secondarySystemBackground))
            : AnyShapeStyle(.ultraThinMaterial)
    }

    private var repeatIcon: String {
        switch audioEngine.repeatMode {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard !time.isNaN && time.isFinite else { return "0:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func extractColorFromArtwork() {
        // ✅ FIX: respetar el ajuste "Color dinámico"
        guard dynamicColor else {
            extractedColor = AppTheme.accent
            return
        }

        guard let artwork = audioEngine.currentSong?.artwork else {
            extractedColor = AppTheme.accent
            return
        }

        // ✅ Color dominante VIVO vía histograma HSB, con caché por canción
        let cacheKey = (audioEngine.currentSong?.id.uuidString ?? "none") as NSString
        if let cached = NowPlayingView.colorCache.object(forKey: cacheKey) {
            extractedColor = AppTheme.readableColor(from: cached)
            extractedUIColor = cached
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let dominant = AppTheme.dominantColor(from: artwork) ?? AppTheme.accentUIColor
            NowPlayingView.colorCache.setObject(dominant, forKey: cacheKey)
            DispatchQueue.main.async {
                self.extractedColor = AppTheme.readableColor(from: dominant)
                self.extractedUIColor = dominant
            }
        }
    }
}

// MARK: - AirPlay Route Picker View (UIKit wrapper)
// ✅ FIX: el picker nativo embebido directamente (no dentro de un contenedor
// extra). Al tocarlo, iOS muestra su menú emergente de AirPlay del sistema.
struct AirPlayRoutePickerView: UIViewRepresentable {
    typealias UIViewType = AVRoutePickerView

    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = false
        picker.tintColor = UIColor(Color.accentColor)
        // ✅ Sin icono visible: lo superponemos invisible sobre nuestro botón
        // SwiftUI; solo interesa su comportamiento táctil.
        picker.routePickerButtonBordered = false
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
