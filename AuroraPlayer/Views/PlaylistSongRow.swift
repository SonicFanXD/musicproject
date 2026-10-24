import SwiftUI
import UIKit

// ═══════════════════════════════════════════════════════════════════════════
// PLAYLIST SONG ROW — la fila de canción de una lista de reproducción como
// VIEW VALOR (Equatable).
//
// POR QUÉ EXISTE (Prioridad 5, tanda 4):
// `playlistSongRow(_:index:)` era una función DENTRO de `PlaylistDetailView`,
// que observa `AudioEngine` y `FileAccessService`. Esa vista construye su lista
// con un `VStack` (no un `LazyVStack`), así que SwiftUI evalúa TODAS las filas
// del body: con una lista de 200 canciones cualquier `@Published` del motor
// (play/pausa, cambio de pista, cola, ruta de audio) reevaluaba 200 subárboles
// completos, cada uno con su ecualizador, sus fuentes y su fondo. Es el tirón
// clásico al scrollear mientras suena música.
//
// Con la fila aislada:
//  · La fila NO observa nada: recibe valores y closures.
//  · `==` compara SOLO lo que la fila pinta (ver abajo) y `.equatable()` corta
//    el diff antes de evaluar el body en las filas que no cambiaron.
//
// NOTA: la lista de esta vista sigue siendo un `VStack` a propósito (la
// reproducimos tal cual en esta tanda): cambiarla a `LazyVStack` es una decisión
// de producto aparte, porque altera el scroll del hero y el comportamiento de
// `scrollTo`. La optimización de aquí no depende de eso.
// ═══════════════════════════════════════════════════════════════════════════

struct PlaylistSongRow: View, Equatable {
    let song: Song
    let index: Int
    let isCurrent: Bool
    /// ✅ Solo pinta las barras del indicador: no entra en la igualdad si la
    /// fila no es la actual (ver `==`).
    let isPlaying: Bool
    let isLiked: Bool

    let onPlay: () -> Void
    let onPlayNext: () -> Void
    let onAddToQueue: () -> Void
    let onToggleLike: () -> Void
    let onRemove: () -> Void

    /// ✅ Igualdad = "¿está igual lo que esta fila PINTA?".
    /// · Los closures se ignoran (no son comparables y capturan el motor).
    /// · `isPlaying` solo cuenta en la fila activa: un play/pausa NO invalida
    ///   las otras 199 filas.
    /// · Se comparan campos sueltos en vez de `Song` entero: `Song` incluye
    ///   `lyrics` y `artworkData`, comparar eso por fila sería tirar frames.
    static func == (lhs: PlaylistSongRow, rhs: PlaylistSongRow) -> Bool {
        guard lhs.song.id == rhs.song.id,
              lhs.song.title == rhs.song.title,
              lhs.song.artist == rhs.song.artist,
              lhs.song.albumArtist == rhs.song.albumArtist,
              lhs.song.album == rhs.song.album,
              lhs.song.duration == rhs.song.duration,
              lhs.index == rhs.index,
              lhs.isCurrent == rhs.isCurrent,
              lhs.isLiked == rhs.isLiked
        else { return false }
        return !lhs.isCurrent || lhs.isPlaying == rhs.isPlaying
    }

    var body: some View {
        HStack(spacing: 14) {
            Button {
                Haptics.light()
                onPlay()
            } label: {
                HStack(spacing: 14) {
                    // Número o ecualizador animado (componente compartido con
                    // las filas de álbum/artista: mismo aspecto y misma gestión
                    // de batería — el latido se retira en pausa).
                    if isCurrent {
                        EqualizerBars(color: AppTheme.accent, isPlaying: isPlaying)
                            .frame(width: 26)
                    } else {
                        Text("\(index + 1)")
                            .font(M3ETypography.labelLargeNumeric)
                            .foregroundStyle(Color.secondary.opacity(0.6))
                            .frame(width: 26)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(song.title)
                            .font(M3ETypography.titleMediumEmphasized)
                            .foregroundStyle(isCurrent ? AppTheme.accent : .primary)
                            .lineLimit(1)

                        Text(song.displaySubtitle)
                            .font(M3ETypography.bodyMedium)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    // ✅ FIX LAYOUT SHIFT: el carril derecho reserva el ancho de
                    // la duración; el ecualizador se centra dentro, así el título
                    // no cambia de ancho al empezar a sonar la fila.
                    Group {
                        if isCurrent {
                            EqualizerBars(color: AppTheme.accent, isPlaying: isPlaying)
                        } else {
                            Text(Self.durationLabel(song.duration))
                                .font(M3ETypography.timeDisplayCompact)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(minWidth: 30, alignment: .trailing)
                }
            }
            // ✅ M3E + CONTEXTO: rebote rápido al toque, con apenas un velo.
            // La opacidad baja a 0.9 (no 0.7) porque esta fila abre un
            // `.contextMenu` con pulsación larga: con el apagado profundo el
            // sistema levantaba la preview sobre una fila ya casi gris y el
            // gesto se sentía "roto".
            .buttonStyle(PressableButtonStyle(scale: AuroraPressScale.row, pressedOpacity: 0.9))

            Button {
                Haptics.light()
                onRemove()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.red.opacity(0.7))
                    .frame(width: 44, height: 44) // Área táctil amplia
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle(scale: AuroraPressScale.chip))
            .accessibilityLabel(Localization.localized("queue.remove"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    isCurrent
                        ? AnyShapeStyle(AppTheme.accentGradient(opacity: 0.1))
                        : AnyShapeStyle(Color.secondary.opacity(0.05))
                )
        }
        .overlay {
            if isCurrent {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(AppTheme.accent.opacity(0.25), lineWidth: 1)
            }
        }
        .contextMenu {
            Button {
                Haptics.light()
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
                    Localization.localized(isLiked ? "actions.unlike" : "actions.like"),
                    systemImage: isLiked ? "heart.slash" : "heart"
                )
            }
            Button {
                Haptics.light()
                onRemove()
            } label: {
                Label(Localization.localized("playlists.removeSong"), systemImage: "minus.circle")
            }
        }
    }

    /// Duración de fila. Se evalúa UNA vez por render del body (nunca por frame).
    private static func durationLabel(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
