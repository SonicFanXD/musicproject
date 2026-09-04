import SwiftUI
import UniformTypeIdentifiers

struct FolderPickerView: View {
    @ObservedObject var fileAccessService: FileAccessService
    @Environment(\.dismiss) private var dismiss

    @State private var showImporter = false
    @State private var importMode: ImportMode = .both

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
                    VStack(spacing: 20) {
                        headerSection

                        actionButtons

                        if fileAccessService.isScanning {
                            scanningProgress
                        }

                        libraryContent
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Biblioteca")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") {
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: importMode == .folders ? [.folder] : supportedAudioTypes,
                allowsMultipleSelection: importMode == .files
            ) { result in
                handleImportResult(result)
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.16))
                    .frame(width: 70, height: 70)

                Image(systemName: "music.note.list")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            Text("Tu Biblioteca")
                .font(.system(size: 22, weight: .bold))

            Text("Añade tu música para empezar")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .opaqueGlass(cornerRadius: 24, tint: .accentColor)
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
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: 44, height: 44)

                        Image(systemName: "folder.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
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
                .padding(.vertical, 12)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)

            Button {
                importMode = .files
                showImporter = true
            } label: {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: 44, height: 44)

                        Image(systemName: "music.note")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
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
                .padding(.vertical, 12)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)

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
                .padding(.vertical, 12)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .disabled(fileAccessService.isScanning)
        }
    }

    // MARK: - Scanning Progress

    private var scanningProgress: some View {
        VStack(spacing: 12) {
            HStack {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Color.accentColor))

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
                            .foregroundStyle(Color.accentColor)

                        Text("Carpetas")
                            .font(.headline)
                    }
                    .padding(.horizontal, 4)

                    VStack(spacing: 8) {
                        ForEach(fileAccessService.folders) { folder in
                            HStack {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.accentColor.opacity(0.12))
                                        .frame(width: 38, height: 38)

                                    Image(systemName: "folder.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(Color.accentColor)
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
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    }
                }
            }

            // Files Section
            if !fileAccessService.files.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "music.note")
                            .foregroundStyle(Color.accentColor)

                        Text("Archivos individuales")
                            .font(.headline)
                    }
                    .padding(.horizontal, 4)

                    VStack(spacing: 8) {
                        ForEach(fileAccessService.files) { file in
                            HStack {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.accentColor.opacity(0.12))
                                        .frame(width: 38, height: 38)

                                    Image(systemName: "music.note")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(Color.accentColor)
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
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(.white.opacity(0.1), lineWidth: 1)
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