import SwiftUI
import SwiftData

/// Cuántas copias tienes (por clave canónica) y qué cartas están en deseos. Se usa para insignias en la cuadrícula.
struct OwnershipIndex {
    var ownedByKey: [String: Int] = [:]
    var wishlistCardIDs: Set<String> = []

    init(collection: [CollectionItem], wishlist: [WishlistItem]) {
        ownedByKey = CollectionMath.owned(collection.map(\.line))
        wishlistCardIDs = Set(wishlist.map(\.cardID))
    }

    func owned(_ card: CardSummary) -> Int { ownedByKey[card.canonicalKey] ?? 0 }
    func isWished(_ card: CardSummary) -> Bool { wishlistCardIDs.contains(card.id) }
}

struct CardGridTile: View {
    let card: CardSummary
    var owned: Int = 0
    var wished: Bool = false
    var subtitle: String? = nil
    var price: Double? = nil
    var priceCurrency: String? = nil
    var updatedAt: Date? = nil
    /// Si se pasa, muestra un botón +1 visible sobre la carta.
    var onQuickAdd: (() -> Void)? = nil
    @State private var taps = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                // Mismo marco de carta para todas: así los precios quedan a la misma altura en cada fila.
                Color.clear
                    .aspectRatio(0.716, contentMode: .fit)
                    .overlay {
                        AsyncImage(url: ImageQuality.best(card.thumbnailURL ?? card.imageURL, size: .grid)) { phase in
                            if let image = phase.image {
                                image.resizable().interpolation(.high).antialiased(true).scaledToFit()
                            } else {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(.quaternary)
                                    .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: card.game.color.opacity(0.35), radius: 8, y: 4)

                VStack {
                    Spacer()
                    HStack(alignment: .bottom) {
                        if let price = price ?? card.price, let currency = priceCurrency ?? card.priceCurrency {
                            PriceSticker(amount: price, currency: currency, stale: updatedAt != nil && Theme.isStale(updatedAt))
                        }
                        Spacer()
                        if let onQuickAdd {
                            Button {
                                taps += 1
                                onQuickAdd()
                            } label: {
                                Image(systemName: "plus")
                                    .font(.subheadline.weight(.bold))
                                    .frame(width: 32, height: 32)
                                    .background(.regularMaterial, in: Circle())
                                    .foregroundStyle(Theme.positive)
                                    .symbolEffect(.bounce, value: taps)
                            }
                            .buttonStyle(PressableStyle())
                            .accessibilityLabel("Agregar una a la colección")
                        }
                    }
                }
                .padding(8)

                HStack(spacing: 4) {
                    if wished {
                        Image(systemName: "heart.fill")
                            .font(.caption2.weight(.bold))
                            .padding(5)
                            .background(.regularMaterial, in: Circle())
                            .foregroundStyle(Theme.negative)
                    }
                    if owned > 0 {
                        Text("×\(owned)")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Theme.positive, in: Capsule())
                            .foregroundStyle(.white)
                            .animatedNumber(owned)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(6)
                .animation(Motion.spring, value: owned > 0)
                .animation(Motion.spring, value: wished)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(card.name).font(.system(.subheadline, design: .rounded).weight(.bold)).lineLimit(2)
                Text(subtitle ?? card.setLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let rarity = card.rarity, !rarity.isEmpty {
                    Text(rarity)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(card.game.color.opacity(0.14), in: Capsule())
                        .foregroundStyle(card.game.color)
                        .lineLimit(1)
                }
                if (price ?? card.price) == nil {
                    Text("Sin precio").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
    }
}

/// Precio como etiqueta sobre la imagen: el precio completo en un renglón y la moneda abajo, siempre igual.
struct PriceSticker: View {
    let amount: Double
    let currency: String
    var stale = false
    @Environment(AppModel.self) private var model

    var body: some View {
        let shown = model.converted(amount, from: currency).map { ($0, model.displayCurrency) } ?? (amount, currency)
        VStack(alignment: .leading, spacing: 0) {
            Text(MoneyFormatter.number(shown.0, currency: shown.1))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: true, vertical: false)
            Text(shown.1)
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .opacity(0.85)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(stale ? Theme.stale : CurrencyTag.color(for: shown.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(MoneyFormatter.string(shown.0, currency: shown.1))\(stale ? ", precio con más de una semana" : "")")
    }
}

struct CardGrid<Item: Identifiable, Tile: View>: View {
    let items: [Item]
    @ViewBuilder let tile: (Item) -> Tile

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 18)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 24) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    tile(item)
                        .staggeredAppear(index: index)
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.vertical, 16)
        }
    }
}
