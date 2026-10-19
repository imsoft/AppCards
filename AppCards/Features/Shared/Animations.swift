import SwiftUI

/// Animaciones con propósito. Todas respetan "Reducir movimiento".
enum Motion {
    static let snappy = Animation.snappy(duration: 0.3)
    static let spring = Animation.spring(response: 0.45, dampingFraction: 0.75)
    static let gentle = Animation.easeOut(duration: 0.35)
}

/// Aparece con fundido y leve escala, en cascada según el índice.
struct StaggeredAppear: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .scaleEffect(shown || reduceMotion ? 1 : 0.92)
            .offset(y: shown || reduceMotion ? 0 : 12)
            .onAppear {
                guard !shown else { return }
                let delay = min(Double(index % 12) * 0.04, 0.4)
                withAnimation(Motion.spring.delay(delay)) { shown = true }
            }
    }
}

/// Flota al entrar: desde abajo con leve escala.
struct FloatIn: ViewModifier {
    var delay: Double = 0
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .scaleEffect(shown || reduceMotion ? 1 : 0.94)
            .offset(y: shown || reduceMotion ? 0 : 18)
            .onAppear {
                guard !shown else { return }
                withAnimation(Motion.spring.delay(delay)) { shown = true }
            }
    }
}

/// Botón o tarjeta que se encoge un poco al presionar.
struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension View {
    func staggeredAppear(index: Int) -> some View { modifier(StaggeredAppear(index: index)) }
    func floatIn(delay: Double = 0) -> some View { modifier(FloatIn(delay: delay)) }

    /// Los números cambian con transición de dígitos en vez de saltar.
    func animatedNumber<V: Equatable>(_ value: V) -> some View {
        contentTransition(.numericText())
            .animation(Motion.snappy, value: value)
    }
}

/// Tamaño de las hojas: en iPad siempre completas; en iPhone completas salvo las cortas.
struct SheetSize: ViewModifier {
    var shortOnPhone: Bool
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        if sizeClass == .regular {
            content
                .presentationDetents([.large])
                .presentationSizing(.form)
        } else {
            content.presentationDetents(shortOnPhone ? [.medium, .large] : [.large])
        }
    }
}

extension View {
    /// Hoja que abre completa (iPad siempre; iPhone salvo `shortOnPhone`).
    func sheetSize(shortOnPhone: Bool = false) -> some View { modifier(SheetSize(shortOnPhone: shortOnPhone)) }
}
