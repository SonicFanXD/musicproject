import SwiftUI
import UIKit

// ═══════════════════════════════════════════════════════════════════════════
// DETAIL HERO ARTWORK — la carátula grande de Álbum/Artista como VIEW VALOR
// (Equatable), con una sola pasada de composición para la sombra.
//
// POR QUÉ EXISTE (Prioridad 4/5, tanda 4):
// 1. RENDIMIENTO. `AlbumDetailView`/`ArtistDetailView` observan `AudioEngine`
//    y publican `scrollOffset` (se actualiza cada 1pt de scroll). Eso hace que
//    el body del detalle se reevalúe decenas de veces por segundo y arrastre
//    el subtree de la portada: `Image` + `clipShape` + `overlay` de borde +
//    `shadow`. La sombra de una imagen clipada por un shape es una pasada
//    offscreen; repetirla 60 veces por segundo en un A11 con una imagen de
//    200/170pt es exactamente el tipo de trabajo que produce el micro-tirón al
//    empezar a scrollear. Aquí el subtree se corta con `.equatable()`: en
//    scroll los valores no cambian, así que SwiftUI ni lo reevalúa.
// 2. UNA SOLA PASADA DE SOMBRA. `.compositingGroup()` se aplica ANTES del
//    `.shadow()`, de modo que imagen + borde se rasterizan juntos y la sombra
//    se calcula UNA vez sobre el resultado (mismo look, la mitad de trabajo).
//    Sin él, `Image` y el `overlay` del borde generan cada uno su propia capa
//    y la sombra se aplica dos veces.
//
// DELIBERADAMENTE NO usa `matchedGeometryEffect`: la portada no viaja entre
// pantallas, solo entra con un spring al aparecer el hero.
// ═══════════════════════════════════════════════════════════════════════════

struct DetailHeroArtwork: View, Equatable {
    enum Kind: Equatable {
        case album
        case artist
    }

    let kind: Kind
    /// Huella de CONTENIDO de la portada (mismo hash que usa la caché de
    /// miniaturas). Se compara esto y no la `UIImage`: `UIImage` no tiene una
    /// igualdad por contenido útil y comparar punteros daría falsos iguales.
    let identity: String
    /// Ya viene reducida por `AppTheme.thumbnail` (caché por hash+tamaño):
    /// aquí no se decodifica nada, solo se pinta.
    let image: UIImage?
    let size: CGFloat
    let accentPrimary: Color
    let accentSecondary: Color
    let shadowColor: Color
    /// Driver de la animación de entrada del hero (`appearAnimation`).
    let isVisible: Bool

    /// ✅ Igualdad = "¿pinta lo mismo?". Los colores del acento entran porque
    /// tiñen borde y sombra del placeholder; si el usuario cambia de tema con
    /// la vista abierta, la portada debe seguir al acento.
    static func == (lhs: DetailHeroArtwork, rhs: DetailHeroArtwork) -> Bool {
        lhs.kind == rhs.kind
            && lhs.identity == rhs.identity
            && lhs.size == rhs.size
            && lhs.isVisible == rhs.isVisible
            && lhs.accentPrimary == rhs.accentPrimary
            && lhs.accentSecondary == rhs.accentSecondary
            && lhs.shadowColor == rhs.shadowColor
    }

    var body: some View {
        content
            // ✅ M3E: la portada entra con el spring estándar (antes: spring
            // suelto 0.5/0.8 en álbum y otro igual en artista). Una sola curva
            // para todo el hero = el bloque se siente como una pieza.
            .scaleEffect(isVisible ? 1 : (kind == .album ? 0.9 : 0.85))
            .opacity(isVisible ? 1 : 0)
            .animation(AuroraMotion.spatialDefault, value: isVisible)
    }

    // MARK: - Contenido

    @ViewBuilder
    private var content: some View {
        if let image = image {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(shape)
                .overlay { border }
                // ✅ Una sola capa: imagen + borde se rasterizan juntos y la
                // sombra se calcula una vez sobre el compuesto.
                .compositingGroup()
                .shadow(color: shadowColor.opacity(imageShadowOpacity), radius: imageShadowRadius, x: 0, y: 10)
        } else {
            placeholder
                .shadow(color: shadowColor.opacity(0.25), radius: placeholderShadowRadius, x: 0, y: placeholderShadowY)
        }
    }

    private var placeholder: some View {
        ZStack {
            shape
                .fill(
                    LinearGradient(
                        colors: [accentPrimary.opacity(placeholderPrimaryOpacity),
                                 accentSecondary.opacity(placeholderSecondaryOpacity),
                                 Color.secondary.opacity(0.22)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)

            Image(systemName: kind == .album ? "square.stack" : "person.fill")
                .font(.system(size: kind == .album ? 54 : 56, weight: .light))
                .foregroundStyle(kind == .album ? Color.secondary.opacity(0.7) : Color.white.opacity(0.9))
        }
    }

    // MARK: - Forma y borde (única diferencia entre álbum y artista)

    private var shape: AnyShape {
        switch kind {
        case .album:
            return AnyShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        case .artist:
            return AnyShape(Circle())
        }
    }

    /// ✅ FIX CI: `AnyShape` NO conforma `InsettableShape`, así que no expone
    /// `strokeBorder`. Cada rama dibuja el borde con su shape CONCRETO (que sí
    /// lo conforma) y el `@ViewBuilder` unifica el tipo de retorno. Se mantiene
    /// el borde HACIA DENTRO (strokeBorder, no stroke): con stroke, el 3.5pt del
    /// avatar del artista se saldría media línea fuera de la máscara circular y
    /// contra el fondo.
    @ViewBuilder
    private var border: some View {
        switch kind {
        case .album:
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.35), .white.opacity(0.08), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        case .artist:
            // ✅ Borde premium con gradiente (mismo gesto que NowPlayingView).
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.45), accentPrimary.opacity(0.7),
                                 accentSecondary.opacity(0.55), .white.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3.5
                )
        }
    }

    // Sombra de la portada real (valores originales de cada hero).
    private var imageShadowOpacity: Double {
        kind == .album ? 0.4 : 0.3
    }

    private var imageShadowRadius: CGFloat {
        kind == .album ? 16 : 22
    }

    // Sombra del placeholder (más contenida: no hay imagen que separar).
    private var placeholderShadowRadius: CGFloat {
        kind == .album ? 14 : 18
    }

    private var placeholderShadowY: CGFloat {
        kind == .album ? 8 : 10
    }

    private var placeholderPrimaryOpacity: Double {
        kind == .album ? 0.35 : 0.45
    }

    private var placeholderSecondaryOpacity: Double {
        kind == .album ? 0.2 : 0.25
    }
}
