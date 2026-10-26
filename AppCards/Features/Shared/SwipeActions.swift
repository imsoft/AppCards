import SwiftUI
import UIKit

/// Una opción que aparece al deslizar una tarjeta hacia un lado.
struct SwipeAction: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    var tint: Color
    let action: () -> Void
}

/// Recuerda qué tarjeta tiene sus opciones abiertas, para cerrar las demás.
@Observable
final class SwipeGroup {
    var openID: AnyHashable?
}

private struct SwipeGroupKey: EnvironmentKey {
    static let defaultValue: SwipeGroup? = nil
}

extension EnvironmentValues {
    var swipeGroup: SwipeGroup? {
        get { self[SwipeGroupKey.self] }
        set { self[SwipeGroupKey.self] = newValue }
    }
}

extension View {
    /// Deslizar a la izquierda muestra `trailing`; a la derecha, `leading`. Funciona dentro de un ScrollView
    /// (a diferencia de `.swipeActions`, que solo sirve en List) y no estorba el scroll vertical.
    func swipeOptions(id: AnyHashable,
                      leading: [SwipeAction] = [],
                      trailing: [SwipeAction] = [],
                      cornerRadius: CGFloat = Theme.cardRadius,
                      spacing: CGFloat = 8,
                      contentBackground: Color? = nil) -> some View {
        modifier(SwipeOptionsModifier(id: id, leading: leading, trailing: trailing, cornerRadius: cornerRadius,
                                      spacing: spacing, contentBackground: contentBackground))
    }
}

private struct SwipeOptionsModifier: ViewModifier {
    let id: AnyHashable
    let leading: [SwipeAction]
    let trailing: [SwipeAction]
    let cornerRadius: CGFloat
    let spacing: CGFloat
    /// Fondo que se pone a la tarjeta mientras se desliza, si es transparente.
    let contentBackground: Color?

    @Environment(\.swipeGroup) private var group
    @State private var offset: CGFloat = 0
    @State private var restingOffset: CGFloat = 0

    private let buttonWidth: CGFloat = 74

    private func width(of actions: [SwipeAction]) -> CGFloat {
        actions.isEmpty ? 0 : CGFloat(actions.count) * buttonWidth + CGFloat(actions.count) * spacing
    }

    func body(content: Content) -> some View {
        content
            .background(offset != 0 ? contentBackground : nil)
            .overlay {
                // Mientras hay opciones abiertas, tocar la tarjeta las cierra en lugar de abrirla.
                if restingOffset != 0 {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { close() }
                }
            }
            .offset(x: offset)
            .background(alignment: .trailing) {
                buttons(trailing, revealed: -offset).opacity(offset < 0 ? 1 : 0)
            }
            .background(alignment: .leading) {
                buttons(leading, revealed: offset).opacity(offset > 0 ? 1 : 0)
            }
            .gesture(HorizontalPan(onChange: changed, onEnd: ended))
            .onChange(of: group?.openID) { _, newValue in
                if newValue != id, restingOffset != 0 { close() }
            }
            .accessibilityActions {
                ForEach(leading + trailing) { action in
                    Button(action.title, action: action.action)
                }
            }
    }

    private func buttons(_ actions: [SwipeAction], revealed: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(actions) { action in
                Button {
                    close()
                    action.action()
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: action.systemImage).font(.title3.weight(.semibold))
                        Text(action.title)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .frame(width: buttonWidth)
                    .frame(maxHeight: .infinity)
                    .background(action.tint.gradient, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("swipe-\(action.title)")
                .accessibilityHidden(revealed < 1)
            }
        }
        .padding(.horizontal, actions.isEmpty ? 0 : spacing / 2)
        // Los botones aparecen conforme se desliza.
        .scaleEffect(min(1, max(0.6, revealed / max(width(of: actions), 1))), anchor: .center)
    }

    private func changed(_ translation: CGFloat) {
        var proposed = restingOffset + translation
        let maxLeft = -width(of: trailing)
        let maxRight = width(of: leading)
        // Resistencia al pasarse del límite.
        if proposed < maxLeft { proposed = maxLeft + (proposed - maxLeft) / 3 }
        if proposed > maxRight { proposed = maxRight + (proposed - maxRight) / 3 }
        offset = proposed
    }

    private func ended(_ translation: CGFloat, _ velocity: CGFloat) {
        let projected = restingOffset + translation + velocity * 0.15
        let target: CGFloat
        if projected < -width(of: trailing) / 2, !trailing.isEmpty {
            target = -width(of: trailing)
        } else if projected > width(of: leading) / 2, !leading.isEmpty {
            target = width(of: leading)
        } else {
            target = 0
        }
        withAnimation(Motion.snappy) {
            offset = target
            restingOffset = target
        }
        if target != 0 {
            group?.openID = id
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func close() {
        withAnimation(Motion.snappy) {
            offset = 0
            restingOffset = 0
        }
        if group?.openID == id { group?.openID = nil }
    }
}

/// Arrastre que solo empieza si el movimiento es horizontal: el scroll vertical y el arrastre largo siguen funcionando.
private struct HorizontalPan: UIGestureRecognizerRepresentable {
    let onChange: (CGFloat) -> Void
    let onEnd: (CGFloat, CGFloat) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .changed:
            onChange(translation)
        case .ended:
            onEnd(translation, recognizer.velocity(in: recognizer.view).x)
        case .cancelled, .failed:
            onEnd(0, 0)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) * 1.2
        }
    }
}
