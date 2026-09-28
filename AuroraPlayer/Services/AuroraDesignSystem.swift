import SwiftUI
import UIKit

// ✅ AURORA DESIGN: sistema de diseño extraído de la identidad visual de
// NowPlayingView. Es el CONTRATO visual de la app: tokens (radio, spacing,
// tamaños, sombras, presión) + superficies + badges + chips + headers.
// Regla de oro de rendimiento en A11: "glass en containers y features,
// flat en filas" — cada .ultraThinMaterial es un pase offscreen por frame.
//
// ─────────────────────────────────────────────────────────────────────────
// REGLAS DE ACENTO (PARTE 2.7 del contrato):
//  · Acento de DOS colores SIEMPRE para fondos/bordes: AuroraDesignSystem
//    .textSafeAccentGradient() / AppTheme.accentGradient(opacity:).
//    NUNCA AppTheme.accent.opacity(X) a secas para rellenos grandes.
//  · Texto o icono BLANCO encima del acento: usar textSafeAccentGradient()
//    (ancla el brillo del secundario al del primario si difieren mucho).
//  · Acento sólido SOLO para iconos pequeños: AppTheme.accent directo.
//  · "Acento desde carátula" activo: leer ThemeManager.shared
//    .artworkAccentColor / .artworkSecondaryColor. NUNCA extraer localmente.
//
// REGLAS DE TIPOGRAFÍA (PARTE 2.8 del contrato):
//  · Título de hero (26-30pt): .system(size:, weight: .bold, design: .rounded)
//  · Título de sección (18-20pt): .system(size:, weight: .bold, design: .rounded)
//  · Título de fila (15-16pt): .system(size:, weight: .semibold, design: .rounded)
//  · Subtítulo de fila (12-13pt): .system(size:) SIN .rounded (contraste)
//  · Datos numéricos (duración, kbps, FPS): .monospacedDigit()
//  · Chips y pills (10-13pt): .system(size:, weight: .semibold, design: .rounded)
// ─────────────────────────────────────────────────────────────────────────

// MARK: - Radii

enum AuroraRadius {
    static let xs: CGFloat = 10    // icon badges pequeños, chips compactos
    static let sm: CGFloat = 14    // filas compactas, sub-cards
    static let md: CGFloat = 18    // filas estándar, chips grandes
    static let lg: CGFloat = 22    // cards estándar, contenedores
    static let xl: CGFloat = 28    // headers premium, cards destacadas
    static let xxl: CGFloat = 34   // containers full-screen (NowPlaying, PlayerBar)
}

// MARK: - Spacing

enum AuroraSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let sectionGap: CGFloat = 22  // separación entre secciones
}

// MARK: - Icon sizes (jerarquía)

enum AuroraIconSize {
    static let inline: CGFloat = 16    // iconos dentro de texto
    static let small: CGFloat = 30     // row badge
    static let medium: CGFloat = 34    // section header badge
    static let large: CGFloat = 44     // action button icon container
    static let hero: CGFloat = 88      // header card circle
}

// MARK: - Shadows
// ✅ AURORA DESIGN: SIEMPRE una sola sombra. Doble sombra = 2 pasadas
// offscreen por frame en vistas que se re-renderizan (scroll, hero) —
// prohibido en el A11. Cada nivel define color, radio y offset juntos.

enum AuroraShadow {
    static let softColor = Color.black.opacity(0.06)
    static let mediumColor = Color.black.opacity(0.18)
    static let strongColor = Color.black.opacity(0.35)

    static let softRadius: CGFloat = 10
    static let mediumRadius: CGFloat = 20
    static let strongRadius: CGFloat = 24

    static let softY: CGFloat = 4
    static let mediumY: CGFloat = 8
    static let strongY: CGFloat = 12
}

// MARK: - Press scales (uniformar feedback)

enum AuroraPressScale {
    static let row: CGFloat = 0.98     // filas, cards
    static let chip: CGFloat = 0.95    // chips, tabs
    static let button: CGFloat = 0.92  // botones grandes con texto
    static let circle: CGFloat = 0.88  // botones circulares pequeños
}

// MARK: - Superficies

/// ✅ AURORA DESIGN: superficies del sistema. `.glass` SOLO sobre fondo con
/// artwork/blur (containers de nivel 1: NowPlaying, PlayerBar, heroes) y un
/// máximo de 3-4 simultáneos visibles. `.flat` para listas largas (biblioteca,
/// playlists, queue, settings, logs): cero recomposición de blur por fila.
/// `.opaque` no se elige a mano: `auroraCard` cae a él automáticamente con
/// "Reducir transparencia" activo.
enum AuroraSurface {
    case glass      // .ultraThinMaterial — SOLO sobre fondo con artwork/blur
    case flat       // secondarySystemBackground.opacity(0.6) — listas largas, perf
    case opaque     // secondarySystemBackground — reduceTransparency
}

// MARK: - Gradiente text-safe (regla 2.7)

enum AuroraDesignSystem {
    /// ✅ AURORA DESIGN: gradiente de dos colores con el BRILLO del secundario
    /// anclado al del primario cuando difieren mucho (>0.3). Para texto o
    /// icono blanco encima del acento: conserva el tono de dos colores reales
    /// sin sacrificar legibilidad. Es la semántica ya validada en
    /// NowPlayingView/LogsView, centralizada aquí para todo el sistema.
    static func textSafeGradient(
        primary: Color,
        secondary: Color,
        primaryOpacity: Double = 1,
        secondaryOpacity: Double = 1
    ) -> LinearGradient {
        var secondaryStop = secondary
        var h1: CGFloat = 0, s1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 1
        var h2: CGFloat = 0, s2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 1
        if UIColor(primary).getHue(&h1, saturation: &s1, brightness: &b1, alpha: &a1),
           UIColor(secondary).getHue(&h2, saturation: &s2, brightness: &b2, alpha: &a2),
           abs(b1 - b2) > 0.3 {
            secondaryStop = Color(UIColor(hue: h2, saturation: s2, brightness: b1, alpha: a2))
        }
        return LinearGradient(
            colors: [primary.opacity(primaryOpacity), secondaryStop.opacity(secondaryOpacity)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// ✅ AURORA DESIGN: variante para acento MANUAL (el patrón de LogsView).
    /// Existen DOS wrappers y no uno porque la FUENTE del par es distinta,
    /// no la lógica:
    ///  · `textSafeAccentGradient()` — par resuelto del modo "acento desde
    ///    carátula" (NowPlaying, PlayerBar): carátula si el modo está activo,
    ///    acento manual si no.
    ///  · `textSafeGradientManual(primary:)` — acento fijo por parámetro
    ///    (LogsView): el secundario de carátula SOLO entra si el modo está
    ///    activo (si no, sería el de una canción anterior, hue equivocado)
    ///    y cae a `primary.opacity(0.85)`.
    /// Ambos aplican el mismo anclaje de brillo (umbral 0.3) de arriba.
    static func textSafeGradientManual(
        primary: Color,
        primaryOpacity: Double = 1,
        secondaryOpacity: Double = 1
    ) -> LinearGradient {
        let manager = ThemeManager.shared
        let candidate = manager.accentFromArtwork ? manager.artworkSecondaryColor : nil
        let secondary = candidate ?? primary.opacity(0.85)
        return textSafeGradient(
            primary: primary,
            secondary: secondary,
            primaryOpacity: primaryOpacity,
            secondaryOpacity: secondaryOpacity
        )
    }

    /// ✅ AURORA DESIGN: el acento de la app (par de la carátula si el modo
    /// "acento desde portada" está activo, acento manual si no) en versión
    /// text-safe. Respeta la regla: el secundario solo entra cuando procede,
    /// nunca el de una canción anterior con el modo apagado.
    static func textSafeAccentGradient(
        primaryOpacity: Double = 1,
        secondaryOpacity: Double = 1
    ) -> LinearGradient {
        let manager = ThemeManager.shared
        let primary = (manager.accentFromArtwork ? manager.artworkAccentColor : nil) ?? AppTheme.accent
        let secondary = (manager.accentFromArtwork ? manager.artworkSecondaryColor : nil) ?? primary.opacity(0.85)
        return textSafeGradient(
            primary: primary,
            secondary: secondary,
            primaryOpacity: primaryOpacity,
            secondaryOpacity: secondaryOpacity
        )
    }
}

// MARK: - Card estándar

private struct AuroraCardModifier: ViewModifier {
    let radius: CGFloat
    let style: AuroraSurface
    let withBorder: Bool
    let withShadow: Bool
    // ✅ Misma clave que LyricsView: un único @AppStorage por modifier, sin
    // tocar claves existentes. Al cambiar el ajuste, todas las cards recaen.
    @AppStorage("com.aurora.reduceTransparency") private var reduceTransparency = false

    func body(content: Content) -> some View {
        let effectiveStyle: AuroraSurface = (reduceTransparency && style == .glass) ? .opaque : style
        return content
            .background(surfaceBackground(effectiveStyle))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                withBorder
                    ? RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.12), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                    : nil
            )
            .shadow(
                color: withShadow ? AuroraShadow.softColor : .clear,
                radius: withShadow ? AuroraShadow.softRadius : 0,
                x: 0,
                y: withShadow ? AuroraShadow.softY : 0
            )
    }

    @ViewBuilder
    private func surfaceBackground(_ effective: AuroraSurface) -> some View {
        switch effective {
        case .glass:
            Rectangle().fill(.ultraThinMaterial)
        case .flat:
            Rectangle().fill(Color(UIColor.secondarySystemBackground).opacity(0.6))
        case .opaque:
            Rectangle().fill(Color(UIColor.secondarySystemBackground))
        }
    }
}

extension View {
    /// ✅ AURORA DESIGN: card estándar del sistema. `style` decide la superficie
    /// (glass solo en containers/features; flat en filas por rendimiento en
    /// A11) y `radius` la escala de AuroraRadius. Con "Reducir transparencia"
    /// cualquier `.glass` cae a `.opaque` automáticamente. Sombra SIEMPRE
    /// single (soft): la fuerte queda reservada a containers de nivel 1.
    func auroraCard(
        radius: CGFloat = AuroraRadius.lg,
        style: AuroraSurface = .flat,
        withBorder: Bool = true,
        withShadow: Bool = true
    ) -> some View {
        modifier(AuroraCardModifier(radius: radius, style: style, withBorder: withBorder, withShadow: withShadow))
    }
}

// MARK: - Icon badges

enum AuroraIconShape {
    case circle
    case roundedRect
}

private struct AuroraIconBadgeModifier: ViewModifier {
    let size: CGFloat
    let color: Color
    let shape: AuroraIconShape
    let iconSize: CGFloat?

    func body(content: Content) -> some View {
        content
            // ✅ AURORA DESIGN: el gradiente interno SIEMPRE dos paradas del
            // MISMO tono (0.22 → 0.08), como los section headers de Settings y
            // los feature buttons de NowPlaying. Nunca color sólido a secas.
            .font(.system(size: iconSize ?? size * 0.52, weight: .medium))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(
                Group {
                    switch shape {
                    case .circle:
                        Circle().fill(
                            LinearGradient(
                                colors: [color.opacity(0.22), color.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    case .roundedRect:
                        RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous).fill(
                            LinearGradient(
                                colors: [color.opacity(0.22), color.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    }
                }
            )
    }
}

extension View {
    /// ✅ AURORA DESIGN: badge de icono con el lenguaje del sistema. Aplicar
    /// sobre el `Image(systemName:)`. Jerarquía de tamaños:
    /// section header → .medium + roundedRect · row icon → .small +
    /// roundedRect · header card → .hero + circle · feature button →
    /// .large + roundedRect.
    func auroraIconBadge(
        size: CGFloat = AuroraIconSize.medium,
        color: Color,
        shape: AuroraIconShape = .roundedRect,
        iconSize: CGFloat? = nil
    ) -> some View {
        modifier(AuroraIconBadgeModifier(size: size, color: color, shape: shape, iconSize: iconSize))
    }
}

// MARK: - Chips y botones

private struct AuroraChipModifier: ViewModifier {
    let isSelected: Bool
    let accent: Color

    func body(content: Content) -> some View {
        content
            // ✅ AURORA DESIGN: chip del sistema (tabs, presets, filtros).
            // Seleccionado = gradiente text-safe + texto blanco; sin
            // seleccionar = superficie flat neutra. Mismo vocabulario que
            // los filtros de LogsView y las cápsulas de NowPlaying.
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(isSelected ? Color.white : Color.secondary)
            .padding(.horizontal, AuroraSpacing.lg)
            .padding(.vertical, AuroraSpacing.sm)
            .background(
                Capsule().fill(
                    isSelected
                        ? AnyShapeStyle(AuroraDesignSystem.textSafeGradient(primary: accent, secondary: accent.opacity(0.7)))
                        : AnyShapeStyle(Color.secondary.opacity(0.12))
                )
            )
    }
}

private struct AuroraPrimaryActionModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            // ✅ AURORA DESIGN: acción primaria = relleno de acento completo
            // text-safe + texto blanco. Consume la regla 2.7 centralizada.
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white)
            .padding(.horizontal, AuroraSpacing.xl)
            .padding(.vertical, AuroraSpacing.md)
            .background(
                Capsule().fill(AnyShapeStyle(AuroraDesignSystem.textSafeAccentGradient()))
            )
    }
}

private struct AuroraSecondaryActionModifier: ViewModifier {
    let accent: Color
    @AppStorage("com.aurora.reduceTransparency") private var reduceTransparency = false

    func body(content: Content) -> some View {
        content
            // ✅ AURORA DESIGN: acción secundaria = vidrio + velo de acento +
            // borde de acento (el patrón de los botones de acción de los
            // detalles). Con "Reducir transparencia" cae a superficie opaca
            // del sistema, conservando velo y borde.
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(accent)
            .padding(.horizontal, AuroraSpacing.xl)
            .padding(.vertical, AuroraSpacing.md)
            .background(
                Group {
                    if reduceTransparency {
                        Capsule().fill(Color(UIColor.secondarySystemBackground))
                    } else {
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(Capsule().fill(accent.opacity(0.12)))
                    }
                }
            )
            .overlay(
                Capsule().strokeBorder(accent.opacity(0.35), lineWidth: 1)
            )
    }
}

extension View {
    /// ✅ AURORA DESIGN: chip seleccionable (tabs, presets, filtros).
    func auroraChip(isSelected: Bool, accent: Color) -> some View {
        modifier(AuroraChipModifier(isSelected: isSelected, accent: accent))
    }

    /// ✅ AURORA DESIGN: botón primario (relleno de acento + texto blanco).
    func auroraPrimaryAction() -> some View {
        modifier(AuroraPrimaryActionModifier())
    }

    /// ✅ AURORA DESIGN: botón secundario (glass + velo de acento + borde).
    func auroraSecondaryAction(accent: Color) -> some View {
        modifier(AuroraSecondaryActionModifier(accent: accent))
    }
}

// MARK: - Chip informacional

/// ✅ AURORA DESIGN: chip INFORMACIONAL del sistema: NO es seleccionable y no
/// tiene estado. Icono opcional + dato sobre la superficie de vidrio del sistema
/// (reactiva a "Reducir transparencia"). Cierra el hueco que quedaba entre
/// `auroraChip` (seleccionable: tabs, presets, filtros) y los datos de cabecera
/// de las vistas de detalle (recuento, duración, kHz, bit-perfect), que hasta
/// ahora iban con HStack + nativeGlassCapsule + font/padding a mano en cada
/// sitio. Un solo color para icono y texto: `.secondary` para un dato normal y
/// el acento de la vista para uno destacado (el pill de bit-perfect).
struct AuroraInfoChip: View {
    let icon: String?
    let text: String
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
            }
            // ✅ 13 semibold: el chip es dato de cabecera, no letra pequeña
            // (contrato tipográfico: chips y pills 10-13pt).
            Text(text)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, AuroraSpacing.md)
        .padding(.vertical, 6)
        // ✅ fixedSize: el chip NUNCA se parte ni se corta con guiones — mantiene
        // su tamaño intrínseco y el FlowLayout lo acomoda entero en la fila
        // siguiente si no cabe.
        .fixedSize()
        .nativeGlassCapsule()
    }
}

// MARK: - Section header

/// ✅ AURORA DESIGN: header de sección con icon-badge + título (el lenguaje
/// de Settings y AudioQualityDetailView, generalizado). Es una VIEW, no un
/// modifier: crea contenido propio.
struct AuroraSectionHeader: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: AuroraSpacing.md) {
            Image(systemName: icon)
                .auroraIconBadge(size: AuroraIconSize.medium, color: color, shape: .roundedRect)
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color.primary)
            Spacer()
        }
    }
}

// MARK: - Header de sheet

/// ✅ AURORA DESIGN: header de sheet con chevron.down a la izquierda, título
/// centrado y slot trailing opcional — el patrón de NowPlayingView (fila de
/// 44pt, sin .toolbar) generalizado a los modales con cierre claro.
struct AuroraSheetHeader: View {
    let title: String
    let onClose: () -> Void
    var trailing: AnyView? = nil

    var body: some View {
        HStack {
            Button {
                onClose()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text(Localization.localized("design.close")))

            Spacer()

            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .lineLimit(1)

            Spacer()

            // Slot trailing: mantiene el eje óptico del título centrado
            // aunque no haya botón a la derecha (marco fantasma de 44pt).
            Group {
                if let trailing {
                    AnyView(trailing)
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }
            }
        }
        .frame(height: 44)
        .padding(.horizontal, AuroraSpacing.sm)
    }
}
