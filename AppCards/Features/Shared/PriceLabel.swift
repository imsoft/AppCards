import SwiftUI

/// Etiqueta de moneda: MXN en azul Vault (tu moneda), las extranjeras en gris oscuro. Sin verde ni rojo, que ya significan subió/bajó.
struct CurrencyTag: View {
    let code: String
    var size: Size = .regular
    var onGradient = false

    enum Size { case small, regular, large }
    @Environment(\.gradientForeground) private var gradientForeground

    static func color(for code: String) -> Color {
        switch code {
        case "MXN": .vaultBlue
        default: Color(red: 0.33, green: 0.36, blue: 0.42)
        }
    }

    var body: some View {
        Text(code)
            .font(font)
            .padding(.horizontal, size == .small ? 4 : 6)
            .padding(.vertical, size == .small ? 1 : 2)
            .background(onGradient ? gradientForeground.opacity(0.22) : Self.color(for: code).opacity(0.15), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .foregroundStyle(onGradient ? gradientForeground : Self.color(for: code))
    }

    private var font: Font {
        switch size {
        case .small: .system(size: 9, weight: .bold, design: .rounded)
        case .regular: .system(size: 11, weight: .bold, design: .rounded)
        case .large: .system(size: 14, weight: .bold, design: .rounded)
        }
    }
}

/// Número con su etiqueta de moneda al lado.
struct MoneyText: View {
    let amount: Double
    let currency: String
    var font: Font = .headline
    var tagSize: CurrencyTag.Size = .regular
    var onGradient = false
    var color: Color? = nil
    @Environment(\.gradientForeground) private var gradientForeground

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(MoneyFormatter.number(amount, currency: currency))
                .font(font)
                .monospacedDigit()
                .foregroundStyle(color ?? (onGradient ? gradientForeground : .primary))
                .animatedNumber(amount)
            CurrencyTag(code: currency, size: tagSize, onGradient: onGradient)
        }
    }
}

/// Precio en la moneda elegida en grande y el original en pequeño debajo (si es distinta).
struct PriceLabel: View {
    let amount: Double
    let currency: String
    var style: Style = .regular
    var updatedAt: Date? = nil
    var alignment: HorizontalAlignment = .trailing
    /// Mostrar abajo el precio en su moneda original (USD/EUR).
    var showsOriginal = true

    @Environment(AppModel.self) private var model

    enum Style {
        case compact, regular, large
    }

    var body: some View {
        let isStale = updatedAt != nil && Theme.isStale(updatedAt)
        VStack(alignment: alignment, spacing: 2) {
            HStack(spacing: 4) {
                if isStale {
                    Image(systemName: "clock").font(.caption2).foregroundStyle(Theme.stale)
                        .accessibilityLabel("Precio con más de una semana")
                }
                MoneyText(amount: primary.amount, currency: primary.currency, font: primaryFont,
                          tagSize: style == .large ? .large : (style == .compact ? .small : .regular),
                          color: isStale ? Theme.stale : nil)
            }
            if showsOriginal, let secondary {
                MoneyText(amount: secondary.amount, currency: secondary.currency,
                          font: style == .large ? .subheadline : .caption2, tagSize: .small, color: .secondary)
            }
        }
    }

    private var primaryFont: Font {
        switch style {
        case .compact: .subheadline.weight(.semibold)
        case .regular: .headline
        case .large: .system(.largeTitle, design: .rounded).weight(.bold)
        }
    }


    private var primary: (amount: Double, currency: String) {
        if let converted = model.converted(amount, from: currency) {
            return (converted, model.displayCurrency)
        }
        return (amount, currency)
    }

    private var secondary: (amount: Double, currency: String)? {
        guard currency != model.displayCurrency, model.converted(amount, from: currency) != nil else { return nil }
        return (amount, currency)
    }
}

/// Cifra grande con el cambio respecto a un valor anterior, en verde o rojo.
struct BigAmountView: View {
    let title: String
    let amount: Double
    let currency: String
    var previous: Double? = nil
    var previousLabel: String = "vs. ayer"
    var footnote: String? = nil
    /// En tarjetas con gradiente el texto hereda el color de la tarjeta y el cambio va en una píldora.
    var onGradient = false
    @Environment(\.gradientForeground) private var gradientForeground

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.medium)).opacity(onGradient ? 0.85 : 1).foregroundStyle(onGradient ? gradientForeground : .secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(MoneyFormatter.number(amount, currency: currency))
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(onGradient ? gradientForeground : .primary)
                    .animatedNumber(amount)
                CurrencyTag(code: currency, size: .large, onGradient: onGradient)
            }
            HStack(spacing: 10) {
                if let change = PriceTracking.change(from: previous, to: amount), let previous {
                    let diff = amount - previous
                    let color = diff > 0 ? Theme.negative : (diff < 0 ? Theme.positive : Color.secondary)
                    Label(String(format: "%@ (%+.1f%%)", MoneyFormatter.string(diff, currency: currency), change * 100),
                          systemImage: diff >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(onGradient ? gradientForeground.opacity(0.22) : color.opacity(0.12), in: Capsule())
                        .foregroundStyle(onGradient ? gradientForeground : color)
                    Text(previousLabel).font(.footnote).opacity(onGradient ? 0.85 : 1).foregroundStyle(onGradient ? gradientForeground : .secondary)
                }
                if let footnote {
                    Text(footnote).font(.footnote).opacity(onGradient ? 0.85 : 1).foregroundStyle(onGradient ? gradientForeground : .secondary)
                }
            }
        }
    }
}

/// "En tienda ≈ $X MXN · +25% ($Y de margen)". Respeta el ajuste de mostrar/ocultar.
struct StorePriceLine: View {
    let amount: Double
    let currency: String
    var onGradient = false
    var compact = false
    @Environment(AppModel.self) private var model
    @Environment(\.gradientForeground) private var gradientForeground

    var body: some View {
        if model.showStorePrice, model.storeMarkupPercent > 0 {
            let base = model.converted(amount, from: currency) ?? amount
            let code = model.converted(amount, from: currency) == nil ? currency : model.displayCurrency
            let percent = model.storeMarkupPercent
            let tint: Color = onGradient ? gradientForeground : .secondary
            HStack(spacing: 5) {
                Image(systemName: "storefront")
                    .font(.caption2.weight(.semibold))
                Text("En tienda ≈").font(.caption)
                MoneyText(amount: StoreMarkup.storePrice(base, percent: percent), currency: code,
                          font: .caption.weight(.semibold), tagSize: .small, onGradient: onGradient, color: tint)
                if !compact {
                    Text("+\(Int(percent))% · \(MoneyFormatter.number(StoreMarkup.markupAmount(base, percent: percent), currency: code)) de margen")
                        .font(.caption2)
                        .opacity(0.85)
                }
            }
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityElement(children: .combine)
        }
    }
}
