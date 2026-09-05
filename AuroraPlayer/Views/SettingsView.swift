import SwiftUI

struct SettingsView: View {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var fileAccessService: FileAccessService
    @Environment(\.dismiss) private var dismiss

    @State private var showFolderPicker = false
    @State private var showLogs = false
    @State private var showAbout = false
    @State private var showEqualizerSheet = false
    @State private var selectedThemeIndex: Int
    @ObservedObject private var theme = ThemeManager.shared

    // Configuraciones persistentes
    @AppStorage("com.aurora.showVisualizer") private var showVisualizer = true
    @AppStorage("com.aurora.enableHaptics") private var enableHaptics = true
    @AppStorage("com.aurora.keepScreenOn") private var keepScreenOn = false
    @AppStorage("com.aurora.artworkCorner") private var artworkCorner: Double = 22
    @AppStorage("com.aurora.dynamicColor") private var dynamicColor = true
    @AppStorage("com.aurora.reduceTransparency") private var reduceTransparency = false

    private let themes = ["Sistema (claro/oscuro)", "Modo Claro", "Modo Oscuro"]
    private let accents = ["Morado (predeterminado)", "Azul Aurora", "Esmeralda", "Rosa Neón", "Ámbar Solar"]

    private let themeDefaultsKey = "com.aurora.uiTheme"

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.3.2"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "7"
        return "\(version) (\(build))"
    }

    init(audioEngine: AudioEngine, fileAccessService: FileAccessService) {
        self.audioEngine = audioEngine
        self.fileAccessService = fileAccessService

        let savedTheme = UserDefaults.standard.integer(forKey: themeDefaultsKey)
        _selectedThemeIndex = State(initialValue: savedTheme >= 0 && savedTheme < 3 ? savedTheme : 0)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                applyThemeBackground()

                ScrollView {
                    VStack(spacing: 22) {
                        headerSection

                        // Biblioteca
                        settingsSection(icon: "folder.fill", title: "Biblioteca", color: .blue) {
                            settingsButton(title: "Carpetas de música", subtitle: "\(fileAccessService.folders.count) carpetas", icon: "folder.fill", color: .blue) {
                                showFolderPicker = true
                            }
                            settingsDivider
                            settingsButton(title: "Actualizar biblioteca", subtitle: fileAccessService.isScanning ? "Escaneando..." : "Rescanear carpetas", icon: "arrow.clockwise", color: .orange) {
                                fileAccessService.refreshAllFolders()
                            }
                            .disabled(fileAccessService.isScanning)
                        }

                        // Audio
                        settingsSection(icon: "waveform", title: "Audio", color: .purple) {
                            settingsButton(title: "Equalizador", subtitle: audioEngine.isEQEnabled ? "Activado (\(audioEngine.eqPreset.displayName))" : "Desactivado", icon: "slider.horizontal.3", color: .purple) {
                                showEqualizerSheet = true
                            }
                            settingsDivider
                            settingsButton(title: "Crossfade", subtitle: audioEngine.isCrossfadeEnabled ? "Transición de \(Int(audioEngine.currentCrossfadeDuration))s" : "Desactivado", icon: "forward.end.fill", color: .teal) {
                                audioEngine.toggleCrossfade()
                            }
                            // ✅ Slider de crossfade: la API ya existía pero no
                            // estaba expuesta en la UI (rango 1–12s, persistido).
                            if audioEngine.isCrossfadeEnabled {
                                settingsSliderRow(
                                    title: "Duración del crossfade",
                                    value: Binding(
                                        get: { audioEngine.currentCrossfadeDuration },
                                        set: { audioEngine.setCrossfadeDuration($0) }
                                    ),
                                    range: 1...12, step: 1, color: .teal, suffix: "s"
                                )
                            }
                        }

                        // Apariencia
                        settingsSection(icon: "paintbrush.fill", title: "Apariencia", color: .pink) {
                            settingsMenuButton(title: "Tema", subtitle: themes[selectedThemeIndex], icon: "circle.lefthalf.filled", color: .gray, options: themes, selection: $selectedThemeIndex) { index in
                                selectedThemeIndex = index
                                UserDefaults.standard.set(index, forKey: themeDefaultsKey)
                            }
                            settingsDivider
                            settingsMenuButton(title: "Color de acento", subtitle: accents[theme.accentIndex], icon: "drop.fill", color: theme.accent, options: accents, selection: $theme.accentIndex) { index in
                                theme.setAccent(index)
                            }
                            settingsDivider
                            settingsToggleRow(title: "Color dinámico", subtitle: "Extrae el color dominante de la portada", icon: "wand.and.stars", color: .cyan, isOn: $dynamicColor)
                            settingsDivider
                            settingsSliderRow(title: "Esquinas del artwork", value: $artworkCorner, range: 0...44, step: 2, color: .blue, suffix: "pt")
                            settingsDivider
                            settingsToggleRow(title: "Reducir transparencia", subtitle: "Menos desenfoques, más rendimiento", icon: "circle.slash", color: .gray, isOn: $reduceTransparency)
                        }

                        // Reproducción
                        settingsSection(icon: "dial.max.fill", title: "Reproducción", color: .orange) {
                            settingsToggleRow(title: "Visualizador de audio", subtitle: "Animación de barras en Reproduciendo", icon: "waveform.path.ecg", color: .pink, isOn: $showVisualizer)
                            settingsDivider
                            settingsToggleRow(title: "Respuesta táctil", subtitle: "Vibración al tocar los controles", icon: "iphone.radiowaves.left.and.right", color: .mint, isOn: $enableHaptics)
                            settingsDivider
                            settingsToggleRow(title: "Mantener pantalla encendida", subtitle: "Evita que se bloquee mientras se reproduce", icon: "sun.max.fill", color: .yellow, isOn: $keepScreenOn)
                        }
                        // ✅ Sincronización en vivo con el engine (antes solo
                        // se aplicaba al reiniciar ContentView)
                        .onChange(of: keepScreenOn) { newValue in
                            audioEngine.isKeepScreenOnEnabled = newValue
                        }

                        // Rendimiento (info técnica)
                        settingsSection(icon: "gauge.open.with.needle", title: "Rendimiento", color: .indigo) {
                            settingsInfoRow(title: "Salida de audio", value: audioEngine.audioQualityInfo.isEmpty ? "\(Int(audioEngine.outputSampleRate / 1000)) kHz · \(audioEngine.outputChannelCount) canales" : audioEngine.audioQualityInfo, icon: "speaker.wave.2.fill", color: .indigo)
                            settingsDivider
                            settingsInfoRow(title: "Ruta de reproducción", value: audioEngine.currentRouteName, icon: "airplayaudio", color: .blue)
                            settingsDivider
                            // ✅ Modelo comercial real (ej. "iPhone 13 Pro") en vez de "iPhone"
                            settingsInfoRow(title: "Dispositivo", value: audioEngine.deviceModelName, icon: "iphone", color: .gray)
                        }

                        // Estadísticas
                        settingsSection(icon: "chart.bar.fill", title: "Estadísticas", color: .green) {
                            statRow(title: "Canciones", value: "\(fileAccessService.songs.count)")
                            settingsDivider
                            statRow(title: "Álbumes", value: "\(fileAccessService.albums.count)")
                            settingsDivider
                            statRow(title: "Artistas", value: "\(fileAccessService.artists.count)")
                        }

                        // Avanzado
                        settingsSection(icon: "wrench.and.screwdriver.fill", title: "Avanzado", color: .orange) {
                            settingsButton(title: "Registros", subtitle: "Ver logs de la app", icon: "doc.text.magnifyingglass", color: .gray) {
                                showLogs = true
                            }
                            settingsDivider
                            settingsButton(title: "Acerca de", subtitle: "Aurora Player v\(appVersion)", icon: "info.circle.fill", color: .blue) {
                                showAbout = true
                            }
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 30)
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

    // MARK: - Theme Background
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
                    colors: [Color(UIColor.systemBackground), Color(UIColor.secondarySystemBackground)],
                    startPoint: .top, endPoint: .bottom
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

    // MARK: - Header
    private var headerSection: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.3), Color.accentColor.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)

                Image(systemName: "gearshape.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 4) {
                Text("Ajustes")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Configura Aurora Player a tu gusto")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .nativeGlass(cornerRadius: 24)
    }

    // MARK: - Section Builder
    @ViewBuilder
    private func settingsSection<Content: View>(
        icon: String, title: String, color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 26, height: 26)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(color.opacity(0.12))
                    }

                Text(title)
                    .font(.system(size: 17, weight: .semibold))
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

    // MARK: - Button Row
    @ViewBuilder
    private func settingsButton(
        title: String, subtitle: String, icon: String, color: Color,
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
            .padding(.horizontal, 16).padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Toggle Row
    @ViewBuilder
    private func settingsToggleRow(
        title: String, subtitle: String, icon: String, color: Color,
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
        .padding(.horizontal, 16).padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            isOn.wrappedValue.toggle()
        }
    }

    // MARK: - Slider Row
    @ViewBuilder
    private func settingsSliderRow(
        title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double,
        color: Color, suffix: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(Int(value.wrappedValue)) \(suffix)")
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .foregroundStyle(color)
            }

            Slider(value: value, in: range, step: step)
                .tint(color)
                .accessibilityLabel(title)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    // MARK: - Info Row
    @ViewBuilder
    private func settingsInfoRow(
        title: String, value: String, icon: String, color: Color
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
        .padding(.horizontal, 16).padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    // MARK: - Icon
    private func iconView(icon: String, color: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(color)
            .frame(width: 30, height: 30)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.opacity(0.1))
            }
    }

    // MARK: - Menu Picker Button Row
    @ViewBuilder
    private func settingsMenuButton(
        title: String, subtitle: String, icon: String, color: Color,
        options: [String], selection: Binding<Int>,
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
            .padding(.horizontal, 16).padding(.vertical, 14)
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
        .padding(.horizontal, 16).padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    // MARK: - Divider
    private var settingsDivider: some View {
        Divider()
            .opacity(0.1)
            .padding(.leading, 60)
    }
}

#Preview {
    SettingsView(audioEngine: AudioEngine(), fileAccessService: FileAccessService())
}