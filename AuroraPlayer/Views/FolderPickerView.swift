import SwiftUI
import UniformTypeIdentifiers

struct FolderPickerView: View {
    @ObservedObject var fileAccessService: FileAccessService
    @Environment(\.dismiss) private var dismiss

    @State private var showFolderImporter = false
    @State private var showFileImporter = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showFolderImporter = true
                    } label: {
                        HStack {
                            Image(systemName: "folder.fill")
                            Text("Añadir carpeta")
                        }
                    }

                    Button {
                        showFileImporter = true
                    } label: {
                        HStack {
                            Image(systemName: "music.note")
                            Text("Añadir archivos")
                        }
                    }

                    Button {
                        fileAccessService.refreshAllFolders()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Actualizar biblioteca")
                        }
                    }
                    .disabled(fileAccessService.isScanning)
                } header: {
                    Text("Acciones")
                }

                Section {
                    if fileAccessService.folders.isEmpty {
                        Text("No hay carpetas añadidas")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(fileAccessService.folders) { folder in
                            HStack {
                                Image(systemName: "folder.fill")
                                Text(folder.displayName)
                                Spacer()
                                Button(role: .destructive) {
                                    fileAccessService.removeFolder(folder)
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    Text("Carpetas")
                }

                Section {
                    if fileAccessService.files.isEmpty {
                        Text("No hay archivos individuales")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(fileAccessService.files) { file in
                            HStack {
                                Image(systemName: "music.note")
                                Text(file.displayName)
                                Spacer()
                                Button(role: .destructive) {
                                    fileAccessService.removeFile(file)
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    Text("Archivos individuales")
                }
            }
            .navigationTitle("Biblioteca")
            .navigationBarTitleDisplayMode(.inline)
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

        return types
    }

    // MARK: - Import Handling

    private func handleFolderResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                AppLog.error(.library, "No se seleccionó ninguna carpeta")
                return
            }
            fileAccessService.addFolder(url: url)

        case .failure(let error):
            AppLog.error(.library, "Error al seleccionar carpeta: \(error.localizedDescription)")
        }
    }

    private func handleFileResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else {
                AppLog.error(.library, "No se seleccionaron archivos")
                return
            }
            fileAccessService.addFiles(urls: urls)

        case .failure(let error):
            AppLog.error(.library, "Error al seleccionar archivos: \(error.localizedDescription)")
        }
    }
}