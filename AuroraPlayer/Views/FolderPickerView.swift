import SwiftUI
import UniformTypeIdentifiers

struct FolderPickerView: View {
    @ObservedObject var fileAccessService: FileAccessService
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
                LinearGradient(
                    colors: [
                        Color(UIColor.systemBackground),
                        Color(UIColor.tertiarySystemBackground).opacity(0.4),
                        Color(UIColor.systemBackground)
                    ],
                    startPoint: .top, endPoint: .bottom
                ).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(UIColor.systemBackground).opacity(0.92), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                // Título personalizado consistente con la app
                ToolbarItem(placement: .principal) {
                    Text("Biblioteca")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [AppTheme.accent, AppTheme.accent.opacity(0.75)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .accessibilityLabel("Biblioteca")
                }

                ToolbarItem(placement: .topBarTrailing) {
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
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { headerPulse = true }
            }
        }
    }

    // MARK: - Header Section con animación

    private var headerSection: some View {
        VStack(spacing: 14) {
            ZStack {
                // ✅ Anillo pulsante
                Circle()
                    .stroke(AppTheme.accent.opacity(0.2), lineWidth: 2)
                    .frame(width: 80, height: 80)
                    .scaleEffect(headerPulse ? 1.1 : 0.95)
                    .opacity(headerPulse ? 0.5 : 0.2)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.accent.opacity(0.15), AppTheme.accent.opacity(0.05)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 68, height: 68)

                Image(systemName: "music.note.list")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
            }
            .opacity(appearAnimation ? 1 : 0)
            .scaleEffect(appearAnimation ? 1 : 0.7)

            VStack(spacing: 6) {
                Text(Localization.localized("library.title"))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(Localization.localized("library.subtitle"))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .opacity(appearAnimation ? 1 : 0)
            .offset(y: appearAnimation ? 0 : 10)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
        }
        .animation(.easeOut(duration: 0.5).delay(0.1), value: appearAnimation)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                importMode = .folders
                showImporter = true
            } label: {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.accent.opacity(0.12))
                            .frame(width: 44, height: 44)

                        Image(systemName: "folder.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Añadir carpeta")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text("Selecciona una carpeta completa")
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
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .shadow(color: AppTheme.accent.opacity(0.08), radius: 8, y: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle(scale: 0.97))

            Button {
                importMode = .files
                showImporter = true
            } label: {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.accent.opacity(0.12))
                            .frame(width: 44, height: 44)

                        Image(systemName: "music.note")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Añadir archivos")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text("Selecciona canciones individuales")
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
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .shadow(color: AppTheme.accent.opacity(0.08), radius: 8, y: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle(scale: 0.97))

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
                        Text("Actualizar biblioteca")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text("Rescanear carpetas existentes")
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
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .shadow(color: Color.orange.opacity(0.08), radius: 8, y: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle(scale: 0.97))
            .disabled(fileAccessService.isScanning)
        }
    }

    // MARK: - Scanning Progress

    private var scanningProgress: some View {
        VStack(spacing: 12) {
            HStack {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.accent))

                Text("Escaneando biblioteca...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
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
                            .foregroundStyle(AppTheme.accent)

                        Text("Carpetas")
                            .font(.headline)
                    }
                    .padding(.horizontal, 4)

                    VStack(spacing: 8) {
                        ForEach(fileAccessService.folders) { folder in
                            HStack {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(AppTheme.accent.opacity(0.12))
                                        .frame(width: 38, height: 38)

                                    Image(systemName: "folder.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(AppTheme.accent)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(folder.displayName)
                                        .font(.subheadline.weight(.medium))

                                    Text("Carpeta añadida")
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
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(.ultraThinMaterial)
                            }
                        }
                    }
                    .background {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                }
            }

            // Files Section
            if !fileAccessService.files.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "music.note")
                            .foregroundStyle(AppTheme.accent)

                        Text("Archivos individuales")
                            .font(.headline)
                    }
                    .padding(.horizontal, 4)

                    VStack(spacing: 8) {
                        ForEach(fileAccessService.files) { file in
                            HStack {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(AppTheme.accent.opacity(0.12))
                                        .frame(width: 38, height: 38)

                                    Image(systemName: "music.note")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(AppTheme.accent)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.displayName)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)

                                    Text("Archivo individual")
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
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(.ultraThinMaterial)
                            }
                        }
                    }
                    .background {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                }
            }

            // Empty State
            if fileAccessService.folders.isEmpty && fileAccessService.files.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "music.note")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)

                    Text("Tu biblioteca está vacía")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    Text("Añade carpetas o archivos para empezar")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
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