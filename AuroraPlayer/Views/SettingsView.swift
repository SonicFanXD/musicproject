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
    // ✅ Observar el idioma: al cambiar, esta vista se re-renderiza al instante
    @ObservedObject private var localization = Localization.shared

    // Configuraciones persistentes
    @AppStorage("com.aurora.showVisualizer") private var showVisualizer = true
    @AppStorage("com.aurora.enableHaptics") private var enableHaptics = true
    @AppStorage("com.aurora.keepScreenOn") private var keepScreenOn = false
    @AppStorage("com.aurora.artworkCorner") private var artworkCorner: Double = 22
    @AppStorage("com.aurora.dynamicColor") private var dynamicColor = true
    @AppStorage("com.aurora.reduceTransparency") private var reduceTransparency = false
    @AppStorage("com.aurora.hapticIntensity") private var hapticIntensity: Double = 1.0
    @AppStorage("com.aurora.showLyricsByDefault") private var showLyricsByDefault = false
    @AppStorage("com.aurora.autoPlayOnStart") private var autoPlayOnStart = false
    @AppStorage("com.aurora.showVisualizerInBar") private var showVisualizerInBar = true
    @AppStorage("com.aurora.compactPlayerBar") private var compactPlayerBar = false
    @AppStorage("com.aurora.language") private var selectedLanguage = 0 // 0 = español, 1 = inglés
    @AppStorage("com.aurora.showFPS") private var showFPS = false

    // ✅ LOCALIZADOS: computados para reaccionar al cambio de idioma al
    // instante (antes eran `let` hardcodeados en español → el inglés no
    // se aplicaba en los pickers de Tema, Color de acento e Idioma).
    private var themes: [String] {
        [
            Localization.localized("settings.theme.system"),
            Localization.localized("settings.theme.light"),
            Localization.localized("settings.theme.dark")
        ]
    }
    private var accents: [String] {
        [
            Localization.localized("settings.accent.purple"),
            Localization.localized("settings.accent.blue"),
            Localization.localized("settings.accent.emerald"),
            Localization.localized("settings.accent.pink"),
            Localization.localized("settings.accent.amber"),
            Localization.localized("settings.accent.black"),
            Localization.localized("settings.accent.darkRed")
        ]
    }
    private var languages: [String] { ["Español", "English"] }

    private let themeDefaultsKey = "com.aurora.uiTheme"

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.8.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "17"
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
                        settingsSection(icon: "folder.fill", title: Localization.localized("settings.library"), color: .blue) {
                            settingsButton(title: Localization.localized("settings.musicFolders"), subtitle: "\(fileAccessService.folders.count) \(Localization.localized("folders"))", icon: "folder.fill", color: .blue) {
                                showFolderPicker = true
                            }
                            settingsDivider
                            settingsButton(title: Localization.localized("settings.updateLibrary"), subtitle: fileAccessService.isScanning ? Localization.localized("settings.scanning") : Localization.localized("settings.rescanFolders"), icon: "arrow.clockwise", color: .orange) {
                                fileAccessService.refreshAllFolders()
                            }
                            .disabled(fileAccessService.isScanning)
                        }

                        // Audio
                        // ✅ Crossfade eliminado por completo (fuente de bugs
                        // de sincronización): ya no aparece en Ajustes.
                        settingsSection(icon: "waveform", title: Localization.localized("settings.audio"), color: AppTheme.accent) {
                            settingsButton(title: Localization.localized("settings.equalizer"), subtitle: audioEngine.isEQEnabled ? "\(Localization.localized("equalizer.active")) (\(audioEngine.eqPreset.displayName))" : Localization.localized("equalizer.disabled"), icon: "slider.horizontal.3", color: AppTheme.accent) {
                                showEqualizerSheet = true
                            }
                            settingsDivider
                            settingsToggleRow(
                                title: Localization.localized("settings.monoAudio"),
                                subtitle: Localization.localized("settings.monoAudioSubtitle"),
                                icon: "ear",
                                color: .cyan,
                                isOn: Binding(
                                    get: { audioEngine.isMonoAudioEnabled },
                                    set: { _ in audioEngine.toggleMonoAudio() }
                                )
                            )
                        }

                        // Apariencia
                        settingsSection(icon: "paintbrush.fill", title: Localization.localized("settings.appearance"), color: .pink) {
                            settingsMenuButton(title: Localization.localized("settings.theme"), subtitle: themes[selectedThemeIndex], icon: "circle.lefthalf.filled", color: .gray, options: themes, selection: $selectedThemeIndex) { index in
                                selectedThemeIndex = index
                                UserDefaults.standard.set(index, forKey: themeDefaultsKey)
                            }
                            settingsDivider
                            settingsMenuButton(title: Localization.localized("settings.accentColor"), subtitle: accents[theme.accentIndex], icon: "drop.fill", color: theme.accent, options: accents, selection: $theme.accentIndex) { index in
                                theme.setAccent(index)
                            }
                            settingsDivider
                            settingsToggleRow(title: Localization.localized("settings.dynamicColor"), subtitle: Localization.localized("settings.dynamicColorSubtitle"), icon: "wand.and.stars", color: .cyan, isOn: $dynamicColor)
                            settingsDivider
                            // ✅ NUEVO: acento dinámico según la carátula de la canción
                            settingsToggleRow(
                                title: Localization.localized("settings.accentFromArtwork"),
                                subtitle: Localization.localized("settings.accentFromArtworkSubtitle"),
                                icon: "photo.artframe",
                                color: .indigo,
                                isOn: Binding(
                                    get: { theme.accentFromArtwork },
                                    set: { newValue in
                                        theme.accentFromArtwork = newValue
                                        // Al activar, extraer de inmediato el color de la canción actual
                                        if newValue { theme.updateArtworkAccent(from: audioEngine.currentSong) }
                                    }
                                )
                            )
                            settingsDivider
                            settingsSliderRow(title: Localization.localized("settings.artworkCorners"), value: $artworkCorner, range: 0...44, step: 2, color: .blue, suffix: "pt")
                            settingsDivider
                            settingsToggleRow(title: Localization.localized("settings.reduceTransparency"), subtitle: Localization.localized("settings.reduceTransparencySubtitle"), icon: "circle.slash", color: .gray, isOn: $reduceTransparency)
                            settingsDivider
                            settingsMenuButton(title: Localization.localized("settings.language"), subtitle: languages[selectedLanguage], icon: "globe", color: .blue, options: languages, selection: $selectedLanguage) { index in
                                selectedLanguage = index
                                // ✅ Aplicar el idioma al instante en toda la app
                                Localization.shared.currentLanguage = Localization.Language(rawValue: index) ?? .spanish
                            }
                        }

                        // Reproducción
                        settingsSection(icon: "dial.max.fill", title: Localization.localized("settings.playback"), color: .orange) {
                            settingsToggleRow(title: Localization.localized("settings.visualizer"), subtitle: Localization.localized("settings.visualizerSubtitle"), icon: "waveform.path.ecg", color: .pink, isOn: $showVisualizer)
                            settingsDivider
                            settingsToggleRow(title: Localization.localized("settings.haptics"), subtitle: Localization.localized("settings.hapticsSubtitle"), icon: "iphone.radiowaves.left.and.right", color: .mint, isOn: $enableHaptics)
                            settingsDivider
                            settingsToggleRow(title: Localization.localized("settings.keepScreenOn"), subtitle: Localization.localized("settings.keepScreenOnSubtitle"), icon: "sun.max.fill", color: .yellow, isOn: $keepScreenOn)
                            settingsDivider
                            settingsToggleRow(title: Localization.localized("settings.autoPlayOnStart"), subtitle: Localization.localized("settings.autoPlayOnStartSubtitle"), icon: "play.circle", color: .green, isOn: $autoPlayOnStart)
                        }
                        
                        // ✅ Personalización avanzada
                        settingsSection(icon: "wand.and.rays", title: Localization.localized("settings.customization"), color: .indigo) {
                            settingsSliderRow(title: Localization.localized("settings.hapticIntensity"), value: $hapticIntensity, range: 0.0...1.0, step: 0.1, color: .mint, suffix: "")
                            settingsDivider
                            settingsToggleRow(title: Localization.localized("settings.showVisualizerInBar"), subtitle: Localization.localized("settings.showVisualizerInBarSubtitle"), icon: "waveform", color: .accentColor, isOn: $showVisualizerInBar)
                            settingsDivider
                            settingsToggleRow(title: Localization.localized("settings.compactPlayerBar"), subtitle: Localization.localized("settings.compactPlayerBarSubtitle"), icon: "rectangle.compress.vertical", color: .gray, isOn: $compactPlayerBar)
                            settingsDivider
                            settingsToggleRow(title: Localization.localized("settings.showLyricsByDefault"), subtitle: Localization.localized("settings.showLyricsByDefaultSubtitle"), icon: "quote.bubble", color: .blue, isOn: $showLyricsByDefault)
                        }
                        // ✅ Sincronización en vivo con el engine (antes solo
                        // se aplicaba al reiniciar ContentView)
                        .onChange(of: keepScreenOn) { newValue in
                            audioEngine.isKeepScreenOnEnabled = newValue
                        }

                        // Rendimiento (info técnica)
                        settingsSection(icon: "gauge.open.with.needle", title: Localization.localized("settings.performance"), color: .indigo) {
                            settingsToggleRow(title: Localization.localized("settings.showFPS"), subtitle: Localization.localized("settings.showFPSSubtitle"), icon: "speedometer", color: .green, isOn: $showFPS)
                            settingsDivider
                            settingsInfoRow(title: Localization.localized("settings.audioOutput"), value: audioEngine.audioQualityInfo.isEmpty ? "\(Int(audioEngine.outputSampleRate / 1000)) kHz · \(audioEngine.outputChannelCount)" : audioEngine.audioQualityInfo, icon: "speaker.wave.2.fill", color: .indigo)
                            settingsDivider
                            settingsInfoRow(title: Localization.localized("settings.playbackRoute"), value: audioEngine.currentRouteName, icon: "airplayaudio", color: .blue)
                            settingsDivider
                            // ✅ Modelo comercial real (ej. "iPhone 13 Pro") en vez de "iPhone"
                            settingsInfoRow(title: Localization.localized("settings.device"), value: audioEngine.deviceModelName, icon: "iphone", color: .gray)
                        }

                        // Estadísticas
                        settingsSection(icon: "chart.bar.fill", title: Localization.localized("settings.stats"), color: .green) {
                            statRow(title: Localization.localized("library.songs"), value: "\(fileAccessService.songs.count)")
                            settingsDivider
                            statRow(title: Localization.localized("library.albums"), value: "\(fileAccessService.albums.count)")
                            settingsDivider
                            statRow(title: Localization.localized("library.artists"), value: "\(fileAccessService.artists.count)")
                        }

                        // Avanzado
                        settingsSection(icon: "wrench.and.screwdriver.fill", title: Localization.localized("settings.advanced"), color: .orange) {
                            settingsButton(title: Localization.localized("settings.logs"), subtitle: Localization.localized("settings.logsSubtitle"), icon: "doc.text.magnifyingglass", color: .gray) {
                                showLogs = true
                            }
                            settingsDivider
                            settingsButton(title: Localization.localized("settings.about"), subtitle: "Aurora Player v\(appVersion)", icon: "info.circle.fill", color: .blue) {
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
                    Text(Localization.localized("settings.title"))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [AppTheme.accent, AppTheme.accent.opacity(0.75)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .accessibilityLabel(Localization.localized("settings.title"))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(Localization.localized("actions.done")) { dismiss() }
                        .foregroundStyle(AppTheme.accent)
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
                Button(Localization.localized("common.ok"), role: .cancel) {}
            } message: {
                Text(Localization.localized("settings.description"))
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
                            colors: [AppTheme.accent.opacity(0.3), AppTheme.accent.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)

                Image(systemName: "gearshape.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
            }

            VStack(spacing: 4) {
                Text(Localization.localized("settings.title"))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(Localization.localized("settings.subtitle"))
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