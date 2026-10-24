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

// MARK: - Transición shared-axis X

private extension AnyTransition {
    /// Entra desde la derecha y retrocede hacia la derecha (atrás). El
    /// desplazamiento se combina con opacidad para que el cambio no sea un
    /// corte seco incluso si el frame tarda en asentarse.
    static var m3eSharedAxisX: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        )
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
    let destination: () -> Destination

    func body(content: Content) -> some View {
        ZStack {
            content
                .allowsHitTesting(!isPresented)
                .accessibilityHidden(isPresented)

            if isPresented {
                M3EScreenContainer(onDismiss: { isPresented = false }, content: destination)
                    .transition(.m3eSharedAxisX)
                    .zIndex(1000)
            }
        }
        .animation(AuroraMotion.spatialDefault, value: isPresented)
    }
}

private struct M3EScreenItemModifier<Item: Identifiable, Destination: View>: ViewModifier {
    @Binding var item: Item?
    let destination: (Item) -> Destination

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
                .transition(.m3eSharedAxisX)
                .zIndex(1000)
            }
        }
        .animation(AuroraMotion.spatialDefault, value: item?.id)
    }
}

extension View {
    /// Presenta `destination` a pantalla completa con la transición lateral
    /// de M3E en lugar del slide-up de `fullScreenCover`.
    func m3eScreen<Destination: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        modifier(M3EScreenModifier(isPresented: isPresented, destination: destination))
    }

    /// Variante para contenido identificable (detalles de álbum, artista o
    /// playlist), equivalente a `fullScreenCover(item:)`.
    func m3eScreen<Item: Identifiable, Destination: View>(
        item: Binding<Item?>,
        @ViewBuilder destination: @escaping (Item) -> Destination
    ) -> some View {
        modifier(M3EScreenItemModifier(item: item, destination: destination))
    }
}
