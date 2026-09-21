import SwiftUI

/// ✅ RAÍZ DE LA APP (3.0): tab bar inferior con tres pestañas
/// (Bienvenida · Biblioteca · Ajustes).
///
/// RootTabView es el ÚNICO dueño de `audioEngine` y `fileAccessService`: antes
/// vivían dentro de ContentView, pero ahora los comparten las tres pestañas, el
/// splash y la PlayerBar flotante (una sola sesión de audio y una sola
/// biblioteca indexada).
struct RootTabView: View {
    @StateObject private var audioEngine = AudioEngine()
    @StateObject private var fileAccessService = FileAccessService()
    /// ✅ Observar el idioma: las etiquetas del tab bar cambian al instante.
    @ObservedObject private var localization = Localization.shared
    // ✅ 3.0 MODO PRESENTACIÓN: mientras se graba la pantalla se oculta la barra
    // de estado y se muestra una píldora "Grabando". No afecta al audio.
    @ObservedObject private var captureMode = CaptureModeManager.shared

    /// ✅ La app abre en Biblioteca (donde abría siempre); Bienvenida queda a la
    /// izquierda y Ajustes a la derecha.
    @State private var selectedTab: AppTab = .library
    /// ✅ El splash se dibuja por ENCIMA de todo (tab bar y PlayerBar incluidos)
    /// hasta que la biblioteca termina de cargar.
    @State private var isInitialLoad = true
    /// ✅ 3.0: confirmación breve tras una captura de pantalla del sistema.
    @State private var showScreenshotToast = false
    /// ✅ Evita que dos capturas seguidas se oculten la una a la otra: solo el
    /// temporizador de la última captura puede retirar el toast.
    @State private var screenshotToastToken = 0

    enum AppTab: Hashable {
        case welcome
        case library
        case settings
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            welcomeTab
            libraryTab
            settingsTab
        }
        .tint(AppTheme.accent)
        // ✅ Barra de estado oculta SOLO durante la grabación de pantalla (hora,
        // batería y red fuera del vídeo). Al terminar, se restaura sola.
        .statusBarHidden(captureMode.isScreenCaptured)
        // ✅ Tab bar con material: mismo lenguaje visual que el resto de la app.
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        // ✅ FIX 3.0.1: el inset de la PlayerBar ya NO se aplica aquí. Sobre un
        // TabView, `safeAreaInset` solo conocía el indicador de inicio y colocaba
        // la barra ENCIMA del tab bar nativo (tapaba los tres iconos). Ahora el
        // inset vive dentro de cada pestaña (ver `playerBarInset`), cuyo safe area
        // SÍ incluye el alto del tab bar → la barra queda justo por encima, con
        // separación, y los iconos siempre visibles y tocables.
        .overlay {
            if isInitialLoad {
                splashOverlay
            }
        }
        // ✅ Modo presentación: píldora "Grabando" (arriba a la derecha) y toast
        // de captura (arriba al centro), ambos sin recibir toques.
        .overlay(alignment: .top) { topOverlays }
        .animation(.easeInOut(duration: 0.3), value: captureMode.isScreenCaptured)
        .onAppear(perform: handleAppear)
        // ✅ 3.0: el sistema avisa cuando el usuario captura la pantalla.
        .onReceive(CaptureModeManager.shared.screenshotPublisher) { _ in
            showScreenshotToastBriefly()
        }
        // ✅ La grabación puede empezar con la app en segundo plano: al volver a
        // primer plano se resincroniza el estado (y el log correspondiente).
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            captureMode.refreshCaptureState()
        }

        .onChange(of: fileAccessService.isInitialLibraryLoaded) { loaded in
            if loaded { finishInitialLoad() }
        }
        // ✅ 3.0 ESTADÍSTICAS: el reloj de reproducción (0,4 s en primer plano)
        // alimenta el tiempo escuchado REAL. Se observa como publisher —no como
        // estado— para que RootTabView no se re-renderice en cada tick, y el
        // trabajo pesado (volcado a disco) solo ocurre cada ~15 s.
        .onReceive(audioEngine.clock.$time) { _ in
            fileAccessService.accumulateListeningTick(
                songID: audioEngine.currentSong?.id,
                isPlaying: audioEngine.isPlaying
            )
        }
        .onReceive(audioEngine.$isPlaying) { playing in
            // ✅ Al pausar, el reloj deja de emitir ticks: se vuelca lo acumulado
            // para no perder el último tramo escuchado.
            if !playing {
                fileAccessService.accumulateListeningTick(songID: nil, isPlaying: false)
            }
        }
        .task { await splashFallback() }
    }

    // MARK: - Pestañas

    private var welcomeTab: some View {
        playerBarInset {
            WelcomeView(audioEngine: audioEngine, fileAccessService: fileAccessService)
        }
        .tabItem { Label(Localization.localized("tab.welcome"), systemImage: "sparkles") }
        .tag(AppTab.welcome)
    }

    private var libraryTab: some View {
        playerBarInset {
            ContentView(audioEngine: audioEngine, fileAccessService: fileAccessService)
        }
        .tabItem { Label(Localization.localized("tab.library"), systemImage: "music.note.list") }
        .tag(AppTab.library)
    }

    private var settingsTab: some View {
        playerBarInset {
            SettingsView(audioEngine: audioEngine, fileAccessService: fileAccessService)
        }
        .tabItem { Label(Localization.localized("tab.settings"), systemImage: "gearshape.fill") }
        .tag(AppTab.settings)
    }

    // MARK: - PlayerBar flotante

    /// ✅ Aplica el inset de la PlayerBar DENTRO de una pestaña: el contenido de un
    /// tab incluye el alto del tab bar en su safe area, así que la barra se coloca
    /// justo por encima de los iconos (no encima) y, de paso, las listas reservan
    /// espacio para no ocultar la última fila.
    private func playerBarInset<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                playerBar
            }
    }

    private var playerBar: some View {
        PlayerBar(
            audioEngine: audioEngine,
            fileAccessService: fileAccessService,
            clock: audioEngine.clock
        )
        .padding(.horizontal, 10)
        // ✅ 8pt de aire entre la barra y los iconos del tab bar.
        .padding(.bottom, 8)
    }

    // MARK: - Splash

    // MARK: - Modo presentación

    /// ✅ Capa superior: el toast de captura va centrado y la píldora de grabación
    /// a la derecha. Si coinciden, se apilan sin solaparse.
    @ViewBuilder
    private var topOverlays: some View {
        VStack(spacing: 8) {
            if showScreenshotToast {
                screenshotToast
                    .transition(.opacity)
            }
            if captureMode.isScreenCaptured {
                recordingPill
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .transition(.opacity)
            }
        }
        .padding(.top, 10)
        .padding(.horizontal, 14)
    }

    /// ✅ Toast "Captura guardada": card pequeña, material, sin bloquear toques.
    private var screenshotToast: some View {
        HStack(spacing: 7) {
            Image(systemName: "camera.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.accent)

            Text(Localization.localized("capture.screenshotSaved"))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background {
            Capsule().fill(AnyShapeStyle(.ultraThinMaterial))
        }
        .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
        .allowsHitTesting(false)
    }

    /// ✅ Muestra el toast 2 s. Cada captura reinicia el contador, así dos
    /// capturas seguidas no se pisan (la primera no retira el toast de la segunda).
    @MainActor
    private func showScreenshotToastBriefly() {
        screenshotToastToken += 1
        let token = screenshotToastToken

        withAnimation(.easeInOut(duration: 0.3)) { showScreenshotToast = true }

        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard token == screenshotToastToken else { return }
            withAnimation(.easeInOut(duration: 0.3)) { showScreenshotToast = false }
        }
    }

    /// ✅ Píldora "● Grabando": solo visible mientras se graba la pantalla, con
    /// material ultraThinMaterial y sin recibir toques.
    private var recordingPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(AppTheme.accent)
                .frame(width: 7, height: 7)

            Text(Localization.localized("capture.recording"))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background {
            Capsule().fill(AnyShapeStyle(.ultraThinMaterial))
        }
        .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
        .allowsHitTesting(false)
    }

    private var splashOverlay: some View {
        SplashView()
            // ✅ Salida premium: la escala mínima acompaña al fundido (duración la
            // marca el withAnimation del llamador, como antes).
            .transition(.scale(scale: 0.96).combined(with: .opacity))
    }

    private func handleAppear() {
        connectPlaybackTracking()
        guard fileAccessService.isInitialLibraryLoaded else { return }
        finishInitialLoad()
    }

    // MARK: - Tracking de reproducciones (3.0)

    /// ✅ El motor solo AVISA de que una canción empezó; las estadísticas viven
    /// en FileAccessService (dueño de playCounts/playTimes/lastPlayedDates), así
    /// que la conexión se hace aquí, donde ambos existen.
    private func connectPlaybackTracking() {
        audioEngine.onSongStarted = { [fileAccessService] song in
            fileAccessService.recordPlayStarted(songID: song.id)
        }
        // ✅ 3.0: el peso del shuffle inteligente lo calcula FileAccessService
        // (dueño de playCounts/lastPlayedDates/liked); el motor solo ordena.
        audioEngine.shuffleWeightProvider = { [fileAccessService] song in
            fileAccessService.smartShuffleWeight(for: song)
        }
    }

    private func finishInitialLoad() {
        withAnimation(.easeOut(duration: 0.3)) { isInitialLoad = false }
    }

    /// ✅ Respaldo: si la carga inicial no termina en 8 s, el splash también se
    /// retira (mismo tope que tenía ContentView).
    private func splashFallback() async {
        try? await Task.sleep(nanoseconds: 8_000_000_000)
        guard isInitialLoad else { return }
        finishInitialLoad()
    }
}
