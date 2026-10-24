import SwiftUI
import UIKit

// ═══════════════════════════════════════════════════════════════════════════
// LIBRARY ROWS — filas de la biblioteca como VIEWS VALOR (Equatable).
//
// POR QUÉ EXISTE ESTE ARCHIVO (Prioridad 5, scroll a 60 fps):
// Las filas vivían como funciones `private func songRow(_:)` DENTRO de
// `ContentView`, que observa `AudioEngine` y `FileAccessService`. Cualquier
// @Published de esos objetos (play/pausa, cambio de ruta de audio, cambio de
// cola, progreso del escaneo…) re-evaluaba el body del padre y, con él, el de
// TODAS las filas visibles: con ~1.000 canciones eso son decenas de miles de
// diffs por evento, y en el A11 se ve como micro-tirones al scrollear mientras
// cambia el estado del motor.
//
// La solución tiene dos mitades:
//  1. La fila es una VIEW independiente que solo recibe VALORES (nunca el
//     engine). No observa nada: no hay forma de que un tick del motor la
//     despierte.
//  2. `==` compara SOLO lo que la fila PINTA. `.equatable()` hace que SwiftUI
//     corte el diff antes de evaluar el body cuando esos valores no cambiaron.
//
// COSTE: comparar 6-10 campos por fila visible (strings cortos, UUIDs) es
// órdenes de magnitud más barato que re-evaluar el body con su `VStack`, sus
// fuentes y su `auroraCard`. Y las filas NO visibles ni se crean (LazyVStack).
// ═══════════════════════════════════════════════════════════════════════════

// MARK: - Fila de canción de la biblioteca

struct LibrarySongRow: View, Equatable {
    let song: Song
    let isCurrent: Bool
    /// ✅ Solo se usa para las barras del indicador "suena ahora"; por eso NO
    /// entra en la igualdad cuando la fila no es la actual (ver `==`).
    let isPlaying: Bool
    let isLiked: Bool
    /// Copia (COW) de las playlists para el submenú "Añadir a playlist". Su
    /// CONTENIDO no participa en la igualdad: solo el recuento, que es lo que
    /// decide si el submenú existe.
    let playlists: [Playlist]

    let onPlay: () -> Void
    let onPlayNext: () -> Void
    let onAddToQueue: () -> Void
    let onToggleLike: () -> Void
    let onAddToPlaylist: (Playlist) -> Void

    /// ✅ Igualdad = "¿está igual lo que esta fila PINTA?".
    /// · Los closures se IGNORAN a propósito (no son Equatable y capturan el
    ///   engine por referencia: compararlos no aporta nada y rompería el diff).
    /// · `isPlaying` solo cuenta si la fila es la actual: el resto de filas no
    ///   pinta nada que dependa de ello, así que un play/pausa NO las invalida.
    /// · Se comparan los campos que el body lee (título, artista, álbum,
    ///   duración y hash de portada) en vez de `Song` entero: `Song` incluye
    ///   `lyrics` y `artworkData`, y compararlos por fila sería tirar frames.
    static func == (lhs: LibrarySongRow, rhs: LibrarySongRow) -> Bool {
        guard lhs.song.id == rhs.song.id,
              lhs.song.title == rhs.song.title,
              lhs.song.artist == rhs.song.artist,
              lhs.song.albumArtist == rhs.song.albumArtist,
              lhs.song.album == rhs.song.album,
              lhs.song.duration == rhs.song.duration,
              lhs.song.artworkHash == rhs.song.artworkHash,
              lhs.isCurrent == rhs.isCurrent,
              lhs.isLiked == rhs.isLiked,
              lhs.playlists.count == rhs.playlists.count
        else { return false }
        // El estado de reproducción solo importa en la fila que suena.
        return !lhs.isCurrent || lhs.isPlaying == rhs.isPlaying
    }

    var body: some View {
        HStack(spacing: 14) {
            Button {
                onPlay()
            } label: {
                HStack(spacing: 14) {
                    artworkView

                    VStack(alignment: .leading, spacing: 3) {
                        // ✅ Jerarquía: título 16 (igual que las filas de
                        // álbum/artista) para separarse del subtítulo de 12.
                        Text(song.displayName)
                            .font(M3ETypography.titleMediumEmphasized)
                            .foregroundStyle(isCurrent ? AppTheme.accent : .primary)
                            .lineLimit(1)

                        Text(song.displaySubtitle)
                            .font(M3ETypography.bodyMedium)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if !song.album.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "opticaldisc")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                                Text(song.album)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                    }

                    Spacer(minLength: 10)

                    // ✅ FIX LAYOUT SHIFT (Prioridad 3): el carril derecho tenía
                    // anchos distintos (barras de 10.5pt vs duración ~28pt), así
                    // que al empezar a sonar una canción el título cambiaba de
                    // ancho disponible y el texto se reflowaba: un salto de
                    // layout visible en pleno scroll. El carril ahora reserva el
                    // ancho de la duración y las barras se centran dentro.
                    Group {
                        if isCurrent {
                            // ✅ FASE 1: barras dibujadas por un único
                            // TimelineView + Canvas. Sin `repeatForever` (no
                            // hay transacción que rearmar en cada re-render de
                            // la lista) y sin pedir frames en pausa.
                            AuroraEqualizerBars(color: AppTheme.accent, isPlaying: isPlaying)
                        } else {
                            Text(Self.durationLabel(song.duration))
                                .font(M3ETypography.labelMedium)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(minWidth: 30, alignment: .trailing)
                }
            }
            // ✅ M3E: press feedback en la fila completa (rebote + apagado).
            // ✅ CONTEXTO: el apagado es SUAVE (0.9, no 0.75) porque la fila abre
            // un `.contextMenu` con pulsación larga. Con el velo profundo, el
            // sistema levantaba la preview sobre una fila ya casi gris y el gesto
            // se sentía roto; así la fila se "hunde" lo justo y la preview del
            // menú se ve con el contenido intacto. Mismo criterio que
            // `PlaylistSongRow` (coherencia entre listas con menú).
            .buttonStyle(PressableButtonStyle(scale: AuroraPressScale.row, pressedOpacity: 0.9))

            Button {
                Haptics.light()
                onToggleLike()
            } label: {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isLiked ? Color.red : (isCurrent ? AppTheme.accent : Color.secondary.opacity(0.7)))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle(scale: AuroraPressScale.chip))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            if isCurrent {
                // Estado current: velo accent + borde accent (radio .md = 18).
                RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                    .fill(AppTheme.accentGradient(opacity: 0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                            .strokeBorder(AppTheme.accent.opacity(0.2), lineWidth: 0.5)
                    )
            }
        }
        // ✅ AURORA DESIGN: superficie flat del sistema (cero blur por fila).
        .auroraCard(radius: AuroraRadius.md, style: .flat, withShadow: false)
        .contextMenu {
            Button {
                onPlay()
            } label: {
                Label(Localization.localized("context.playNow"), systemImage: "play.circle.fill")
            }

            Button {
                Haptics.light()
                onPlayNext()
            } label: {
                Label(Localization.localized("context.playNext"), systemImage: "text.line.first.and.arrowtriangle.forward")
            }

            Button {
                Haptics.light()
                onAddToQueue()
            } label: {
                Label(Localization.localized("actions.addToQueue"), systemImage: "text.badge.plus")
            }

            Button {
                Haptics.light()
                onToggleLike()
            } label: {
                Label(
                    isLiked ? Localization.localized("actions.unlike") : Localization.localized("actions.like"),
                    systemImage: isLiked ? "heart.slash" : "heart"
                )
            }

            if !playlists.isEmpty {
                Menu {
                    ForEach(playlists) { playlist in
                        Button {
                            Haptics.light()
                            onAddToPlaylist(playlist)
                        } label: {
                            Label(playlist.name, systemImage: "music.note.list")
                        }
                    }
                } label: {
                    Label(Localization.localized("context.addToPlaylist"), systemImage: "plus")
                }
            }
        }
    }

    // MARK: - Portada (miniatura por decodificación descendente)

    @ViewBuilder
    private var artworkView: some View {
        // ✅ PERF SCROLL: miniatura por ImageIO a 96px cacheada por hash+px
        // (la ruta completa decodificaba el JPEG de 768px en el main).
        if let thumbnail = song.rowThumbnail(maxPixel: 96) {
            Image(uiImage: thumbnail)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.accentGradient(opacity: 0.15))
                .frame(width: 48, height: 48)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppTheme.accentGradient(opacity: 0.6))
                }
        }
    }

    /// Duración de fila. Se llama UNA vez por evaluación del body (nunca por
    /// frame) y sustituye al `formatDuration` privado de ContentView, que ya no
    /// tiene filas propias.
    private static func durationLabel(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Fila de álbum

struct AlbumRow: View, Equatable {
    let album: Album

    static func == (lhs: AlbumRow, rhs: AlbumRow) -> Bool {
        lhs.album.id == rhs.album.id
            && lhs.album.name == rhs.album.name
            && lhs.album.artist == rhs.album.artist
            && lhs.album.songs.count == rhs.album.songs.count
            && lhs.album.songs.first?.artworkHash == rhs.album.songs.first?.artworkHash
    }

    var body: some View {
        HStack(spacing: 14) {
            artwork

            VStack(alignment: .leading, spacing: 3) {
                Text(album.name)
                    .font(M3ETypography.titleMediumEmphasized)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(album.artist)
                    .font(M3ETypography.bodyMedium)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(localizedSongCount(album.songs.count))
                    .font(M3ETypography.labelMedium)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
            // ✅ Sin flecha manual: NavigationLink ya dibuja su chevron.
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .auroraCard(radius: AuroraRadius.md, style: .flat, withShadow: false)
    }

    @ViewBuilder
    private var artwork: some View {
        if let image = rowThumbnail(album.songs) {
            Image(uiImage: image)
                .resizable().interpolation(.high).scaledToFill()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 52, height: 52)
                .overlay {
                    Image(systemName: "square.stack")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary.opacity(0.6))
                }
        }
    }
}

// MARK: - Fila de artista

struct ArtistRow: View, Equatable {
    let artist: Artist

    static func == (lhs: ArtistRow, rhs: ArtistRow) -> Bool {
        lhs.artist.id == rhs.artist.id
            && lhs.artist.name == rhs.artist.name
            && lhs.artist.songs.count == rhs.artist.songs.count
            && lhs.artist.songs.first?.artworkHash == rhs.artist.songs.first?.artworkHash
    }

    var body: some View {
        HStack(spacing: 14) {
            artwork

            VStack(alignment: .leading, spacing: 3) {
                Text(artist.name)
                    .font(M3ETypography.titleMediumEmphasized)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                // ✅ Solo canciones: `artist.albums` agrupa discos y es caro por fila.
                Text(localizedSongCount(artist.songs.count))
                    .font(M3ETypography.bodyMedium)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .auroraCard(radius: AuroraRadius.md, style: .flat, withShadow: false)
    }

    @ViewBuilder
    private var artwork: some View {
        if let image = rowThumbnail(artist.songs) {
            Image(uiImage: image)
                .resizable().interpolation(.high).scaledToFill()
                .frame(width: 52, height: 52)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 52, height: 52)
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary.opacity(0.6))
                }
        }
    }
}

// MARK: - Helper compartido

/// ✅ Miniatura de fila para álbum/artista por la MISMA ruta que la fila de
/// canción (`Song.rowThumbnail`: ImageIO decodifica el JPEG ya al tamaño pedido
/// y lo cachea por hash+px). Se elige la primera canción con arte, igual que
/// `Album.artwork`/`Artist.artwork`.
private func rowThumbnail(_ songs: [Song], maxPixel: Int = 104) -> UIImage? {
    songs.first(where: { $0.artworkData != nil || $0.artworkHash != nil })?
        .rowThumbnail(maxPixel: maxPixel)
}
