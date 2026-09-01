import SwiftUI

struct SettingsView: View {
    @ObservedObject var library: FileAccessService
    @Environment(\.dismiss) private var dismiss
    @State private var showFolderPicker = false
    @State private var showFilePicker = false
    @State private var showLogs = false

    var body: some View {
        NavigationStack {
            List {
                Section("Música local") {
                    Button { showFolderPicker = true } label: { Label("Agregar carpeta", systemImage: "folder.badge.plus") }
                    Button { showFilePicker = true } label: { Label("Agregar canciones", systemImage: "music.note.list") }
                    Button { library.refreshAllFolders() } label: { Label("Actualizar biblioteca", systemImage: "arrow.clockwise") }
                }
                if !library.folders.isEmpty {
                    Section("Carpetas") {
                        ForEach(library.folders) { folder in Label(folder.displayName, systemImage: "folder") }
                            .onDelete { offsets in offsets.forEach { library.removeFolder(library.folders[$0]) } }
                    }
                }
                if !library.files.isEmpty {
                    Section("Archivos añadidos") {
                        ForEach(library.files) { file in Label(file.displayName, systemImage: "music.note") }
                            .onDelete { offsets in offsets.forEach { library.removeFile(library.files[$0]) } }
                    }
                }
                Section("Diagnóstico") {
                    Button { showLogs = true } label: { Label("Registros", systemImage: "text.alignleft") }
                }
            }
            .navigationTitle("Configuración")
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cerrar") { dismiss() } } }
        }
        .sheet(isPresented: $showFolderPicker) { FolderPickerView(isPresented: $showFolderPicker) { library.addFolder(url: $0) } }
        .sheet(isPresented: $showFilePicker) { MusicFilePickerView(isPresented: $showFilePicker) { library.addFiles(urls: $0) } }
        .sheet(isPresented: $showLogs) { LogsView() }
    }
}
