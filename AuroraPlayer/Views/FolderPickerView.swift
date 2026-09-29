import SwiftUI
import UniformTypeIdentifiers

struct FolderPickerView: View {
    @ObservedObject var fileAccessService: FileAccessService
    // ✅ Observado para que los textos se re-rendericen al cambiar de idioma en vivo.
    @ObservedObject private var localization = Localization.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showImporter = false
    @State private var importMode: ImportMode = .both
    @State private var appearAnimation = false
    @State private var headerPulse = false

    enum ImportMode {
        case folders
        case files
        case both
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                VStack(spacing: 0) {
                    // ✅ AURORA DESIGN: header de sheet del sistema en su propia fila
                    // (44pt, exactamente lo que medía la barra) con el título en el
                    // acento de la app y el "Listo" en el slot trailing: el contenido
                    // de abajo no cambia de tamaño ni de spacing.
                    AuroraSheetHeader(
                        title: Localization.localized("library.title"),
                        onClose: { dismiss() },
                        titleColor: AppTheme.accent,
                        trailing: AnyView(headerDoneButton)
                    )

                    ScrollView {
                        VStack(spacing: 20) {
                            headerSection

                            actionButtons

                            if fileAccessService.isScanning {
                                scanningProgress
                            }

                            libraryContent
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 8)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            // ✅ AURORA DESIGN: el toolbar (título + "Listo") se sustituye por el
            // header del sistema. La barra se oculta para que el header ocupe SU
            // altura (44pt) y no se sume un segundo bloque encima.
            .toolbar(.hidden, for: .navigationBar)
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: importMode == .folders ? [.folder] : supportedAudioTypes,
                allowsMultipleSelection: importMode == .files
            ) { result in
                handleImportResult(result)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.5)) { appearAnimation = true }
                // ✅ El anillo empieza a latir DESPUÉS de la entrada (0,25 s) para que
                // el pulso no compita con la escala de aparición del icono.
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true).delay(0.25)) {
                    headerPulse = true
                }
            }
        }
    }

    /// ✅ AURORA DESIGN: el "Listo" que antes vivía en el toolbar, ahora en el slot
    /// trailing del header. Es el MISMO botón y mide 44pt, lo mismo que el hueco
    /// fantasma del header, así que el título sigue perfectamente centrado.
    private var headerDoneButton: some View {
        Button(Localization.localized("actions.done")) {
            dismiss()
        }
        .frame(width: 44, height: 44) // Bigger invisible touch target
        .contentShape(Rectangle())
    }

    // MARK: - Header Section con animación

    private var headerSection: some View {
        VStack(spacing: 16) {
            ZStack {
                // ✅ Anillo pulsante con material de vidrio (estilo NowPlayingView)
                Circle()
                    .stroke(AppTheme.accentGradient(opacity: 0.45), lineWidth: 2)
                    .frame(width: 88, height: 88)
                    .scaleEffect(headerPulse ? 1.12 : 0.95)
                    .opacity(headerPulse ? 0.6 : 0.25)

                // ✅ AURORA DESIGN: primer uso del vidrio del sistema en esta vista
                // (`auroraGlass()`): mismo Shape y mismo tamaño, pero reactivo a
                // "Reducir transparencia".
                Circle()
                    .auroraGlass()
                    .frame(width: 76, height: 76)
                    .overlay {
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [AppTheme.accent.opacity(0.3), .clear],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    }

                Image(systemName: "music.note.list")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(AppTheme.accentGradient)
            }
            .opacity(appearAnimation ? 1 : 0)
            .scaleEffect(appearAnimation ? 1 : 0.7)

            VStack(spacing: 8) {
                Text(Localization.localized("library.title"))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(Localization.localized("library.subtitle"))
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .opacity(appearAnimation ? 1 : 0)
            .offset(y: appearAnimation ? 0 : 10)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        // ✅ AURORA DESIGN: los contenedores de este sheet pasan a ser cards del
        // sistema (mismo vidrio reactivo, radio y sombra unificados). Este header:
        // radio 24 original → .xl (28, +4pt) por jerarquía del sistema (card
        // destacada/hero) y sombra 0.06/12/5 ≈ AuroraShadow.soft (0.06/10/4).
        // Borde SÍ: no tenía y el sistema lo pone en sus glass cards.
        .auroraCard(radius: AuroraRadius.xl, style: .glass, withBorder: true, withShadow: true)
        .animation(.easeOut(duration: 0.5).delay(0.1), value: appearAnimation)
    }

    // MARK: - Action Buttons

    /// ✅ AURORA DESIGN: las tres filas-botón pasan al feedback de presión del
    /// sistema (0.92, `AuroraPressScale.button`) y su fondo alinea el radio a
    /// `AuroraRadius.md` (18, +2pt desde 16) para coincidir con las listas vecinas.
    /// Antes eran `.plain`: no respondían al tacto.
    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                importMode = .folders
                showImporter = true
            } label: {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.accentGradient(opacity: 0.12))
                            .frame(width: 44, height: 44)

                        Image(systemName: "folder.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppTheme.accentGradient)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(Localization.localized("folders.addFolder"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text(Localization.localized("folders.addFolderSubtitle"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16) // Expanded touch target
                .background {
                    RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                        .auroraGlass()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle(scale: AuroraPressScale.button))

            Button {
                importMode = .files
                showImporter = true
            } label: {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.accentGradient(opacity: 0.12))
                            .frame(width: 44, height: 44)

                        Image(systemName: "music.note")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppTheme.accentGradient)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(Localization.localized("folders.addFiles"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text(Localization.localized("folders.addFilesSubtitle"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16) // Expanded touch target
                .background {
                    RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                        .auroraGlass()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle(scale: AuroraPressScale.button))

            Button {
                fileAccessService.refreshAllFolders()
            } label: {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.orange.opacity(0.12))
                            .frame(width: 44, height: 44)

                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.orange)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(Localization.localized("folders.refresh"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text(Localization.localized("folders.refreshSubtitle"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16) // Expanded touch target
                .background {
                    RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                        .auroraGlass()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle(scale: AuroraPressScale.button))
            // ✅ El estilo de presión propio no lee `isEnabled`: se restaura aquí el
            // atenuado del estado deshabilitado (el `.plain` anterior lo daba solo).
            .opacity(fileAccessService.isScanning ? 0.5 : 1)
            .disabled(fileAccessService.isScanning)
        }
    }

    // MARK: - Scanning Progress

    private var scanningProgress: some View {
        VStack(spacing: 12) {
            HStack {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.accent))

                Text(Localization.localized("folders.scanning"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            // ✅ AURORA DESIGN: card "Escaneando" → card del sistema, radio .md
            // (18, +2pt desde 16 por consistencia con las listas vecinas) y sin
            // sombra (no tenía).
            .auroraCard(radius: AuroraRadius.md, style: .glass, withBorder: true, withShadow: false)
        }
    }

    // MARK: - Library Content

    private var libraryContent: some View {
        VStack(spacing: 16) {
            // Folders Section
            if !fileAccessService.folders.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(AppTheme.accentGradient)

                        Text(Localization.localized("folders.folderSection"))
                            .font(.headline)
                    }
                    .padding(.horizontal, 4)

                    VStack(spacing: 8) {
                        ForEach(fileAccessService.folders) { folder in
                            HStack {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .fill(AppTheme.accentGradient(opacity: 0.12))
                                        .frame(width: 40, height: 40)

                                    Image(systemName: "folder.fill")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(AppTheme.accentGradient)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(folder.displayName)
                                        .font(.subheadline.weight(.medium))

                                    Text(Localization.localized("folders.folderAdded"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button(role: .destructive) {
                                    fileAccessService.removeFolder(folder)
                                } label: {
                                    Image(systemName: "trash.fill")
                                        .font(.caption)
                                        .frame(width: 44, height: 44) // Bigger invisible touch target
                                        .contentShape(Rectangle())
                                }
                            }
                            .padding(.horizontal, 15)
                            .padding(.vertical, 10)
                            .background {
                                // ✅ 60fps: color OPACO (no material blur) para listas largas
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(UIColor.secondarySystemBackground).opacity(0.6))
                            }
                        }
                    }
                    // ✅ AURORA DESIGN: contenedor de lista → card del sistema,
                    // radio .md exacto (18) y sin sombra (no tenía). OJO: las filas
                    // de dentro son full-bleed con radio 14, así que el clipShape
                    // del card les redondea las esquinas extremas a 18 y el borde
                    // pasa a ir por encima de su filo.
                    .auroraCard(radius: AuroraRadius.md, style: .glass, withBorder: true, withShadow: false)
                }
            }

            // Files Section
            if !fileAccessService.files.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "music.note")
                            .foregroundStyle(AppTheme.accentGradient)

                        Text(Localization.localized("folders.filesSection"))
                            .font(.headline)
                    }
                    .padding(.horizontal, 4)

                    VStack(spacing: 8) {
                        ForEach(fileAccessService.files) { file in
                            HStack {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .fill(AppTheme.accentGradient(opacity: 0.12))
                                        .frame(width: 40, height: 40)

                                    Image(systemName: "music.note")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(AppTheme.accentGradient)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.displayName)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)

                                    Text(Localization.localized("folders.fileAdded"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button(role: .destructive) {
                                    fileAccessService.removeFile(file)
                                } label: {
                                    Image(systemName: "trash.fill")
                                        .font(.caption)
                                        .frame(width: 44, height: 44) // Bigger invisible touch target
                                        .contentShape(Rectangle())
                                }
                            }
                            .padding(.horizontal, 15)
                            .padding(.vertical, 10)
                            .background {
                                // ✅ 60fps: color OPACO (no material blur) para listas largas
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(UIColor.secondarySystemBackground).opacity(0.6))
                            }
                        }
                    }
                    // ✅ AURORA DESIGN: contenedor de lista → card del sistema,
                    // radio .md exacto (18) y sin sombra (no tenía). OJO: las filas
                    // de dentro son full-bleed con radio 14, así que el clipShape
                    // del card les redondea las esquinas extremas a 18 y el borde
                    // pasa a ir por encima de su filo.
                    .auroraCard(radius: AuroraRadius.md, style: .glass, withBorder: true, withShadow: false)
                }
            }

            // Empty State
            if fileAccessService.folders.isEmpty && fileAccessService.files.isEmpty {
                VStack(spacing: 12) {
                    // ✅ Estado vacío con el icono del header (mismo lenguaje visual
                    // que el resto: acento de dos colores sobre un disco suave).
                    ZStack {
                        Circle()
                            .fill(AppTheme.accentGradient(opacity: 0.1))
                            .frame(width: 72, height: 72)

                        Image(systemName: "music.note")
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(AppTheme.accentGradient)
                    }
                    .padding(.bottom, 2)

                    Text(Localization.localized("folders.emptyTitle"))
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(Localization.localized("folders.emptySubtitle"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                // ✅ AURORA DESIGN: estado vacío → card del sistema, radio .md
                // exacto (18) y sin sombra (no tenía).
                .auroraCard(radius: AuroraRadius.md, style: .glass, withBorder: true, withShadow: false)
            }
        }
    }

    // MARK: - File Types

    private var supportedAudioTypes: [UTType] {
        var types: [UTType] = [.audio]

        if let mp3 = UTType(filenameExtension: "mp3") {
            types.append(mp3)
        }

        if let flac = UTType(filenameExtension: "flac") {
            types.append(flac)
        }

        if let m4a = UTType(filenameExtension: "m4a") {
            types.append(m4a)
        }

        if let wav = UTType(filenameExtension: "wav") {
            types.append(wav)
        }

        if let aiff = UTType(filenameExtension: "aiff") {
            types.append(aiff)
        }

        if let ogg = UTType(filenameExtension: "ogg") {
            types.append(ogg)
        }

        if let wma = UTType(filenameExtension: "wma") {
            types.append(wma)
        }

        // ✅ Dolby Digital (AC-3) y Dolby Digital Plus (E-AC-3)
        if let ac3 = UTType(filenameExtension: "ac3") {
            types.append(ac3)
        }

        if let ec3 = UTType(filenameExtension: "ec3") {
            types.append(ec3)
        }

        if let eac3 = UTType(filenameExtension: "eac3") {
            types.append(eac3)
        }

        if let ddp = UTType(filenameExtension: "ddp") {
            types.append(ddp)
        }

        return types
    }

    // MARK: - Import Handling

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
            case .both:
                // Handle mixed selection
                for url in urls {
                    if url.hasDirectoryPath {
                        fileAccessService.addFolder(url: url)
                    } else {
                        fileAccessService.addFiles(urls: [url])
                    }
                }
            }

        case .failure(let error):
            AppLog.error(.library, "Error al importar: \(error.localizedDescription)")
        }
    }
}