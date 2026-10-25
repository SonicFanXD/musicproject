import SwiftUI

// ══════════════════════════════════════════════════════════════════════════
// M3E SCREEN TRANSITION — navegación lateral estilo Android.
//
// `fullScreenCover` presenta con el slide-up de iOS, que delata al instante
// que la app no es Android. Este modificador sustituye esa presentación por
// un overlay a pantalla completa con la transición shared-axis X de M3E:
// la pantalla entra desde el borde derecho con un fundido corto y, al
// cerrarse, retrocede hacia ese mismo borde. No hay `repeatForever`: es una
// transición finita con el spring `spatialDefault` de `AuroraMotion`.
//
// El cierre se resuelve con `M3EDismiss`, un wrapper que usa el cierre del
// overlay cuando existe y cae al `dismiss` del sistema cuando la vista se
// presenta de la forma tradicional (p. ej. una hoja de archivos).
// ══════════════════════════════════════════════════════════════════════════

// MARK: - Acción de cierre del overlay

struct M3EScreenDismissAction {
    private let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    func callAsFunction() {
        action()
    }
}

private struct M3EScreenDismissKey: EnvironmentKey {
    static let defaultValue: M3EScreenDismissAction? = nil
}

extension EnvironmentValues {
    /// Cierre inyectado por `m3eScreen`. `nil` fuera de un overlay M3E.
    var m3eScreenDismiss: M3EScreenDismissAction? {
        get { self[M3EScreenDismissKey.self] }
        set { self[M3EScreenDismissKey.self] = newValue }
    }
}

/// Reemplaza a `@Environment(\.dismiss)` en las pantallas que pueden
/// presentarse con `m3eScreen`. La firma es idéntica (`dismiss()`), así que
/// los call sites no cambian y las hojas del sistema siguen funcionando.
@propertyWrapper
struct M3EDismiss: DynamicProperty {
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.m3eScreenDismiss) private var screenDismiss

    /// `@M3EDismiss` se usa sin argumentos; el init explícito evita que el
    /// compilador exija los parámetros de los `@Environment` internos.
    init() {}

    var wrappedValue: () -> Void {
        if let screenDismiss {
            return { screenDismiss() }
        }
        return { systemDismiss() }
    }
}

// MARK: - Estilos de transición

/// Shared Axis X para navegación lateral y Shared Axis Z para diálogos o
/// pantallas que nacen del centro (el antiguo sheet).
enum M3EScreenStyle {
    case sharedAxisX
    case sharedAxisZ
}

// MARK: - Transiciones shared-axis

private extension AnyTransition {
    /// Entrada shared-axis X: llega desde la derecha y se funde con el fondo.
    static var m3eSharedAxisXIn: AnyTransition {
        .move(edge: .trailing)
            .combined(with: .opacity)
            .animation(M3ESpring.spatialDefault)
    }

    /// Salida shared-axis X: retrocede hacia la derecha con el mismo spring.
    static var m3eSharedAxisXOut: AnyTransition {
        .move(edge: .trailing)
            .combined(with: .opacity)
            .animation(M3ESpring.spatialDefault)
    }

    /// Entrada shared-axis Z: escala desde el centro (diálogos/sheets).
    static var m3eSharedAxisZIn: AnyTransition {
        .scale(scale: 0.92, anchor: .center)
            .combined(with: .opacity)
            .animation(M3ESpring.spatialDefault)
    }

    /// Salida shared-axis Z: vuelve al centro mientras se desvanece.
    static var m3eSharedAxisZOut: AnyTransition {
        .scale(scale: 0.92, anchor: .center)
            .combined(with: .opacity)
            .animation(M3ESpring.spatialDefault)
    }
}

// MARK: - Contenedor de pantalla

struct M3EScreenContainer<Content: View>: View {
    private let onDismiss: () -> Void
    private let content: Content

    init(onDismiss: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.onDismiss = onDismiss
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.m3eScreenDismiss, M3EScreenDismissAction(onDismiss))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(M3EColor.surface.ignoresSafeArea())
            .contentShape(Rectangle())
    }
}

// MARK: - Modificadores de presentación

private struct M3EScreenModifier<Destination: View>: ViewModifier {
    @Binding var isPresented: Bool
    let style: M3EScreenStyle
    let destination: () -> Destination

    private var screenTransition: AnyTransition {
        switch style {
        case .sharedAxisX:
            return .asymmetric(insertion: .m3eSharedAxisXIn, removal: .m3eSharedAxisXOut)
        case .sharedAxisZ:
            return .asymmetric(insertion: .m3eSharedAxisZIn, removal: .m3eSharedAxisZOut)
        }
    }

    func body(content: Content) -> some View {
        ZStack {
            content
                .allowsHitTesting(!isPresented)
                .accessibilityHidden(isPresented)

            if isPresented {
                M3EScreenContainer(onDismiss: { isPresented = false }, content: destination)
                    .transition(screenTransition)
                    .zIndex(1000)
            }
        }
    }
}

private struct M3EScreenItemModifier<Item: Identifiable, Destination: View>: ViewModifier {
    @Binding var item: Item?
    let style: M3EScreenStyle
    let destination: (Item) -> Destination

    private var screenTransition: AnyTransition {
        switch style {
        case .sharedAxisX:
            return .asymmetric(insertion: .m3eSharedAxisXIn, removal: .m3eSharedAxisXOut)
        case .sharedAxisZ:
            return .asymmetric(insertion: .m3eSharedAxisZIn, removal: .m3eSharedAxisZOut)
        }
    }

    func body(content: Content) -> some View {
        ZStack {
            content
                .allowsHitTesting(item == nil)
                .accessibilityHidden(item != nil)

            if let item {
                M3EScreenContainer(
                    onDismiss: { self.item = nil },
                    content: { destination(item) }
                )
                .transition(screenTransition)
                .zIndex(1000)
            }
        }
    }
}

extension View {
    /// Presenta `destination` a pantalla completa con la transición lateral
    /// de M3E en lugar del slide-up de `fullScreenCover`.
    func m3eScreen<Destination: View>(
        isPresented: Binding<Bool>,
        style: M3EScreenStyle = .sharedAxisX,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        modifier(M3EScreenModifier(isPresented: isPresented, style: style, destination: destination))
    }

    /// Variante para contenido identificable (detalles de álbum, artista o
    /// playlist), equivalente a `fullScreenCover(item:)`.
    func m3eScreen<Item: Identifiable, Destination: View>(
        item: Binding<Item?>,
        style: M3EScreenStyle = .sharedAxisX,
        @ViewBuilder destination: @escaping (Item) -> Destination
    ) -> some View {
        modifier(M3EScreenItemModifier(item: item, style: style, destination: destination))
    }
}
