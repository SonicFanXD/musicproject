
import UI
import UniformTypeIdentifiers

struct FolderPickerView:
    UIViewControllerRepresentable {

    @Binding
    var isPresented: Bool

    let onFolderPicked:
        (URL) -> Void

    func makeUIViewController(
        context: Context
    ) -> UIDocumentPickerViewController {

        let picker =
            UIDocumentPickerViewController(
                forOpeningContentTypes:
                    [.folder]
            )

        picker.delegate =
            context.coordinator

        picker.allowsMultipleSelection =
            false

        return picker
    }

    func updateUIViewController(
        _ uiViewController:
            UIDocumentPickerViewController,
        context: Context
    ) {
    }

    func makeCoordinator()
        -> Coordinator {

        Coordinator(
            isPresented:
                $isPresented,
            onFolderPicked:
                onFolderPicked
        )
    }

    final class Coordinator:
        NSObject,
        UIDocumentPickerDelegate {

        @Binding
        var isPresented: Bool

        let onFolderPicked:
            (URL) -> Void

        init(
            isPresented:
                Binding<Bool>,
            onFolderPicked:
                @escaping (URL) -> Void
        ) {

            self._isPresented =
                isPresented

            self.onFolderPicked =
                onFolderPicked
        }

        func documentPicker(
            _ controller:
                UIDocumentPickerViewController,
            didPickDocumentsAt urls:
                [URL]
        ) {

            defer {
                isPresented = false
            }

            guard
                let folderURL =
                    urls.first
            else {
                return
            }

            onFolderPicked(
                folderURL
            )
        }

        func documentPickerWasCancelled(
            _ controller:
                UIDocumentPickerViewController
        ) {

            isPresented = false
        }
    }
}

