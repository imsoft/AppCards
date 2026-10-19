import SwiftUI
import UIKit

/// En iPhone, iOS trae apagado arrastrar filas de una lista (en iPad viene encendido).
/// Esta vista invisible busca la lista que la contiene y lo enciende.
struct ListDragEnabler: UIViewRepresentable {
    func makeUIView(context: Context) -> FinderView { FinderView() }
    func updateUIView(_ uiView: FinderView, context: Context) { uiView.enable() }

    final class FinderView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            enable()
        }

        func enable() {
            DispatchQueue.main.async { [weak self] in
                var view = self?.superview
                while let current = view {
                    if let collection = current as? UICollectionView {
                        collection.dragInteractionEnabled = true
                        return
                    }
                    if let table = current as? UITableView {
                        table.dragInteractionEnabled = true
                        return
                    }
                    view = current.superview
                }
            }
        }
    }
}

extension View {
    /// Permite arrastrar filas de esta lista también en iPhone.
    func enableListDragging() -> some View {
        background(ListDragEnabler().frame(width: 0, height: 0).allowsHitTesting(false))
    }
}
