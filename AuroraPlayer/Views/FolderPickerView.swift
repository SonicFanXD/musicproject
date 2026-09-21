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
    // ✅ Secciones COLAPSABLES: con la hoja a media altura, las listas de carpetas
    // y archivos abiertas empujaban las acciones fuera de la vista.
    @State private var showFolders = false
    @State private var showFiles = false

    enum ImportMode {
        case folders
        case files
        case both
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        headerSection

                        actionButtons

                        if fileAccessService.isScanning {
                            scanningProgress
                        }

                        libraryContent
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                // Título personalizado consistente con la app
                ToolbarItem(placement: .principal) {
                    Text(Localization.localized("library.title"))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        // ✅ Acento de dos colores (antes un solo color con opacidad).
                        .foregroundStyle(AppTheme.accentGradient)
                        .accessibilityLabel(Localization.localized("library.title"))
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(Localization.localized("actions.done")) {
                        dismiss()
                    }
                    .frame(width: 44, height: 44) // Bigger invisible touch target
                    .contentShape(Rectangle())
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: importMode == .folders ? [.folder] : supportedAudioTypes,
                allowsMultipleSelection: importMode == .files
            ) { result in
                handleImportResult(result)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.5)) { appearAnimation = true }
            }
        }
    }

    // MARK: - Header Section (compacto)
    // ✅ Antes medía ~280pt: anillo de 88pt con latido `repeatForever` + disco de
    // 76pt + icono de 32pt + título de 24pt, en una pantalla que existe para
    // añadir una carpeta. Ahora es la mitad y el anillo es ESTÁTICO: el latido
    // pedía frames de forma indefinida (también en segundo plano, justo lo que
    // no debe pasar) y competía con la animación de entrada.
    private var headerSection: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(AppTheme.accentGradient(opacity: 0.4), lineWidth: 1.5)
                    .frame(width: 64, height: 64)

                Circle()
                    .fill(AnyShapeStyle(.ultraThinMaterial))
                    .frame(width: 56, height: 56)
                    .overlay {
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [AppTheme.accent.opacity(0.3), .clear],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.2
                            )
                    }

                Image(systemName: "music.note.list")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(AppTheme.accentGradient)
            }
            .opacity(appearAnimation ? 1 : 0)
            .scaleEffect(appearAnimation ? 1 : 0.7)

            VStack(spacing: 4) {
                Text(Localization.localized("library.title"))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(Localization.localized("library.subtitle"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .opacity(appearAnimation ? 1 : 0)
            .offset(y: appearAnimation ? 0 : 10)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AnyShapeStyle(.ultraThinMaterial))
                .shadow(color: .black.opacity(0.06), radius: 12, y: 5)
        }
        .animation(.easeOut(duration: 0.5).delay(0.1), value: appearAnimation)
    }

    // MARK: - Action Buttons (densos)
    /// ✅ Las tres acciones estaban escritas a mano con el MISMO bloque de ~45
    /// líneas cada una (y con 16pt de padding vertical: botones gigantes en una
    /// hoja que ahora abre a media altura). Ahora hay una sola fila reutilizable.
    private var actionButtons: some View {
        VStack(spacing: 10) {
            actionRow(
                icon: "folder.fill",
                title: Localization.localized("folders.addFolder"),
                subtitle: Localization.localized("folders.addFolderSubtitle"),
                isAccent: true
            ) {
                importMode = .folders
                showImporter = true
            }

            actionRow(
                icon: "music.note",
                title: Localization.localized("folders.addFiles"),
                subtitle: Localization.localized("folders.addFilesSubtitle"),
                isAccent: true
            ) {
                importMode = .files
                showImporter = true
            }

            actionRow(
                icon: "arrow.clockwise",
                title: Localization.localized("folders.refresh"),
                subtitle: Localization.localized("folders.refreshSubtitle"),
                isAccent: false
            ) {
                fileAccessService.refreshAllFolders()
            }
            .disabled(fileAccessService.isScanning)
        }
    }

    @ViewBuilder
    private func actionRow(
        icon: String,
        title: String,
        subtitle: String,
        isAccent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            isAccent
                                ? AnyShapeStyle(AppTheme.accentGradient(opacity: 0.12))
                                : AnyShapeStyle(Color.orange.opacity(0.12))
                        )
                        .frame(width: 36, height: 36)

                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(
                            isAccent
                                ? AnyShapeStyle(AppTheme.accentGradient)
                                : AnyShapeStyle(Color.orange)
                        )
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Scanning Progress

    private var scanningProgress: some View {
        HStack(spacing: 10) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.accent))

            Text(Localization.localized("folders.scanning"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }

    // MARK: - Library Content

    private var libraryContent: some View {
        VStack(spacing: 12) {
            // ✅ SECCIONES COLAPSABLES: con la hoja a media altura, tener las dos
            // listas desplegadas empujaba las acciones fuera de la pantalla. El
            // contador queda visible aunque estén plegadas.
            if !fileAccessService.folders.isEmpty {
                collapsibleSection(
                    title: Localization.localized("folders.folderSection"),
                    icon: "folder.fill",
                    count: fileAccessService.folders.count,
                    isExpanded: $showFolders
                ) {
                    VStack(spacing: 6) {
                        ForEach(fileAccessService.folders) { folder in
                            libraryRow(
                                icon: "folder.fill",
                                title: folder.displayName,
                                subtitle: Localization.localized("folders.folderAdded")
                            ) {
                                fileAccessService.removeFolder(folder)
                            }
                        }
                    }
                }
            }

            if !fileAccessService.files.isEmpty {
                collapsibleSection(
                    title: Localization.localized("folders.filesSection"),
                    icon: "music.note",
                    count: fileAccessService.files.count,
                    isExpanded: $showFiles
                ) {
                    VStack(spacing: 6) {
                        ForEach(fileAccessService.files) { file in
                            libraryRow(
                                icon: "music.note",
                                title: file.displayName,
                                subtitle: Localization.localized("folders.fileAdded")
                            ) {
                                fileAccessService.removeFile(file)
                            }
                        }
                    }
                }
            }

            if fileAccessService.folders.isEmpty && fileAccessService.files.isEmpty {
                emptyState
            }
        }
    }

    // MARK: - Sección colapsable

    /// ✅ `DisclosureGroup` con el contador en la etiqueta (visible aunque esté
    /// plegada). El chevron lo pone SwiftUI, así que no hay gesto nuevo que
    /// inventar y la fila sigue siendo táctil de lado a lado.
    @ViewBuilder
    private func collapsibleSection<Content: View>(
        title: String,
        icon: String,
        count: Int,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        DisclosureGroup(isExpanded: isExpanded) {
            content()
                .padding(.top, 8)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.accentGradient)

                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("\(count)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background {
                        Capsule().fill(Color(UIColor.tertiarySystemBackground))
                    }

                Spacer(minLength: 0)
            }
        }
        .tint(AppTheme.accent)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AnyShapeStyle(.ultraThinMaterial))
        }
    }

    // MARK: - Fila de carpeta / archivo

    /// ✅ Carpetas y archivos compartían dos bloques idénticos de ~50 líneas.
    @ViewBuilder
    private func libraryRow(
        icon: String,
        title: String,
        subtitle: String,
        onRemove: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(AppTheme.accentGradient(opacity: 0.12))
                    .frame(width: 34, height: 34)

                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.accentGradient)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 13))
                    .frame(width: 44, height: 44) // Bigger invisible touch target
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background {
            // ✅ 60fps: color OPACO (no material blur) para listas largas
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground).opacity(0.6))
        }
    }

    // MARK: - Estado vacío

    /// ✅ Estado vacío CON llamada a la acción: antes solo explicaba, y el botón
    /// para empezar estaba en la lista de acciones de arriba (fuera de la vista
    /// con la hoja a media altura).
    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppTheme.accentGradient(opacity: 0.1))
                    .frame(width: 64, height: 64)

                Image(systemName: "music.note")
                    .font(.system(size: 26, weight: .medium))
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

            Button {
                Haptics.light()
                importMode = .folders
                showImporter = true
            } label: {
                Label(Localization.localized("folders.addFolder"), systemImage: "folder.badge.plus")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background {
                        Capsule().fill(AppTheme.accentGradient)
                    }
            }
            .buttonStyle(PressableButtonStyle(scale: 0.96))
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
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