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

    /// ✅ La app abre en Biblioteca (donde abría siempre); Bienvenida queda a la
    /// izquierda y Ajustes a la derecha.
    @State private var selectedTab: AppTab = .library
    /// ✅ El splash se dibuja por ENCIMA de todo (tab bar y PlayerBar incluidos)
    /// hasta que la biblioteca termina de cargar.
    @State private var isInitialLoad = true

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
        // ✅ Tab bar con material: mismo lenguaje visual que el resto de la app.
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        // ✅ La PlayerBar conserva su diseño y flota POR ENCIMA del tab bar: el
        // inset la aparta del borde inferior automáticamente, sin offsets fijos.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            playerBar
        }
        .overlay {
            if isInitialLoad {
                splashOverlay
            }
        }
        .onAppear(perform: handleAppear)
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
        WelcomeView(audioEngine: audioEngine, fileAccessService: fileAccessService)
            .tabItem { Label(Localization.localized("tab.welcome"), systemImage: "sparkles") }
            .tag(AppTab.welcome)
    }

    private var libraryTab: some View {
        ContentView(audioEngine: audioEngine, fileAccessService: fileAccessService)
            .tabItem { Label(Localization.localized("tab.library"), systemImage: "music.note.list") }
            .tag(AppTab.library)
    }

    private var settingsTab: some View {
        SettingsView(audioEngine: audioEngine, fileAccessService: fileAccessService)
            .tabItem { Label(Localization.localized("tab.settings"), systemImage: "gearshape.fill") }
            .tag(AppTab.settings)
    }

    // MARK: - PlayerBar flotante

    private var playerBar: some View {
        PlayerBar(
            audioEngine: audioEngine,
            fileAccessService: fileAccessService,
            clock: audioEngine.clock
        )
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    // MARK: - Splash

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
