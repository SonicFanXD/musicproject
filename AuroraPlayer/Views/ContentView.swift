```swift
import SwiftUI

struct ContentView: View {

    @EnvironmentObject
    private var audioEngine: AudioEngine

    @StateObject
    private var fileAccessService =
        FileAccessService()

    @State private var showFolderPicker = false
    @State private var hasRestored = false

    var body: some View {

        NavigationStack {

            VStack(spacing: 0) {

                List {

                    Section("Carpetas") {

                        ForEach(
                            fileAccessService.folders
                        ) { folder in

                            Label(
                                folder.displayName,
                                systemImage:
                                    "folder"
                            )
                        }
                        .onDelete(
                            perform:
                                deleteFolders
                        )

                        Button {

                            showFolderPicker =
                                true

                        } label: {

                            Label(
                                "Agregar carpeta",
                                systemImage:
                                    "folder.badge.plus"
                            )
                        }
                    }

                    Section(
                        "Canciones (\(fileAccessService.songs.count))"
                    ) {

                        if fileAccessService.songs.isEmpty {

                            Text(
                                "Agrega una carpeta para ver tus canciones aquí"
                            )
                            .foregroundColor(
                                .secondary
                            )

                        } else {

                            ForEach(
                                fileAccessService.songs
                            ) { song in

                                songRow(song)
                            }
                        }
                    }
                }
                .listStyle(
                    .insetGrouped
                )

                if let currentSong =
                    audioEngine.currentSong {

                    PlayerBar(
                        audioEngine:
                            audioEngine,
                        song:
                            currentSong
                    )
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
            .navigationTitle(
                "Aurora Player"
            )
            .toolbar {

                ToolbarItem(
                    placement:
                        .navigationBarTrailing
                ) {

                    Button {

                        fileAccessService
                            .refreshAllFolders()

                    } label: {

                        Image(
                            systemName:
                                "arrow.clockwise"
                        )
                    }
                }
            }
            .sheet(
                isPresented:
                    $showFolderPicker
            ) {

                FolderPickerView(
                    isPresented:
                        $showFolderPicker
                ) { url in

                    fileAccessService
                        .addFolder(
                            url: url
                        )
                }
            }
        }
        .onChange(
            of:
                fileAccessService.songs
        ) { newSongs in

            guard
                !hasRestored,
                !newSongs.isEmpty
            else {
                return
            }

            audioEngine.restoreState(
                with:
                    newSongs
            )

            hasRestored = true
        }
    }

    private func songRow(
        _ song: Song
    ) -> some View {

        Button {

            audioEngine.play(
                song:
                    song,
                from:
                    fileAccessService.songs
            )

        } label: {

            HStack(spacing: 12) {

                Group {

                    if
                        let data =
                            song.artworkData,
                        let image =
                            UIImage(
                                data:
                                    data
                            )
                    {

                        Image(
                            uiImage:
                                image
                        )
                        .resizable()
                        .scaledToFill()

                    } else {

                        Image(
                            systemName:
                                iconFor(song)
                        )
                        .foregroundColor(
                            audioEngine.currentSong?.id ==
                                song.id
                            ? .accentColor
                            : .secondary
                        )
                    }
                }
                .frame(
                    width: 42,
                    height: 42
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 6
                    )
                )

                VStack(
                    alignment:
                        .leading,
                    spacing: 2
                ) {

                    Text(song.title)
                        .foregroundColor(
                            .primary
                        )
                        .lineLimit(1)

                    if !song.artist.isEmpty {

                        Text(song.artist)
                            .font(
                                .caption
                            )
                            .foregroundColor(
                                .secondary
                            )
                            .lineLimit(1)
                    }
                }

                Spacer()

                if
                    audioEngine.currentSong?.id ==
                    song.id
                {

                    Image(
                        systemName:
                            audioEngine.isPlaying
                            ? "speaker.wave.2.fill"
                            : "pause.fill"
                    )
                    .foregroundColor(
                        .accentColor
                    )
                }
            }
        }
        .buttonStyle(
            .plain
        )
    }

    private func iconFor(
        _ song: Song
    ) -> String {

        guard
            audioEngine.currentSong?.id ==
                song.id
        else {
            return "music.note"
        }

        return audioEngine.isPlaying
            ? "speaker.wave.2.fill"
            : "pause.fill"
    }

    private func deleteFolders(
        at offsets: IndexSet
    ) {

        for index in offsets {

            fileAccessService.removeFolder(
                fileAccessService.folders[index]
            )
        }
    }
}
```
