import SwiftUI

// MARK: - Fondo con manchas de color

/// Fondo de pantalla: gris del sistema con dos manchas difuminadas del color dado arriba.
struct ScreenBackground: View {
    var color: Color = .vaultBlue

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
            GeometryReader { geo in
                Circle()
                    .fill(color.opacity(0.22))
                    .frame(width: geo.size.width * 0.9)
                    .blur(radius: 70)
                    .offset(x: -geo.size.width * 0.35, y: -geo.size.width * 0.45)
                Circle()
                    .fill(color.opacity(0.14))
                    .frame(width: geo.size.width * 0.7)
                    .blur(radius: 60)
                    .offset(x: geo.size.width * 0.55, y: -geo.size.width * 0.2)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Selector de juego con chips

struct GameSelector: View {
    @Binding var selection: Game?
    var allowsAll = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if allowsAll {
                    chip(title: "Todo", symbol: "square.grid.2x2.fill", color: .vaultBlue, onColor: .white, isSelected: selection == nil) { selection = nil }
                }
                ForEach(Game.allCases) { game in
                    chip(title: game.title, symbol: game.systemImage, color: game.color, onColor: game.onColor, isSelected: selection == game) { selection = game }
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.vertical, 6)
        }
    }

    private func chip(title: String, symbol: String, color: Color, onColor: Color, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.snappy(duration: 0.25)) { action() } }) {
            Label(title, systemImage: symbol)
                .font((allowsAll ? Font.footnote : Font.subheadline).weight(.semibold))
                .padding(.horizontal, allowsAll ? 10 : 12)
                .padding(.vertical, 9)
                .background {
                    if isSelected {
                        Capsule().fill(LinearGradient(colors: [color, color.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .shadow(color: color.opacity(0.45), radius: 8, y: 4)
                    } else {
                        Capsule().fill(Color(.secondarySystemGroupedBackground))
                    }
                }
                .foregroundStyle(isSelected ? onColor : color)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint("Filtra por \(title)")
    }
}

/// Selector de un solo juego (sin "Todo").
struct SingleGameSelector: View {
    @Binding var game: Game

    var body: some View {
        GameSelector(selection: Binding(get: { game }, set: { if let value = $0 { game = value } }))
    }
}

// MARK: - Ilustración de cartas en abanico

struct FannedCards: View {
    var color: Color = .vaultBlue
    var size: CGFloat = 120
    @State private var open = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ForEach(Array([-14.0, 0.0, 14.0].enumerated()), id: \.offset) { index, angle in
                RoundedRectangle(cornerRadius: size * 0.09, style: .continuous)
                    .fill(LinearGradient(colors: [color.opacity(index == 1 ? 1 : 0.75), color.opacity(index == 1 ? 0.7 : 0.45)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: size * 0.62, height: size * 0.88)
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: size * 0.05)
                            .fill(.white.opacity(0.35))
                            .frame(width: size * 0.46, height: size * 0.34)
                            .padding(.top, size * 0.08)
                    }
                    .shadow(color: color.opacity(0.35), radius: 10, y: 6)
                    .rotationEffect(.degrees(open || reduceMotion ? angle : 0), anchor: .bottom)
                    .offset(y: index == 1 ? -size * 0.04 : 0)
                    .zIndex(index == 1 ? 1 : 0)
            }
        }
        .frame(width: size, height: size)
        .onAppear { withAnimation(Motion.spring.delay(0.15)) { open = true } }
    }
}

/// Estado vacío con personalidad: abanico de cartas, título y texto.
struct EmptyStateView: View {
    let title: String
    let message: String
    var color: Color = .vaultBlue

    var body: some View {
        VStack(spacing: 18) {
            FannedCards(color: color)
            Text(title).font(.system(.title3, design: .rounded).weight(.bold))
            Text(message)
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Carta que se inclina al arrastrar

struct TiltEffect: ViewModifier {
    @State private var drag: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(Double(drag.height) / -10), axis: (x: 1, y: 0, z: 0))
            .rotation3DEffect(.degrees(Double(drag.width) / 10), axis: (x: 0, y: 1, z: 0))
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in drag = CGSize(width: max(min(value.translation.width, 80), -80), height: max(min(value.translation.height, 80), -80)) }
                    .onEnded { _ in withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { drag = .zero } }
            )
    }
}

extension View {
    func tiltOnDrag() -> some View { modifier(TiltEffect()) }
}

// MARK: - Encabezado grande con tipografía redondeada

struct ScreenHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(.largeTitle, design: .rounded).weight(.bold))
            if let subtitle {
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.screenPadding)
        .padding(.top, 4)
    }
}
