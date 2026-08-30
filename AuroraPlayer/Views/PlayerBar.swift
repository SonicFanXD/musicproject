```swift
import SwiftUI

struct PlayerBar: View {

    @ObservedObject
    var audioEngine: AudioEngine

    let song: Song

    var body: some View {

        VStack(spacing: 8) {

            ProgressView(
                value:
                    audioEngine.currentTime,
                total:
                    max(
                        audioEngine.duration,
                        1
                    )
            )
            .tint(
                .accentColor
            )

            HStack(spacing: 12) {

                artwork

                VStack(
                    alignment:
                        .leading,
                    spacing: 2
                ) {

                    Text(song.title)
                        .font(
                            .subheadline
                        )
                        .bold()
                        .lineLimit(1)

                    Text(
                        song.artist.isEmpty
                        ? audioEngine.currentRouteName
                        : song.artist
                    )
                    .font(
                        .caption2
                    )
                    .foregroundColor(
                        .secondary
                    )
                    .lineLimit(1)
                }

                Spacer(
                    minLength: 4
                )

                HStack(spacing: 18) {

                    Button {

                        audioEngine
                            .playPrevious()

                    } label: {

                        Image(
                            systemName:
                                "backward.fill"
                        )
                        .font(
                            .system(
                                size: 20
                            )
                        )
                    }

                    Button {

                        if audioEngine.isPlaying {

                            audioEngine.pause()

                        } else {

                            audioEngine.resume()
                        }

                    } label: {

                        Image(
                            systemName:
                                audioEngine.isPlaying
                                ? "pause.circle.fill"
                                : "play.circle.fill"
                        )
                        .font(
                            .system(
                                size: 40
                            )
                        )
                    }

                    Button {

                        audioEngine
                            .playNext()

                    } label: {

                        Image(
                            systemName:
                                "forward.fill"
                        )
                        .font(
                            .system(
                                size: 20
                            )
                        )
                    }
                }
            }
        }
        .padding()
        .background(
            .thinMaterial
        )
    }

    @ViewBuilder
    private var artwork: some View {

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
            .frame(
                width: 44,
                height: 44
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 7
                )
            )

        } else {

            Image(
                systemName:
                    "music.note"
            )
            .font(
                .system(
                    size: 22
                )
            )
            .frame(
                width: 44,
                height: 44
            )
            .background(
                Color.secondary
                    .opacity(0.15)
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 7
                )
            )
        }
    }
}
```
