import SwiftUI
import SwiftData

/// Acción para seleccionar un elemento cuando la pantalla está en dos columnas (iPad).
struct SplitSelectAction {
    let select: (AnyHashable) -> Void
    let selected: AnyHashable?
}

private struct SplitSelectKey: EnvironmentKey {
    static let defaultValue: SplitSelectAction? = nil
}

extension EnvironmentValues {
    var splitSelect: SplitSelectAction? {
        get { self[SplitSelectKey.self] }
        set { self[SplitSelectKey.self] = newValue }
    }
}

/// En iPhone navega (empuja el detalle). En iPad, dentro de `AdaptiveSplitView`, selecciona y el detalle aparece a la derecha.
struct ItemLink<Value: Hashable, Label: View>: View {
    let value: Value
    @ViewBuilder let label: () -> Label
    @Environment(\.splitSelect) private var splitSelect

    init(value: Value, @ViewBuilder label: @escaping () -> Label) {
        self.value = value
        self.label = label
    }

    var body: some View {
        if let splitSelect {
            Button { splitSelect.select(AnyHashable(value)) } label: {
                label()
                    .overlay {
                        if splitSelect.selected == AnyHashable(value) {
                            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                                .strokeBorder(Color.accentColor, lineWidth: 3)
                                .padding(-4)
                        }
                    }
            }
            .accessibilityAddTraits(splitSelect.selected == AnyHashable(value) ? .isSelected : [])
        } else {
            NavigationLink(value: value, label: label)
        }
    }
}

/// Lista + detalle. En pantalla compacta (iPhone, o iPad en ventana angosta) es un `NavigationStack` normal.
/// En pantalla amplia (iPad) usa dos columnas: la lista a la izquierda y el detalle a la derecha.
struct AdaptiveSplitView<Value: PersistentModel, Primary: View, Detail: View, Empty: View>: View {
    @ViewBuilder let primary: () -> Primary
    let detail: (Value) -> Detail
    @ViewBuilder let empty: () -> Empty

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selection: Value?

    init(for: Value.Type,
         @ViewBuilder detail: @escaping (Value) -> Detail,
         @ViewBuilder empty: @escaping () -> Empty,
         @ViewBuilder primary: @escaping () -> Primary) {
        self.primary = primary
        self.detail = detail
        self.empty = empty
    }

    var body: some View {
        if sizeClass == .regular {
            NavigationSplitView {
                primary()
                    .environment(\.splitSelect, SplitSelectAction(
                        select: { value in
                            withAnimation(Motion.snappy) { selection = value.base as? Value }
                        },
                        selected: selection.map(AnyHashable.init)
                    ))
                    .navigationSplitViewColumnWidth(min: 360, ideal: 440, max: 560)
            } detail: {
                NavigationStack {
                    if let selection, selection.modelContext != nil, !selection.isDeleted {
                        detail(selection)
                            .id(selection.persistentModelID)
                    } else {
                        empty()
                    }
                }
            }
            .navigationSplitViewStyle(.balanced)
        } else {
            NavigationStack {
                primary()
                    .navigationDestination(for: Value.self) { detail($0) }
            }
        }
    }
}

/// Columna de detalle vacía en iPad.
struct SplitPlaceholder: View {
    let title: String
    let message: String
    var color: Color = .vaultBlue

    var body: some View {
        EmptyStateView(title: title, message: message, color: color)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ScreenBackground(color: color))
    }
}
