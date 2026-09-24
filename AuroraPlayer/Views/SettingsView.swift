import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View, SettingsRowBuilding {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var fileAccessService: FileAccessService
    @Environment(\.dismiss) private var dismiss

    @State private var showImporter = false
    @State private var showLogs = false
    @State private var showAbout = false
    @State private var showEqualizerSheet = false
    // ✅ FASE C1: confirmación destructiva del reset de ajustes
    @State private var showResetSettingsAlert = false
    // ✅ FASE C1: confirmación del reset de caché de biblioteca
    @State private var showResetCacheAlert = false
    @State private var selectedThemeIndex: Int

    /// ✅ Gestión embebida de biblioteca (sin pantalla aparte):
    /// .folders = picker de carpetas, .files = picker de canciones.
    private enum ImportMode { case folders, files }
    @State private var importMode: ImportMode = .folders
    // ✅ Observar el tema (el header reacciona al acento) y el idioma (los
    // títulos se re-renderizan al instante). Cada sección observa por su
    // cuenta lo que necesita, así el tipo del `body` padre deja de crecer.
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var localization = Localization.shared

    private let themeDefaultsKey = "com.aurora.uiTheme"

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "21"
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
                AppBackground()

                ScrollView {
                    VStack(spacing: 22) {
                        headerSection

                        // Biblioteca (gestión embebida: sin pantalla aparte)
                        LibrarySettingsSection(
                            fileAccessService: fileAccessService,
                            onAddFolder: {
                                importMode = .folders
                                showImporter = true
                            },
                            onAddFiles: {
                                importMode = .files
                                showImporter = true
                            }
                        )

                        // Audio
                        // ✅ Crossfade eliminado por completo (fuente de bugs
                        // de sincronización): ya no aparece en Ajustes.
                        AudioSettingsSection(
                            audioEngine: audioEngine,
                            showEqualizerSheet: $showEqualizerSheet
                        )

                        // Apariencia
                        AppearanceSettingsSection(
                            selectedThemeIndex: $selectedThemeIndex,
                            themeDefaultsKey: themeDefaultsKey
                        )

                        // ✅ Acento de portada: control unificado para todo el entorno
                        // (NowPlaying, álbumes, artistas, PlayerBar, tint global UIKit).
                        // Un solo ajuste activa/desactiva la detección de colores en
                        // TODAS las vistas simultáneamente.
                        ArtworkAccentSettingsSection()

                        // Reproducción
                        PlaybackSettingsSection(audioEngine: audioEngine)

                        // ✅ Personalización avanzada
                        CustomizationSettingsSection()

                        // Rendimiento (info técnica)
                        PerformanceSettingsSection(audioEngine: audioEngine)

                        // Estadísticas (✅ incluye canciones en proceso de indexación)
                        StatsSettingsSection(fileAccessService: fileAccessService)

                        // Avanzado
                        AdvancedSettingsSection(
                            appVersion: appVersion,
                            onShowLogs: { showLogs = true },
                            onShowAbout: { showAbout = true },
                            onResetSettings: { showResetSettingsAlert = true },
                            onResetCache: { showResetCacheAlert = true }
                        )
                    }
                    .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                SettingsToolbar(onDone: { dismiss() })
            }
            .sheet(isPresented: $showLogs) {
                LogsView()
            }
            .sheet(isPresented: $showEqualizerSheet) {
                EqualizerView(audioEngine: audioEngine)
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: importMode == .folders ? [.folder] : supportedAudioTypes,
                allowsMultipleSelection: importMode == .files
            ) { result in
                handleImportResult(result)
            }
            .alert("Aurora Player v\(appVersion)", isPresented: $showAbout) {
                Button(Localization.localized("common.ok"), role: .cancel) {}
            } message: {
                Text(Localization.localized("settings.description"))
            }
            // ✅ FASE C1: confirmación destructiva antes de restablecer ajustes
            .alert(Localization.localized("settings.resetSettings"), isPresented: $showResetSettingsAlert) {
                Button(Localization.localized("actions.cancel"), role: .cancel) {}
                Button(Localization.localized("settings.resetConfirm"), role: .destructive) {
                    resetAllSettings()
                }
            } message: {
                Text(Localization.localized("settings.resetSettingsMessage"))
            }
            // ✅ FASE C1: confirmación del reset de caché de biblioteca
            .alert(Localization.localized("settings.resetCache"), isPresented: $showResetCacheAlert) {
                Button(Localization.localized("actions.cancel"), role: .cancel) {}
                Button(Localization.localized("settings.resetConfirm"), role: .destructive) {
                    resetLibraryCache()
                }
            } message: {
                Text(Localization.localized("settings.resetCacheMessage"))
            }
        }
    }

    // MARK: - Header (diseño premium estilo NowPlayingView)
    private var headerSection: some View {
        VStack(spacing: 16) {
            ZStack {
                // ✅ Círculo con tinte suave (sin blur: cero re-muestreo en scroll)
                Circle()
                    .fill(theme.resolvedAccentGradient(opacity: 0.12))
                    .frame(width: 88, height: 88)
                    .overlay {
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [theme.resolvedAccent.opacity(0.5), theme.resolvedAccent.opacity(0.1), .clear],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    }
                    .shadow(color: theme.resolvedAccent.opacity(0.2), radius: 12, x: 0, y: 6)

                Image(systemName: "gearshape.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [theme.resolvedAccent, theme.resolvedAccent.opacity(0.7)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            }

            VStack(spacing: 6) {
                Text(Localization.localized("settings.title"))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(Localization.localized("settings.subtitle"))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                // ✅ Versión visible en el header (los números de versión no se
                // traducen, así que no hace falta una key de Localización).
                Text(appVersionLabel)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background {
            // ✅ Fondo opaco + borde gradiente sutil (look vidrio sin blur)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.14), .clear, .white.opacity(0.06)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }

    /// ✅ "Versión 2.2.0 · Build 22": leído del bundle y localizado con las
    /// keys que ya existían (settings.version / settings.build).
    private var appVersionLabel: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(Localization.localized("settings.version")) \(short) · \(Localization.localized("settings.build")) \(build)"
    }

    // MARK: - Fase C1: reset de ajustes a valores por defecto

    /// ✅ SOLO preferencias de usuario. NO incluye claves de DATOS: biblioteca
    /// (`musicFolders`/`musicFiles`), playlists, "Me gusta", estado de
    /// reproducción, primera indexación ni la categoría seleccionada — el reset
    /// de ajustes nunca borra contenido del usuario.
    private static let userSettingsKeys: [String] = [
        // Apariencia / reproducción
        "com.aurora.showVisualizer",
        "com.aurora.enableHaptics",
        "com.aurora.keepScreenOn",
        "com.aurora.artworkCorner",
        "com.aurora.reduceTransparency",
        "com.aurora.hapticIntensity",
        "com.aurora.showLyricsByDefault",
        "com.aurora.autoPlayOnStart",
        "com.aurora.showVisualizerInBar",
        "com.aurora.compactPlayerBar",
        "com.aurora.language",
        "com.aurora.showFPS",
        "com.aurora.uiTheme",
        // Biblioteca: comportamiento del botón "Actualizar"
        "com.aurora.scanOnlyNewSongs",
        // Audio
        "com.aurora.audioSessionMode",
        "com.aurora.eqEnabled",
        "com.aurora.eqPreset",
        "com.aurora.limiterEnabled",
        "com.aurora.monoAudio",
        // Acento
        "com.aurora.accentColor",
        "com.aurora.accentFromArtwork",
        "com.aurora.accentHeuristicV2",
        // Controles de reproducción persistentes
        "com.aurora.shuffleEnabled",
        "com.aurora.repeatMode",
        // Ordenación de la biblioteca
        "com.aurora.songSort",
        "com.aurora.songSortAscending",
        "com.aurora.albumSort",
        "com.aurora.albumSortAscending",
        "com.aurora.artistSort",
        "com.aurora.artistSortAscending"
    ]

    /// ✅ Valores de una instalación nueva, exactamente los mismos que declaran
    /// los `@AppStorage` de cada sub-vista de sección. El reset los escribe en
    /// `UserDefaults` (el almacén que cada `@AppStorage` observa) porque los
    /// ajustes ya no viven en este struct: así todas las secciones se actualizan
    /// solas, sin dejar el padre anidando una sección dentro de otra.
    private static let userSettingsDefaults: [String: Any] = [
        "com.aurora.showVisualizer": true,
        "com.aurora.enableHaptics": true,
        "com.aurora.keepScreenOn": false,
        "com.aurora.artworkCorner": 22.0,
        "com.aurora.reduceTransparency": false,
        "com.aurora.hapticIntensity": 1.0,
        "com.aurora.showLyricsByDefault": false,
        "com.aurora.autoPlayOnStart": false,
        "com.aurora.showVisualizerInBar": true,
        "com.aurora.compactPlayerBar": false,
        "com.aurora.language": 0,
        "com.aurora.showFPS": false,
        "com.aurora.scanOnlyNewSongs": true,
        "com.aurora.audioSessionMode": 0
    ]

    /// ✅ Restablece los ajustes a los valores de una instalación nueva:
    /// borra las claves de preferencias y vuelve a escribir los defaults. El
    /// motor se toca SOLO por sus APIs públicas, que son las que re-aplican el
    /// cambio al grafo de audio (un simple `UserDefaults.removeObject` no lo
    /// haría).
    private func resetAllSettings() {
        for key in Self.userSettingsKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }

        // 1) Ajustes de usuario → los defaults declarados en cada sección
        for (key, value) in Self.userSettingsDefaults {
            UserDefaults.standard.set(value, forKey: key)
        }

        // 2) Tema (0 = Sistema). La raíz lee `com.aurora.uiTheme` con @AppStorage,
        // así que se re-aplica al instante sin reiniciar.
        selectedThemeIndex = 0
        UserDefaults.standard.set(0, forKey: themeDefaultsKey)

        // 3) Motor: apagar solo lo que esté activo (los toggles re-aplican al
        // grafo: bypass del EQ, ganancia de salida, downmix mono, etc.)
        if audioEngine.isEQEnabled { audioEngine.toggleEQ() }
        audioEngine.setEQPreset(.flat)
        audioEngine.eqPreset = .flat // garantiza valor+persistencia si no hay nodo EQ
        if audioEngine.isLimiterEnabled { audioEngine.toggleLimiter() }
        if audioEngine.isMonoAudioEnabled { audioEngine.toggleMonoAudio() }
        if audioEngine.isKeepScreenOnEnabled { audioEngine.isKeepScreenOnEnabled = false }
        audioEngine.setAudioSessionMode(0)

        // 4) Cola: shuffle y repeat a su estado inicial
        if audioEngine.isShuffleEnabled { audioEngine.isShuffleEnabled = false }
        if audioEngine.repeatMode != .off { audioEngine.repeatMode = .off }

        // 5) Acento: manual (índice 0) y sin "acento desde carátula"
        if theme.accentFromArtwork { theme.accentFromArtwork = false }
        theme.setAccent(0)

        // 6) Idioma: español
        localization.currentLanguage = .spanish

        // 7) HUD de FPS: apagado inmediato (la raíz observa la clave)
        FPSOverlayController.shared.setEnabled(false)

        AppLog.info(.settings, "Ajustes restablecidos a valores por defecto (biblioteca y playlists intactas)")
    }

    /// ✅ Reset de caché de biblioteca: descarta todo lo DERIVADO en memoria
    /// (colores de acento de las carátulas, miniaturas y el índice de búsqueda)
    /// y pide una reindexación. Nunca borra canciones, carpetas ni playlists —
    /// la biblioteca se vuelve a leer desde los archivos y las cachés se
    /// reconstruyen solas en el siguiente uso.
    private func resetLibraryCache() {
        AppTheme.artworkColorCache.removeAllObjects()
        AppTheme.artworkSecondaryColorCache.removeAllObjects()
        AppTheme.thumbnailCache.removeAllObjects()
        LibrarySearchIndex.shared.invalidate()
        fileAccessService.refreshAllFolders()
        AppLog.info(.settings, "Caché de biblioteca restablecida (colores, miniaturas e índice) · reindexando")
    }

    // MARK: - Importación embebida (carpetas / canciones individuales)

    /// Tipos de audio soportados para el picker de archivos individuales.
    private var supportedAudioTypes: [UTType] {
        var types: [UTType] = [.audio]
        if let mp3 = UTType(filenameExtension: "mp3") { types.append(mp3) }
        if let flac = UTType(filenameExtension: "flac") { types.append(flac) }
        if let m4a = UTType(filenameExtension: "m4a") { types.append(m4a) }
        if let wav = UTType(filenameExtension: "wav") { types.append(wav) }
        if let aiff = UTType(filenameExtension: "aiff") { types.append(aiff) }
        if let ogg = UTType(filenameExtension: "ogg") { types.append(ogg) }
        if let wma = UTType(filenameExtension: "wma") { types.append(wma) }
        // ✅ Dolby Digital (AC-3) y Dolby Digital Plus (E-AC-3)
        if let ac3 = UTType(filenameExtension: "ac3") { types.append(ac3) }
        if let ec3 = UTType(filenameExtension: "ec3") { types.append(ec3) }
        if let eac3 = UTType(filenameExtension: "eac3") { types.append(eac3) }
        if let ddp = UTType(filenameExtension: "ddp") { types.append(ddp) }
        return types
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else {
                AppLog.error(.library, "No se seleccionó nada")
                return
            }
            switch importMode {
            case .folders:
                if let url = urls.first {
                    fileAccessService.addFolder(url: url)
                }
            case .files:
                fileAccessService.addFiles(urls: urls)
            }
        case .failure(let error):
            AppLog.error(.library, "Error al importar: \(error.localizedDescription)")
        }
    }
}

// MARK: - Secciones extraídas del body
//
// ✅ Cada sección es su PROPIO tipo con su propio `body`. Motivo (crash al abrir
// Ajustes): el tipo genérico del `body` de SettingsView era tan profundo
// (closures anidadas por cada picker, ForEach y sección) que el demangler de
// Swift desbordaba la pila al resolver su nombre en runtime → crash en la stack
// guard del hilo principal (traza llena de decodeMangledType), sin ninguna
// construcción que pudiera trapar. Con las secciones fuera, ningún tipo
// individual anida cuatro niveles de closure.
// El contenido es idéntico: solo cambia dónde vive.

/// Biblioteca: picker de carpetas/canciones, lista de lo añadido y escaneo.
private struct LibrarySettingsSection: View, SettingsRowBuilding {
    @ObservedObject var fileAccessService: FileAccessService
    @ObservedObject var localization = Localization.shared
    // ✅ El acento de la sección se re-aplica al cambiarlo desde Apariencia.
    @ObservedObject var theme = ThemeManager.shared
    let onAddFolder: () -> Void
    let onAddFiles: () -> Void
    @AppStorage("com.aurora.scanOnlyNewSongs") private var scanOnlyNewSongs = true

    var body: some View {
        settingsSection(icon: "folder.fill", title: Localization.localized("settings.library"), color: .blue) {
            settingsButton(title: Localization.localized("settings.addFolder"), subtitle: Localization.localized("settings.addFolderSubtitle"), icon: "folder.badge.plus", color: .blue) {
                onAddFolder()
            }
            settingsDivider
            settingsButton(title: Localization.localized("settings.addFiles"), subtitle: Localization.localized("settings.addFilesSubtitle"), icon: "music.note.badge.plus", color: .purple) {
                onAddFiles()
            }
            settingsDivider
            settingsToggleRow(
                title: Localization.localized("settings.scanOnlyNewSongs"),
                subtitle: Localization.localized("settings.scanOnlyNewSongsSubtitle"),
                icon: "magnifyingglass",
                color: .teal,
                isOn: $scanOnlyNewSongs
            )

            // ✅ Carpetas añadidas (lista embebida con eliminar)
            if !fileAccessService.folders.isEmpty {
                settingsDivider
                ForEach(fileAccessService.folders) { folder in
                    HStack(spacing: 14) {
                        iconView(icon: "folder.fill", color: .blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(folder.displayName)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(Localization.localized("settings.folderAdded"))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            fileAccessService.removeFolder(folder)
                        } label: {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.red)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
            }

            // ✅ Archivos individuales añadidos (lista embebida)
            if !fileAccessService.files.isEmpty {
                settingsDivider
                ForEach(fileAccessService.files) { file in
                    HStack(spacing: 14) {
                        iconView(icon: "music.note", color: .purple)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.displayName)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(Localization.localized("settings.fileAdded"))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            fileAccessService.removeFile(file)
                        } label: {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.red)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
            }

            if fileAccessService.folders.isEmpty && fileAccessService.files.isEmpty {
                settingsDivider
                VStack(spacing: 6) {
                    Text(Localization.localized("settings.emptyLibraryTitle"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(Localization.localized("settings.emptyLibrarySubtitle"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }

            settingsDivider
            settingsButton(title: Localization.localized("settings.updateLibrary"), subtitle: fileAccessService.isScanning ? Localization.localized("settings.scanning") : Localization.localized("settings.rescanFolders"), icon: "arrow.clockwise", color: .orange) {
                if scanOnlyNewSongs {
                    fileAccessService.scanForNewSongsOnly()
                } else {
                    fileAccessService.refreshAllFolders()
                }
            }
            .disabled(fileAccessService.isScanning)

            if fileAccessService.isScanning {
                HStack(spacing: 10) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: theme.resolvedAccent))
                    Text(Localization.localized("settings.scanning"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
        .onChange(of: scanOnlyNewSongs) { v in AppLog.info(.settings, "Escaneo solo nuevas: \(v ? "activado" : "desactivado")") }
    }
}

/// Audio: ecualizador, modo de sesión, mono y limitador.
/// ✅ Era la sección más anidada del body (dos pickers con closures de tres
/// niveles): ahora ese anidamiento vive aquí, no en el tipo del padre.
private struct AudioSettingsSection: View, SettingsRowBuilding {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var localization = Localization.shared
    // ✅ El acento de la sección se re-aplica al cambiarlo desde Apariencia.
    @ObservedObject var theme = ThemeManager.shared
    @Binding var showEqualizerSheet: Bool
    // ✅ AUDIÓFILO: configuración del modo de audio
    @AppStorage("com.aurora.audioSessionMode") private var audioSessionMode = 0 // 0 = default, 1 = measurement

    var body: some View {
        settingsSection(icon: "waveform", title: Localization.localized("settings.audio"), color: theme.resolvedAccent) {
            settingsButton(title: Localization.localized("settings.equalizer"), subtitle: audioEngine.isEQEnabled ? "\(Localization.localized("equalizer.active")) (\(audioEngine.eqPreset.displayName))" : Localization.localized("equalizer.disabled"), icon: "slider.horizontal.3", color: theme.resolvedAccent) {
                showEqualizerSheet = true
            }
            settingsDivider
            // ✅ AUDIÓFILO: modo de audio (Default vs Measurement)
            settingsMenuButton(
                title: Localization.localized("settings.audioMode"),
                subtitle: audioSessionMode > 0 ? "Measurement (bit-perfect)" : "Default",
                icon: "waveform.badge.micrometer",
                color: .orange,
                options: ["Default", "Measurement (bit-perfect)"],
                selection: Binding(
                    get: { self.audioSessionMode },
                    set: { newValue in
                        Haptics.light()
                        self.audioSessionMode = newValue
                        audioEngine.setAudioSessionMode(newValue)
                        AppLog.info(.settings, "Modo de audio: \(newValue == 1 ? "Measurement" : "Default")")
                    }
                ),
                onChange: { newValue in
                    // Actualizar directamente sin verificación de cambio
                    Haptics.light()
                    self.audioSessionMode = newValue
                    audioEngine.setAudioSessionMode(newValue)
                }
            )
            settingsDivider
            settingsToggleRow(
                title: Localization.localized("settings.monoAudio"),
                subtitle: Localization.localized("settings.monoAudioSubtitle"),
                icon: "ear",
                color: .cyan,
                isOn: Binding(
                    get: { audioEngine.isMonoAudioEnabled },
                    set: { newValue in
                        if newValue != audioEngine.isMonoAudioEnabled {
                            Haptics.light()
                            audioEngine.toggleMonoAudio()
                            AppLog.info(.settings, "Audio mono: \(newValue ? "activado" : "desactivado")")
                        }
                    }
                )
            )
            settingsDivider
            // ✅ LIMITER: anti-distorsión universal
            settingsToggleRow(
                title: Localization.localized("settings.limiter"),
                subtitle: Localization.localized("settings.limiterSubtitle"),
                icon: "waveform.path",
                color: .purple,
                isOn: Binding(
                    get: { audioEngine.isLimiterEnabled },
                    set: { newValue in
                        if newValue != audioEngine.isLimiterEnabled {
                            Haptics.light()
                            audioEngine.toggleLimiter()
                        }
                    }
                )
            )
            // ✅ ELIMINADO el toggle "Optimización Bluetooth": su
            // única acción real era escribir un log (no forzaba
            // buffer ni tasa, porque en A2DP la latencia y el
            // reloj los impone el enlace) y además no se
            // persistía. Un interruptor que no cambia nada es
            // peor que no tenerlo. La implementación interna
            // sigue en AudioEngine por si se le da uso futuro.
        }
    }
}

/// Apariencia: tema, color de acento, esquinas, transparencia e idioma.
/// El índice de tema sigue siendo `@State` del padre porque su valor inicial se
/// resuelve en `init`.
private struct AppearanceSettingsSection: View, SettingsRowBuilding {
    @ObservedObject var theme = ThemeManager.shared
    @ObservedObject var localization = Localization.shared
    @Binding var selectedThemeIndex: Int
    let themeDefaultsKey: String

    @AppStorage("com.aurora.artworkCorner") private var artworkCorner: Double = 22
    @AppStorage("com.aurora.reduceTransparency") private var reduceTransparency = false
    @AppStorage("com.aurora.language") private var selectedLanguage = 0 // 0 = español, 1 = inglés

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

    /// ✅ Subtítulo del picker a prueba de índices persistidos fuera de rango:
    /// un valor antiguo/corrupto en `UserDefaults` ya no puede romper el render
    /// (antes era `themes[selectedThemeIndex]` y compañía).
    private func safeText(_ values: [String], _ index: Int) -> String {
        values.indices.contains(index) ? values[index] : (values.first ?? "")
    }

    var body: some View {
        settingsSection(icon: "paintbrush.fill", title: Localization.localized("settings.appearance"), color: .pink) {
            settingsMenuButton(title: Localization.localized("settings.theme"), subtitle: safeText(themes, selectedThemeIndex), icon: "circle.lefthalf.filled", color: .gray, options: themes, selection: $selectedThemeIndex) { index in
                selectedThemeIndex = index
                UserDefaults.standard.set(index, forKey: themeDefaultsKey)
                AppLog.info(.settings, "Tema: \(safeText(themes, index))")
            }
            settingsDivider
            settingsMenuButton(title: Localization.localized("settings.accentColor"), subtitle: safeText(accents, theme.accentIndex), icon: "drop.fill", color: theme.accent, options: accents, selection: $theme.accentIndex) { index in
                theme.setAccent(index)
                AppLog.info(.settings, "Color de acento: \(safeText(accents, index))")
            }
            settingsDivider
            settingsSliderRow(title: Localization.localized("settings.artworkCorners"), value: $artworkCorner, range: 0...44, step: 2, color: .blue, suffix: "pt")
            settingsDivider
            settingsToggleRow(title: Localization.localized("settings.reduceTransparency"), subtitle: Localization.localized("settings.reduceTransparencySubtitle"), icon: "circle.slash", color: .gray, isOn: $reduceTransparency)
            settingsDivider
            settingsMenuButton(title: Localization.localized("settings.language"), subtitle: safeText(languages, selectedLanguage), icon: "globe", color: .blue, options: languages, selection: $selectedLanguage) { index in
                selectedLanguage = index
                // ✅ Aplicar el idioma al instante en toda la app
                Localization.shared.currentLanguage = Localization.Language(rawValue: index) ?? .spanish
                AppLog.info(.settings, "Idioma: \(safeText(languages, index))")
            }
        }
        .onChange(of: reduceTransparency) { v in AppLog.info(.settings, "Reducir transparencia: \(v ? "activado" : "desactivado")") }
    }
}

/// ✅ Acento de portada: control unificado para todo el entorno
/// (NowPlaying, álbumes, artistas, PlayerBar, tint global UIKit).
/// Un solo ajuste activa/desactiva la detección de colores en TODAS las vistas
/// simultáneamente.
private struct ArtworkAccentSettingsSection: View, SettingsRowBuilding {
    @ObservedObject var theme = ThemeManager.shared
    @ObservedObject var localization = Localization.shared

    var body: some View {
        settingsSection(icon: "swatchpalette.fill", title: Localization.localized("settings.artworkAccent"), color: .purple) {
            settingsToggleRow(
                title: Localization.localized("settings.artworkAccentToggle"),
                subtitle: Localization.localized("settings.artworkAccentSubtitle"),
                icon: "paintpalette.fill",
                color: .purple,
                isOn: Binding(
                    get: { theme.accentFromArtwork },
                    set: { theme.accentFromArtwork = $0 }
                )
            )
            settingsDivider
            // ✅ Algoritmo de extracción: HSB (OFF, comportamiento histórico) vs
            // Oklab (ON, clustering perceptualmente coherente). Red de seguridad
            // del usuario: si alguna portada resuelve mal, se vuelve a HSB sin
            // reinstalar. Se aplica a la PRÓXIMA extracción (las cachés de
            // acento no se invalidan aquí).
            settingsToggleRow(
                title: Localization.localized("settings.oklabClustering"),
                subtitle: Localization.localized("settings.oklabClusteringSubtitle"),
                icon: "circle.hexagongrid.fill",
                color: .blue,
                isOn: Binding(
                    get: { UserDefaults.standard.bool(forKey: "com.aurora.accentHeuristicV2") },
                    set: {
                        UserDefaults.standard.set($0, forKey: "com.aurora.accentHeuristicV2")
                        AppLog.info(.settings, "Clustering Oklab: \($0 ? "activado" : "desactivado")")
                    }
                )
            )
            settingsDivider
            // ✅ Indicador del color activo (extraído de la portada)
            HStack(spacing: 12) {
                Circle()
                    .fill(theme.artworkAccentColor ?? theme.accent)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle()
                            .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                    )
                    .shadow(color: (theme.artworkAccentColor ?? theme.accent).opacity(0.4), radius: 4, y: 2)
                Text(Localization.localized("settings.artworkAccentActive"))
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }
}

/// Reproducción: visualizador, haptics, pantalla encendida y autoplay.
private struct PlaybackSettingsSection: View, SettingsRowBuilding {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var localization = Localization.shared

    @AppStorage("com.aurora.showVisualizer") private var showVisualizer = true
    @AppStorage("com.aurora.enableHaptics") private var enableHaptics = true
    @AppStorage("com.aurora.keepScreenOn") private var keepScreenOn = false
    @AppStorage("com.aurora.autoPlayOnStart") private var autoPlayOnStart = false

    var body: some View {
        settingsSection(icon: "dial.max.fill", title: Localization.localized("settings.playback"), color: .orange) {
            settingsToggleRow(title: Localization.localized("settings.visualizer"), subtitle: Localization.localized("settings.visualizerSubtitle"), icon: "waveform.path.ecg", color: .pink, isOn: $showVisualizer)
            settingsDivider
            settingsToggleRow(title: Localization.localized("settings.haptics"), subtitle: Localization.localized("settings.hapticsSubtitle"), icon: "iphone.radiowaves.left.and.right", color: .mint, isOn: $enableHaptics)
            settingsDivider
            settingsToggleRow(title: Localization.localized("settings.keepScreenOn"), subtitle: Localization.localized("settings.keepScreenOnSubtitle"), icon: "sun.max.fill", color: .yellow, isOn: $keepScreenOn)
            settingsDivider
            settingsToggleRow(title: Localization.localized("settings.autoPlayOnStart"), subtitle: Localization.localized("settings.autoPlayOnStartSubtitle"), icon: "play.circle", color: .green, isOn: $autoPlayOnStart)
        }
        // ✅ Sincronización en vivo con el engine (antes solo
        // se aplicaba al reiniciar ContentView)
        .onChange(of: keepScreenOn) { newValue in
            audioEngine.isKeepScreenOnEnabled = newValue
            AppLog.info(.settings, "Mantener pantalla encendida: \(newValue ? "activado" : "desactivado")")
        }
        // ✅ LOGS TÉCNICOS: cambios de ajustes del usuario
        .onChange(of: showVisualizer) { v in AppLog.info(.settings, "Visualizador: \(v ? "activado" : "desactivado")") }
        .onChange(of: enableHaptics) { v in AppLog.info(.settings, "Haptics: \(v ? "activado" : "desactivado")") }
        .onChange(of: autoPlayOnStart) { v in AppLog.info(.settings, "Reproducir al iniciar: \(v ? "activado" : "desactivado")") }
    }
}

/// ✅ Personalización avanzada: intensidad de haptics y barra de reproducción.
private struct CustomizationSettingsSection: View, SettingsRowBuilding {
    @ObservedObject var localization = Localization.shared
    // ✅ El acento de la sección se re-aplica al cambiarlo desde Apariencia.
    @ObservedObject var theme = ThemeManager.shared

    @AppStorage("com.aurora.hapticIntensity") private var hapticIntensity: Double = 1.0
    @AppStorage("com.aurora.showVisualizerInBar") private var showVisualizerInBar = true
    @AppStorage("com.aurora.compactPlayerBar") private var compactPlayerBar = false
    @AppStorage("com.aurora.showLyricsByDefault") private var showLyricsByDefault = false

    var body: some View {
        settingsSection(icon: "wand.and.rays", title: Localization.localized("settings.customization"), color: .indigo) {
            settingsSliderRow(title: Localization.localized("settings.hapticIntensity"), value: $hapticIntensity, range: 0.0...1.0, step: 0.1, color: .mint, suffix: "")
            settingsDivider
            settingsToggleRow(title: Localization.localized("settings.showVisualizerInBar"), subtitle: Localization.localized("settings.showVisualizerInBarSubtitle"), icon: "waveform", color: theme.resolvedAccent, isOn: $showVisualizerInBar)
            settingsDivider
            settingsToggleRow(title: Localization.localized("settings.compactPlayerBar"), subtitle: Localization.localized("settings.compactPlayerBarSubtitle"), icon: "rectangle.compress.vertical", color: .gray, isOn: $compactPlayerBar)
            settingsDivider
            settingsToggleRow(title: Localization.localized("settings.showLyricsByDefault"), subtitle: Localization.localized("settings.showLyricsByDefaultSubtitle"), icon: "quote.bubble", color: .blue, isOn: $showLyricsByDefault)
        }
        // ✅ LOGS TÉCNICOS: cambios de ajustes del usuario
        .onChange(of: showVisualizerInBar) { v in AppLog.info(.settings, "Visualizador en barra: \(v ? "activado" : "desactivado")") }
        .onChange(of: compactPlayerBar) { v in AppLog.info(.settings, "Barra compacta: \(v ? "activado" : "desactivado")") }
        .onChange(of: showLyricsByDefault) { v in AppLog.info(.settings, "Letras por defecto: \(v ? "activado" : "desactivado")") }
    }
}

/// Rendimiento: contador de FPS e información técnica de la salida de audio.
/// ✅ El ajuste viaja con su efecto: el overlay de FPS se activa desde aquí
/// (antes vivía en la cadena de `onChange` del padre).
private struct PerformanceSettingsSection: View, SettingsRowBuilding {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var localization = Localization.shared
    @AppStorage("com.aurora.showFPS") private var showFPS = false

    var body: some View {
        settingsSection(icon: "gauge.open.with.needle", title: Localization.localized("settings.performance"), color: .indigo) {
            settingsToggleRow(title: Localization.localized("settings.showFPS"), subtitle: Localization.localized("settings.showFPSSubtitle"), icon: "speedometer", color: .green, isOn: $showFPS)
            settingsDivider
            settingsInfoRow(title: Localization.localized("settings.audioOutput"), value: audioEngine.audioQualityInfo.isEmpty ? "\(Int(audioEngine.outputSampleRate / 1000)) kHz · \(audioEngine.outputChannelCount)" : audioEngine.audioQualityInfo, icon: "speaker.wave.2.fill", color: .indigo)
            settingsDivider
            settingsInfoRow(title: Localization.localized("settings.playbackRoute"), value: audioEngine.routeDisplay, icon: "airplayaudio", color: .blue)
            settingsDivider
            // ✅ Modelo comercial real (ej. "iPhone 13 Pro") en vez de "iPhone"
            settingsInfoRow(title: Localization.localized("settings.device"), value: audioEngine.deviceModelName, icon: "iphone", color: .gray)
        }
        .onChange(of: showFPS) { v in
            AppLog.info(.settings, "Contador FPS: \(v ? "activado" : "desactivado")")
            FPSOverlayController.shared.setEnabled(v)
        }
    }
}

/// Estadísticas de la biblioteca (✅ incluye canciones en proceso de indexación).
private struct StatsSettingsSection: View, SettingsRowBuilding {
    @ObservedObject var fileAccessService: FileAccessService
    @ObservedObject var localization = Localization.shared

    var body: some View {
        // ✅ Incluye canciones en proceso de indexación.
        let totalSongs = fileAccessService.songs.count + fileAccessService.pendingSongsCount
        let isIndexing = fileAccessService.isScanning || fileAccessService.pendingSongsCount > 0
        settingsSection(icon: "chart.bar.fill", title: Localization.localized("settings.stats"), color: .green) {
            statRow(title: Localization.localized("library.songs"), value: isIndexing ? "\(totalSongs)+" : "\(totalSongs)")
            settingsDivider
            statRow(title: Localization.localized("library.albums"), value: "\(fileAccessService.albums.count)")
            settingsDivider
            statRow(title: Localization.localized("library.artists"), value: "\(fileAccessService.artists.count)")
        }
    }
}

/// Avanzado: logs, acerca de y los dos resets (con confirmación destructiva).
/// ✅ Las acciones viven en el padre: es quien posee el motor, el tema y el
/// idioma que hay que re-aplicar; aquí solo se piden.
private struct AdvancedSettingsSection: View, SettingsRowBuilding {
    @ObservedObject var localization = Localization.shared
    let appVersion: String
    let onShowLogs: () -> Void
    let onShowAbout: () -> Void
    let onResetSettings: () -> Void
    let onResetCache: () -> Void

    var body: some View {
        settingsSection(icon: "wrench.and.screwdriver.fill", title: Localization.localized("settings.advanced"), color: .orange) {
            settingsButton(title: Localization.localized("settings.logs"), subtitle: Localization.localized("settings.logsSubtitle"), icon: "doc.text.magnifyingglass", color: .gray) {
                onShowLogs()
            }
            settingsDivider
            settingsButton(title: Localization.localized("settings.about"), subtitle: "Aurora Player v\(appVersion)", icon: "info.circle.fill", color: .blue) {
                onShowAbout()
            }
            settingsDivider
            // ✅ FASE C1: reset de ajustes (destructivo, con confirmación).
            // NO toca biblioteca, playlists ni "Me gusta".
            settingsButton(title: Localization.localized("settings.resetSettings"), subtitle: Localization.localized("settings.resetSettingsSubtitle"), icon: "arrow.counterclockwise", color: .red) {
                onResetSettings()
            }
            settingsDivider
            // ✅ FASE C1: reset de caché derivada (colores, miniaturas,
            // índice de búsqueda). No borra canciones ni carpetas.
            settingsButton(title: Localization.localized("settings.resetCache"), subtitle: Localization.localized("settings.resetCacheSubtitle"), icon: "arrow.triangle.2.circlepath", color: .teal) {
                onResetCache()
            }
        }
    }
}

/// Barra de navegación de Ajustes: título con degradado y botón "Listo".
/// ⚠️ Extraída (como el resto de secciones) para que el tipo del `body` padre
/// deje de anidar closures dentro de `.toolbar`.
private struct SettingsToolbar: ToolbarContent {
    let onDone: () -> Void

    var body: some ToolbarContent {
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

        ToolbarItem(placement: .navigationBarTrailing) {
            Button(Localization.localized("actions.done")) { onDone() }
                .foregroundStyle(AppTheme.accent)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
    }
}

// MARK: - Helpers de fila compartidos
//
// ✅ Los helpers salen del struct de la vista y pasan a un protocolo con
// implementación por defecto: así las secciones se pueden extraer a sub-vistas
// sin duplicarlos ni cambiar un solo call site. Sin cambios visuales.

private protocol SettingsRowBuilding {}

extension SettingsRowBuilding {
    // MARK: - Section Builder (diseño premium estilo NowPlayingView)
    @ViewBuilder
    func settingsSection<Content: View>(
        icon: String, title: String, color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 30, height: 30)
                    .background {
                        // ✅ Micro-gradiente del MISMO tono de la sección: da
                        // profundidad sin cambiar el color identificativo de cada
                        // grupo (Biblioteca/Audio/Apariencia/...).
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [color.opacity(0.22), color.opacity(0.08)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(color.opacity(0.1), lineWidth: 0.5)
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
                // ✅ Color opaco del sistema (look Settings nativo de iOS):
                // sin blur, cero re-muestreo al hacer scroll = scroll fluido
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(UIColor.secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
            }
        }
    }

    // MARK: - Button Row
    @ViewBuilder
    func settingsButton(
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
    func settingsToggleRow(
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
    }

    // MARK: - Slider Row
    @ViewBuilder
    func settingsSliderRow(
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
    func settingsInfoRow(
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

    // MARK: - Icon (diseño premium estilo NowPlayingView)
    func iconView(icon: String, color: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 32, height: 32)
            .background {
                // ✅ Mismo micro-gradiente que los iconos de sección.
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.18), color.opacity(0.07)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(color.opacity(0.08), lineWidth: 0.5)
            }
    }

    // MARK: - Menu Picker Button Row
    @ViewBuilder
    func settingsMenuButton(
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
    func statRow(title: String, value: String) -> some View {
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
    var settingsDivider: some View {
        Divider()
            .opacity(0.1)
            .padding(.leading, 60)
    }
}

#Preview {
    SettingsView(audioEngine: AudioEngine(), fileAccessService: FileAccessService())
}
