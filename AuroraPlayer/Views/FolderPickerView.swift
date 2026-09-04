import SwiftUI
import UniformTypeIdentifiers

struct FolderPickerView: View {
    @ObservedObject var fileAccessService: FileAccessService
    @Environment(\.dismiss) private var dismiss

    @State private var showFolderImporter = false
    @State private var showFileImporter = false
    @State private var isLoaded = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: 20) {
                        header
                        actionsSection
                        foldersSection
                        filesSection
                        Spacer(minLength: 30)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
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
                isPresented: $showFolderImporter,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                handleFolderResult(result)
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: supportedAudioTypes,
                allowsMultipleSelection: true
            ) { result in
                handleFileResult(result)
            }
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    isLoaded = true
                }
            }
            .scaleEffect(isLoaded ? 1 : 0.97)
            .opacity(isLoaded ? 1 : 0.85)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.16))
                    .frame(width: 76, height: 76)

                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            Text("Tu biblioteca musical")
                .font(.system(size: 24, weight: .bold))

            Text("Añade carpetas o archivos de música para que aparezcan en Aurora Player.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 18)
        .opaqueGlass(cornerRadius: 25, tint: .accentColor)
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(spacing: 12) {
            Button {
                showFolderImporter = true
            } label: {
                HStack(spacing: 13) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.white.opacity(0.16))

                        Image(systemName: "folder.fill")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .frame(width: 42, height: 42)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Añadir carpeta")
                            .font(.subheadline.weight(.bold))

                        Text("Escanear una carpeta completa")
                            .font(.caption)
                            .opacity(0.70)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .opacity(0.60)
                }
                .foregroundStyle(.primary)
                .padding(15)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .opaqueGlass(cornerRadius: 18, tint: .accentColor)

            Button {
                showFileImporter = true
            } label: {
                HStack(spacing: 13) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.white.opacity(0.12))

                        Image(systemName: "music.note")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .frame(width: 42, height: 42)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Añadir archivos")
                            .font(.subheadline.weight(.bold))

                        Text("Seleccionar canciones individualmente")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.primary)
                .padding(15)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .opaqueGlass(cornerRadius: 18, tint: .white)

            Button {
                fileAccessService.refreshAllFolders()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "arrow.clockwise")

                    Text(fileAccessService.isScanning ? "Escaneando…" : "Actualizar biblioteca")
                        .font(.subheadline.weight(.semibold))

                    if fileAccessService.isScanning {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
            }
            .buttonStyle(.plain)
            .disabled(fileAccessService.isScanning)
            .opaqueGlass(cornerRadius: 16, tint: .accentColor)
        }
    }

    // MARK: - Folders

    private var foldersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Carpetas", icon: "folder.fill")

            if fileAccessService.folders.isEmpty {
                emptyCard(icon: "folder", title: "No hay carpetas",
                          message: "Añade una carpeta para comenzar a importar música.")
            } else {
                VStack(spacing: 0) {
                    ForEach(fileAccessService.folders) { folder in
                        folderRow(folder)

                        if folder.id != fileAccessService.folders.last?.id {
                            Divider()
                                .opacity(0.12)
                                .padding(.leading, 60)
                        }
                    }
                }
                .background {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                }
            }
        }
    }

    private func folderRow(_ folder: MusicFolder) -> some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))

                Image(systemName: "folder.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(folder.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text("Carpeta de música")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(role: .destructive) {
                fileAccessService.removeFolder(folder)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.red.opacity(0.80))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
    }

    // MARK: - Files

    private var filesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Archivos individuales", icon: "music.note.list")

            if fileAccessService.files.isEmpty {
                emptyCard(icon: "music.note", title: "No hay archivos individuales",
                          message: "También puedes importar canciones sin añadir una carpeta completa.")
            } else {
                VStack(spacing: 0) {
                    ForEach(fileAccessService.files) { file in
                        fileRow(file)

                        if file.id != fileAccessService.files.last?.id {
                            Divider()
                                .opacity(0.12)
                                .padding(.leading, 60)
                        }
                    }
                }
                .background {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                }
            }
        }
    }

    private func fileRow(_ file: MusicFile) -> some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))

                Image(systemName: "music.note")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(file.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text("Archivo de música")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(role: .destructive) {
                fileAccessService.removeFile(file)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.red.opacity(0.80))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
    }

    // MARK: - Helpers

    private func sectionTitle(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)

            Text(title)
                .font(.headline)
        }
        .padding(.horizontal, 4)
    }

    private func emptyCard(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.subheadline.weight(.semibold))

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 18)
        .opaqueGlass(cornerRadius: 20, tint: .white)
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

        return types
    }

    // MARK: - Import Handling

    private func handleFolderResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            fileAccessService.addFolder(url: url)

        case .failure(let error):
            AppLog.error(.library, "Error al seleccionar carpeta: \(error.localizedDescription)")
        }
    }

    private func handleFileResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            fileAccessService.addFiles(urls: urls)

        case .failure(let error):
            AppLog.error(.library, "Error al seleccionar archivos: \(error.localizedDescription)")
        }
    }
}