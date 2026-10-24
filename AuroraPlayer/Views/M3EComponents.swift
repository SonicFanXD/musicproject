import SwiftUI

// ══════════════════════════════════════════════════════════════════════════
// M3E COMPONENTS — vocabulario visual Material 3 Expressive de Aurora.
//
// · Superficies SÓLIDAS (cero `.ultraThinMaterial` / blurs en cards y barras).
// · Elevación TONAL: borde de 1 pt con el acento al 10 %, sin sombras.
// · Formas de píldora para acciones y radios de 24/32 para contenedores.
// · Todo el feedback de presión es un spring FINITO (`AuroraMotion`): aquí no
//   se usa `repeatForever` en ningún sitio.
// ══════════════════════════════════════════════════════════════════════════

// MARK: - Superficie tonal

/// ✅ FASE 2 (remake): superficie M3E real. Base SÓLIDA del sistema + velo
/// tonal del acento al 8 % + borde de 1.5 pt al 20 %. No es translúcida: el
/// velo se compone sobre la base opaca, así el contenido que scrollea por
/// debajo no se transparenta (lo que delataba el "look iOS").
struct M3ETonalSurface: View {
    var cornerRadius: CGFloat = 24
    var tint: Color = AppTheme.accent
    var base: Color = Color(UIColor.secondarySystemBackground)
    var showsBorder: Bool = true

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(base)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tint.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        tint.opacity(showsBorder ? 0.2 : 0),
                        lineWidth: showsBorder ? 1.5 : 0
                    )
            )
    }
}

// MARK: - Card

/// Contenedor base M3E: superficie teñida, radio grande y borde tonal.
struct M3ECard<Content: View>: View {
    private let cornerRadius: CGFloat
    private let padding: CGFloat
    private let surface: Color
    private let tint: Color
    private let showsBorder: Bool
    private let content: Content

    init(
        cornerRadius: CGFloat = 24,
        padding: CGFloat = 16,
        surface: Color = Color(UIColor.secondarySystemBackground),
        tint: Color = AppTheme.accent,
        showsBorder: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.surface = surface
        self.tint = tint
        self.showsBorder = showsBorder
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                // ✅ FASE 2: base sólida + velo tonal al 8 % + borde al 20 %.
                M3ETonalSurface(
                    cornerRadius: cornerRadius,
                    tint: tint,
                    base: surface,
                    showsBorder: showsBorder
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Squish de presión (M3E)

/// ✅ FASE 2: al pulsar, la forma se deforma (ancho +4 %, alto -6 %) con
/// `spatialFast`; al mantener, vuelve con el mismo spring. Es el "squish" de
/// M3E sin `repeatForever` y sin cambiar el layout (transform GPU).
struct M3ESquishButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(
                x: configuration.isPressed ? 1.04 : 1.0,
                y: configuration.isPressed ? 0.94 : 1.0
            )
            .animation(AuroraMotion.spatialFast, value: configuration.isPressed)
    }
}

// MARK: - Filled button

/// Botón de acción principal: relleno sólido de acento y forma de píldora.
struct M3EFilledButton<Label: View>: View {
    private let tint: Color
    private let foreground: Color
    private let horizontalPadding: CGFloat
    private let verticalPadding: CGFloat
    private let action: () -> Void
    private let label: Label

    init(
        tint: Color = AppTheme.accent,
        foreground: Color = .white,
        horizontalPadding: CGFloat = 22,
        verticalPadding: CGFloat = 12,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.tint = tint
        self.foreground = foreground
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            label
                .font(M3ETypography.labelLargeEmphasized)
                .foregroundStyle(foreground)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background(Capsule(style: .continuous).fill(tint))
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(M3ESquishButtonStyle())
    }
}

// MARK: - Tonal button

/// Botón secundario: relleno tonal (acento al 15 %) y texto en acento.
struct M3ETonalButton<Label: View>: View {
    private let tint: Color
    private let horizontalPadding: CGFloat
    private let verticalPadding: CGFloat
    private let action: () -> Void
    private let label: Label

    init(
        tint: Color = AppTheme.accent,
        horizontalPadding: CGFloat = 18,
        verticalPadding: CGFloat = 10,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.tint = tint
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            label
                .font(M3ETypography.labelLargeEmphasized)
                .foregroundStyle(tint)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background(Capsule(style: .continuous).fill(tint.opacity(0.15)))
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(M3ESquishButtonStyle())
    }
}

// MARK: - Filter chip

/// Chip de filtro con morphing de forma (radio 12 ↔ cápsula) y spring finito.
/// No usa `matchedGeometryEffect`: cada chip interpola SU propia forma, así el
/// layout no se mueve y no hay namespace compartido en el ScrollView.
struct M3EFilterChip: View {
    private let title: String
    private let icon: String?
    private let isSelected: Bool
    private let tint: Color
    private let action: () -> Void

    init(
        title: String,
        icon: String? = nil,
        isSelected: Bool,
        tint: Color = AppTheme.accent,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isSelected = isSelected
        self.tint = tint
        self.action = action
    }

    // ✅ FASE 2: radio 14 (reposo) → 20 (seleccionado), interpolado por
    // `animatableData` con `spatialDefault`.
    private var shapeRadius: CGFloat {
        isSelected ? 20 : 14
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title)
                    .font(M3ETypography.labelLargeEmphasized)
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? tint : Color.secondary)
            // ✅ FASE 2: el COLOR es un efecto (sin rebote) → effectsDefault.
            .animation(AuroraMotion.effectsDefault, value: isSelected)
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(
                AuroraMorphChipShape(cornerRadius: shapeRadius)
                    .fill(isSelected ? tint.opacity(0.2) : Color(UIColor.secondarySystemBackground))
                    .animation(AuroraMotion.spatialDefault, value: isSelected)
            )
            .overlay(
                AuroraMorphChipShape(cornerRadius: shapeRadius)
                    .strokeBorder(
                        isSelected ? tint.opacity(0.5) : Color.clear,
                        lineWidth: 1
                    )
                    .animation(AuroraMotion.spatialDefault, value: isSelected)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(PressableButtonStyle(scale: 0.96, pressedOpacity: 0.9))
        .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : [])
    }
}

// MARK: - Navigation bar

/// Barra de navegación M3E: fondo sólido, título con la escala enfática y un
/// slot trailing para acciones. Sustituye a los headers con material.
struct M3ENavigationBar<Leading: View, Trailing: View>: View {
    private let title: String
    private let subtitle: String?
    private let showsDivider: Bool
    private let leading: Leading
    private let trailing: Trailing

    init(
        title: String,
        subtitle: String? = nil,
        showsDivider: Bool = true,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.showsDivider = showsDivider
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            leading

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(M3ETypography.headlineSmallEmphasized)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(M3ETypography.labelLargeEmphasized)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            trailing
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.systemBackground))
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 1)
            }
        }
    }
}

extension M3ENavigationBar where Leading == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        showsDivider: Bool = true,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            showsDivider: showsDivider,
            leading: { EmptyView() },
            trailing: trailing
        )
    }
}

extension M3ENavigationBar where Leading == EmptyView, Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, showsDivider: Bool = true) {
        self.init(
            title: title,
            subtitle: subtitle,
            showsDivider: showsDivider,
            leading: { EmptyView() },
            trailing: { EmptyView() }
        )
    }
}
