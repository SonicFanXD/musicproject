import SwiftUI
import UIKit

struct SettingsView: View {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var fileAccessService: FileAccessService
    @Environment(\.dismiss) private var dismiss

    @State private var showFolderPicker = false
    @State private var showLogs = false
    @State private var showAbout = false
    @State private var showEqualizerSheet = false
    @State private var selectedThemeIndex: Int
    @State private var selectedAccentIndex: Int

    // Nuevas configuraciones técnicas/visuales
    @AppStorage("com.aurora.showVisualizer") private var showVisualizer = true
    @AppStorage("com.aurora.enableHaptics") private var enableHaptics = true
    @AppStorage("com.aurora.keepScreenOn") private var keepScreenOn = false
    @AppStorage("com.aurora.crossfadeSeconds") private var crossfadeSeconds: Double = 3.0
    @AppStorage("com.aurora.artworkCorner") private var artworkCorner: Double = 22
    @AppStorage("com.aurora.dynamicColor") private var dynamicColor = true

    private let themes = ["Sistema (claro/oscuro)", "Modo Claro", "Modo Oscuro"]
    private let accents = ["Morado (predeterminado)", "Azul Aurora", "Esmeralda", "Rosa Neón", "Ámbar Solar"]

    // Keys de persistencia
    private let themeDefaultsKey = "com.aurora.uiTheme"
    private let accentDefaultsKey = "com.aurora.accentColor"

    // Versión dinámica desde Info.plist
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "2"
        return "\(version) (\(build))"
    }

    init(audioEngine: AudioEngine, fileAccessService: FileAccessService) {
        self.audioEngine = audioEngine
        self.fileAccessService = fileAccessService

        let savedTheme = UserDefaults.standard.integer(forKey: themeDefaultsKey)
        _selectedThemeIndex = State(initialValue: savedTheme >= 0 && savedTheme < 3 ? savedTheme : 0)

        let savedAccent = UserDefaults.standard.integer(forKey: accentDefaultsKey)
        _selectedAccentIndex = State(initialValue: savedAccent >= 0 && savedAccent < 5 ? savedAccent : 0)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                applyThemeBackground()

                ScrollView {
                    VStack(spacing: 24) {
                        headerSection

                        // Library Section
                        settingsSection(
                            icon: "folder.fill",
                            title: "Biblioteca",
                            color: .blue
                        ) {
                            settingsButton(
                                title: "Carpetas de música",
                                subtitle: "\(fileAccessService.folders.count) carpetas",
                                icon: "folder.fill",
                                color: .blue
                            ) {
                                showFolderPicker = true
                            }

                            settingsDivider

                            settingsButton(
                                title: "Actualizar biblioteca",
                                subtitle: fileAccessService.isScanning ? "Escaneando..." : "Rescanear carpetas",
                                icon: "arrow.clockwise",
                                color: .orange
                            ) {
                                fileAccessService.refreshAllFolders()
                            }
                            .disabled(fileAccessService.isScanning)
                        }

                        // Audio Section
                        settingsSection(
                            icon: "waveform",
                            title: "Audio",
                            color: .purple
                        ) {
                            settingsButton(
                                title: "Equalizador",
                                subtitle: audioEngine.isEQEnabled ? "Activado (\(audioEngine.eqPreset.displayName))" : "Desactivado",
                                icon: "slider.horizontal.3",
                                color: .purple
                            ) {
                                audioEngine.toggleEQ()
                            }

                            settingsDivider

                            // Crossfade con switch + slider de duración
                            settingsToggleRow(
                                title: "Crossfade",
                                subtitle: audioEngine.isCrossfadeEnabled ? "Transición de \(Int(audioEngine.currentCrossfadeDuration))s" : "Desactivado",
                                icon: "forward.end.fill",
                                color: .teal,
                                isOn: Binding(
                                    get: { audioEngine.isCrossfadeEnabled },
                                    set: { _ in audioEngine.toggleCrossfade() }
                                )
                            )

                            if audioEngine.isCrossfadeEnabled {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Duración del crossfade")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(Int(audioEngine.currentCrossfadeDuration)) s")
                                            .font(.system(size: 13, weight: .bold).monospacedDigit())
                                            .foregroundStyle(.teal)
                                    }

                                    // El slider refleja el valor actual del motor de audio
                                    Slider(
                                        value: Binding(
                                            get: { audioEngine.currentCrossfadeDuration },
                                            set: { audioEngine.setCrossfadeDuration($0) }
                                        ),
                                        in: 1...12,
                                        step: 1
                                    )
                                    .tint(.teal)
                                }
                                .padding(.horizontal, 16)
                                .padding(.bottom, 14)
                            }

                            settingsDivider

                            // Botón para abrir el ecualizador completo
                            settingsButton(
                                title: "Ajustar Equalizador",
                                subtitle: "Presets y 10 bandas de frecuencia",
                                icon: "slider.vertical.3",
                                color: .indigo
                            ) {
                                showEqualizerSheet = true
                            }
                        }

                        // Visual Section — Tema y color de acento
                        settingsSection(
                            icon: "paintbrush.fill",
                            title: "Apariencia",
                            color: .pink
                        ) {
                            settingsMenuButton(
                                title: "Tema",
                                subtitle: themes[selectedThemeIndex],
                                icon: "circle.lefthalf.filled",
                                color: .gray,
                                options: themes,
                                selection: $selectedThemeIndex
                            ) { index in
                                selectedThemeIndex = index
                                UserDefaults.standard.set(index, forKey: themeDefaultsKey)
                            }

                            settingsDivider

                            settingsMenuButton(
                                title: "Color de acento",
                                subtitle: accents[selectedAccentIndex],
                                icon: "drop.fill",
                                color: accentColorForIndex(selectedAccentIndex),
                                options: accents,
                                selection: $selectedAccentIndex
                            ) { index in
                                selectedAccentIndex = index
                                UserDefaults.standard.set(index, forKey: accentDefaultsKey)
                            }

                            settingsDivider

                            // Color dinámico del artwork
                            settingsToggleRow(
                                title: "Color dinámico",
                                subtitle: "Extrae el color dominante de la portada",
                                icon: "wand.and.stars",
                                color: .cyan,
                                isOn: $dynamicColor
                            )
                        }

                        // NEW: Reproducción / Comportamiento
                        settingsSection(
                            icon: "dial.max.fill",
                            title: "Reproducción",
                            color: .orange
                        ) {
                            // Visualizador
                            settingsToggleRow(
                                title: "Visualizador de audio",
                                subtitle: "Animación de barras en Reproduciendo",
                                icon: "waveform.path.ecg",
                                color: .pink,
                                isOn: $showVisualizer
                            )

                            settingsDivider

                            // Haptics
                            settingsToggleRow(
                                title: "Respuesta táctil",
                                subtitle: "Vibración al tocar los controles",
                                icon: "iphone.radiowaves.left.and.right",
                                color: .mint,
                                isOn: $enableHaptics
                            )

                            settingsDivider

                            // Mantener pantalla encendida en Now Playing
                            settingsToggleRow(
                                title: "Mantener pantalla encendida",
                                subtitle: "Evita que se bloquee mientras se reproduce",
                                icon: "sun.max.fill",
                                color: .yellow,
                                isOn: $keepScreenOn
                            )
                        }

                        // NEW: Tecnica / Rendimiento
                        settingsSection(
                            icon: "gauge.open.with.needle",
                            title: "Rendimiento",
                            color: .indigo
                        ) {
                            // Info técnica
                            settingsInfoRow(
                                title: "Salida de audio",
                                value: audioEngine.audioQualityInfo.isEmpty
                                    ? "\(Int(audioEngine.outputSampleRate / 1000)) kHz · \(audioEngine.outputChannelCount) canales"
                                    : audioEngine.audioQualityInfo,
                                icon: "speaker.wave.2.fill",
                                color: .indigo
                            )

                            settingsDivider

                            settingsInfoRow(
                                title: "Ruta de reproducción",
                                value: audioEngine.currentRouteName,
                                icon: "airplayaudio",
                                color: .blue
                            )

                            settingsDivider

                            settingsInfoRow(
                                title: "Dispositivo",
                                value: UIDevice.current.model,
                                icon: "iphone",
                                color: .gray
                            )
                        }

                        // Stats Section
                        settingsSection(
                            icon: "chart.bar.fill",
                            title: "Estadísticas",
                            color: .green
                        ) {
                            statRow(title: "Canciones", value: "\(fileAccessService.songs.count)")
                            settingsDivider
                            statRow(title: "Álbumes", value: "\(fileAccessService.albums.count)")
                            settingsDivider
                            statRow(title: "Artistas", value: "\(fileAccessService.artists.count)")
                        }

                        // Advanced Section
                        settingsSection(
                            icon: "wrench.and.screwdriver.fill",
                            title: "Avanzado",
                            color: .orange
                        ) {
                            settingsButton(
                                title: "Registros",
                                subtitle: "Ver logs de la app",
                                icon: "doc.text.magnifyingglass",
                                color: .gray
                            ) {
                                showLogs = true
                            }

                            settingsDivider

                            settingsButton(
                                title: "Acerca de",
                                subtitle: "Aurora Player v\(appVersion)",
                                icon: "info.circle.fill",
                                color: .blue
                            ) {
                                showAbout = true
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(UIColor.systemBackground).opacity(0.92), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Ajustes")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.75)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .accessibilityLabel("Ajustes")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") { dismiss() }
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
            .sheet(isPresented: $showFolderPicker) {
                FolderPickerView(fileAccessService: fileAccessService)
            }
            .sheet(isPresented: $showLogs) {
                LogsView()
            }
            .sheet(isPresented: $showEqualizerSheet) {
                EqualizerView(audioEngine: audioEngine)
            }
            .alert("Aurora Player v\(appVersion)", isPresented: $showAbout) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Reproductor de música Hi-Fi optimizado para iOS con soporte de alta fidelidad, ecualizador de 10 bandas, crossfade ajustable y gestión avanzada de carpetas locales.")
            }
        }
    }

    // MARK: - Apply Theme & Accent Color (persistente)
    private func applyThemeBackground() -> some View {
        Group {
            if selectedThemeIndex == 1 {
                Color(UIColor.white).ignoresSafeArea()
                    .onAppear {
                        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let window = scene.windows.first {
                            window.overrideUserInterfaceStyle = .light
                        }
                    }
            } else if selectedThemeIndex == 2 {
                Color(UIColor.black).ignoresSafeArea()
                    .onAppear {
                        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let window = scene.windows.first {
                            window.overrideUserInterfaceStyle = .dark
                        }
                    }
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
                .onAppear {
                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = scene.windows.first {
                        window.overrideUserInterfaceStyle = .unspecified
                    }
                }
            }
        }
    }

    private func accentColorForIndex(_ index: Int) -> Color {
        switch index {
        case 0: return Color.purple
        case 1: return Color.blue
        case 2: return Color.green
        case 3: return Color.pink
        case 4: return Color.orange
        default: return Color.purple
        }
    }

    // MARK: - Header
    private var headerSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.3), Color.accentColor.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 90, height: 90)

                Image(systemName: "gearshape.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 4) {
                Text("Ajustes")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Configura Aurora Player a tu gusto")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .nativeGlass(cornerRadius: 24)
    }

    // MARK: - Section Builder
    @ViewBuilder
    private func settingsSection<Content: View>(
        icon: String,
        title: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 28, height: 28)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(color.opacity(0.12))
                    }

                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content()
            }
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
    }

    // MARK: - Standard Button Row
    @ViewBuilder
    private func settingsButton(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                iconView(icon: icon, color: color)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Toggle Row (Switch integrado — funcional)
    @ViewBuilder
    private func settingsToggleRow(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 14) {
            iconView(icon: icon, color: color)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(color)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            isOn.wrappedValue.toggle()
        }
    }

    // MARK: - Info Row (sin interacción — solo lectura)
    @ViewBuilder
    private func settingsInfoRow(
        title: String,
        value: String,
        icon: String,
        color: Color
    ) -> some View {
        HStack(spacing: 14) {
            iconView(icon: icon, color: color)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)

                Text(value)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }

    // MARK: - Icon (reutilizable)
    private func iconView(icon: String, color: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(color)
            .frame(width: 32, height: 32)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.opacity(0.1))
            }
    }

    // MARK: - Menu Picker Button Row
    @ViewBuilder
    private func settingsMenuButton(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        options: [String],
        selection: Binding<Int>,
        onChange: @escaping (Int) -> Void
    ) -> some View {
        Menu {
            ForEach(0..<options.count, id: \.self) { index in
                Button {
                    onChange(index)
                } label: {
                    HStack {
                        Text(options[index])
                        if selection.wrappedValue == index {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 14) {
                iconView(icon: icon, color: color)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Stat Row
    private func statRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }

    // MARK: - Divider
    private var settingsDivider: some View {
        Divider()
            .opacity(0.1)
            .padding(.leading, 64)
    }
}

#Preview {
    SettingsView(audioEngine: AudioEngine(), fileAccessService: FileAccessService())
}