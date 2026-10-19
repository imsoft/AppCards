import SwiftUI

/// Colores semánticos: verde = bajó / ya la tienes, rojo = subió / te falta, ámbar = precio viejo.
enum Theme {
    static let positive = Color.green
    static let negative = Color.red
    /// Precio viejo: gris con ícono de reloj, para no competir con el ámbar de Pokémon.
    static let stale = Color(.systemGray)
    static let staleAfter: TimeInterval = 7 * 24 * 60 * 60

    /// Espaciado base para que las pantallas respiren.
    static let screenPadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 24
    static let cardRadius: CGFloat = 18

    static func isStale(_ date: Date?) -> Bool {
        guard let date else { return true }
        return Date().timeIntervalSince(date) > staleAfter
    }

    static func changeColor(_ change: Double?) -> Color {
        guard let change, change != 0 else { return .secondary }
        return change < 0 ? positive : negative
    }
}

extension Game {
    /// Color propio de cada juego, para chips, encabezados y gradientes.
    var color: Color {
        switch self {
        case .magic: Color(red: 0.50, green: 0.26, blue: 0.82)
        case .pokemon: Color(red: 0.96, green: 0.65, blue: 0.14)
        case .onePiece: Color(red: 0.05, green: 0.58, blue: 0.62)
        }
    }

    /// Texto legible sobre `color`: oscuro sobre ámbar, blanco sobre los demás (contraste AA).
    var onColor: Color {
        self == .pokemon ? Color(red: 0.22, green: 0.13, blue: 0.0) : .white
    }

    var gradient: LinearGradient {
        LinearGradient(colors: [color, color.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension Color {
    static let cardShadow = Color.black.opacity(0.25)
    static let vaultBlue = Color(red: 0.18, green: 0.36, blue: 0.92)
    static let vaultBlueDark = Color(red: 0.10, green: 0.20, blue: 0.60)
}

/// Color de texto dentro de una GradientCard (blanco, u oscuro sobre ámbar). Lo leen MoneyText, CurrencyTag y BigAmountView.
private struct GradientForegroundKey: EnvironmentKey {
    static let defaultValue: Color = .white
}

extension EnvironmentValues {
    var gradientForeground: Color {
        get { self[GradientForegroundKey.self] }
        set { self[GradientForegroundKey.self] = newValue }
    }
}

/// Tarjeta con gradiente y texto blanco para cifras importantes.
struct GradientCard<Content: View>: View {
    var colors: [Color] = [.vaultBlue, .vaultBlueDark]
    var foreground: Color = .white
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .foregroundStyle(foreground)
            .environment(\.gradientForeground, foreground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.screenPadding)
            .background(
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
            )
            .shadow(color: colors.first?.opacity(0.35) ?? .clear, radius: 12, y: 6)
    }
}

/// Sección con encabezado de ícono en color y fondo suave, con más aire que un GroupBox.
struct SectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    var tint: Color = .accentColor
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(title).font(.headline)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

struct GameChip: View {
    let game: Game

    var body: some View {
        Label(game.title, systemImage: game.systemImage)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(game.color.opacity(0.15), in: Capsule())
            .foregroundStyle(game.color)
    }
}

extension Color {
    /// "#RRGGBB" → Color. Vacío o inválido → nil.
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let rgb = UInt64(value, radix: 16) else { return nil }
        self.init(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
    }

    /// Texto legible encima de este color: oscuro sobre colores claros, blanco sobre oscuros.
    var readableForeground: Color {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return .white }
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance > 0.66 ? Color(red: 0.12, green: 0.1, blue: 0.08) : .white
    }
}

/// Colores para elegir en un deck.
enum DeckPalette {
    static let colors: [(name: String, hex: String)] = [
        ("Azul", "#2F5BEA"), ("Morado", "#7F43D1"), ("Rosa", "#E0457B"), ("Rojo", "#D93A3A"),
        ("Naranja", "#F07B1F"), ("Ámbar", "#F2A623"), ("Verde", "#1F9D55"), ("Turquesa", "#0E949E"),
        ("Grafito", "#4A5160"), ("Café", "#8A5A3C"),
    ]
}
