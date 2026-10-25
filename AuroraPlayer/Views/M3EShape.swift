import SwiftUI

// ══════════════════════════════════════════════════════════════════════════
// M3E SHAPES — familias de forma Material 3.
//
// Las cinco familias usan el radio oficial. La variante `cut` queda preparada
// para una fase posterior; hoy toda la app usa `.rounded`, que es la forma
// base de M3E.
// ══════════════════════════════════════════════════════════════════════════

enum M3EShapeFamily {
    case extraSmall
    case small
    case medium
    case large
    case extraLarge

    var radius: CGFloat {
        switch self {
        case .extraSmall: return 4
        case .small: return 8
        case .medium: return 12
        case .large: return 16
        case .extraLarge: return 28
        }
    }
}

enum M3EShapeStyle {
    case rounded
    case cut
}

/// Forma M3 con radio de familia. Conforma `InsettableShape` para que
/// `strokeBorder` siga funcionando en bordes de 1–1.5 pt.
struct M3EShape: InsettableShape {
    let family: M3EShapeFamily
    var style: M3EShapeStyle = .rounded
    /// Permite respetar un radio configurable (p. ej. el ajuste de esquinas
    /// del artwork) sin dejar de usar la familia M3.
    var cornerRadius: CGFloat?
    var insetAmount: CGFloat = 0

    init(
        family: M3EShapeFamily,
        style: M3EShapeStyle = .rounded,
        cornerRadius: CGFloat? = nil
    ) {
        self.family = family
        self.style = style
        self.cornerRadius = cornerRadius
        self.insetAmount = 0
    }

    func path(in rect: CGRect) -> Path {
        let box = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let radius = min(cornerRadius ?? family.radius, min(box.width, box.height) / 2)

        switch style {
        case .rounded:
            return Path(roundedRect: box, cornerRadius: max(0, radius), style: .continuous)
        case .cut:
            var path = Path()
            path.move(to: CGPoint(x: box.minX + radius, y: box.minY))
            path.addLine(to: CGPoint(x: box.maxX - radius, y: box.minY))
            path.addLine(to: CGPoint(x: box.maxX, y: box.minY + radius))
            path.addLine(to: CGPoint(x: box.maxX, y: box.maxY - radius))
            path.addLine(to: CGPoint(x: box.maxX - radius, y: box.maxY))
            path.addLine(to: CGPoint(x: box.minX + radius, y: box.maxY))
            path.addLine(to: CGPoint(x: box.minX, y: box.maxY - radius))
            path.addLine(to: CGPoint(x: box.minX, y: box.minY + radius))
            path.closeSubpath()
            return path
        }
    }

    func inset(by amount: CGFloat) -> Self {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}
