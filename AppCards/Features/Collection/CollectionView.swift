import SwiftUI
import SwiftData

struct CollectionView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var model
    @Query(sort: \CollectionItem.addedAt, order: .reverse) private var items: [CollectionItem]
    @Query private var wishlist: [WishlistItem]
    @Query(sort: \CollectionSnapshot.date) private var snapshots: [CollectionSnapshot]

    @State private var gameFilter: Game?
    @State private var query = ""
    @State private var showScanner = false
    @State private var viewerCard: CardSummary?
    @State private var deckTarget: CardSummary?
    @AppStorage("collectionSort") private var sort: CollectionSort = .recent

    private var filtered: [CollectionItem] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let matching = items.filter { item in
            (gameFilter == nil || item.game == gameFilter)
                && (needle.isEmpty || item.name.lowercased().contains(needle) || item.number.lowercased().contains(needle))
        }
        return CollectionSorter.sort(matching, by: sort) { item in
            item.referencePrice.flatMap { model.converted($0 * Double(item.quantity), from: item.referenceCurrency) }
        }
    }

    private var total: CollectionTotal {
        CollectionMath.total(lines: filtered.map(\.line), in: model.displayCurrency, converter: model.converter)
    }

    /// Valor de ayer (último snapshot que no sea de hoy), solo cuando se ve toda la colección.
    private var previousValue: Double? {
        guard gameFilter == nil, query.isEmpty,
              let snap = snapshots.last(where: { !Calendar.current.isDateInToday($0.date) }) else { return nil }
        return model.converted(snap.referenceValue, from: snap.currency)
    }

    var body: some View {
        AdaptiveSplitView(for: CollectionItem.self) { item in
            CollectionItemView(item: item)
        } empty: {
            SplitPlaceholder(title: "Elige una carta", message: "Toca una carta de tu colección para ver su ficha aquí.", color: gameFilter?.color ?? .vaultBlue)
        } primary: {
            VStack(spacing: 0) {
                GameSelector(selection: $gameFilter, allowsAll: true)

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                        header
                            .floatIn()
                        if gameFilter == nil && query.isEmpty {
                            CollectionSparkline()
                                .floatIn(delay: 0.08)
                                .padding(18)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                        }
                        if items.isEmpty {
                            EmptyStateView(
                                title: "Tu bóveda está vacía",
                                message: "Escanea tus cartas con la cámara, mantén presionada una carta en Buscar y toca +1, o usa el botón de colección en el detalle.",
                                color: gameFilter?.color ?? .vaultBlue
                            )
                        } else if filtered.isEmpty {
                            EmptyStateView(title: "Nada por aquí", message: "No tienes cartas que coincidan con ese filtro.", color: .gray)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 18)], spacing: 24) {
                            ForEach(Array(filtered.enumerated()), id: \.element.persistentModelID) { index, item in
                                ItemLink(value: item) {
                                    CollectionTile(item: item, wished: wishlist.contains { $0.cardID == item.cardID })
                                }
                                .buttonStyle(PressableStyle())
                                .accessibilityIdentifier("collection-tile")
                                .staggeredAppear(index: index)
                                .contextMenu {
                                    Button { viewerCard = item.summary } label: { Label("Ver carta completa", systemImage: "arrow.up.left.and.arrow.down.right") }
                                    Button { deckTarget = item.summary } label: { Label("Agregar a un deck", systemImage: "plus.rectangle.on.rectangle") }
                                    Button { item.quantity += 1; try? context.save() } label: { Label("+1", systemImage: "plus") }
                                    if item.quantity > 1 {
                                        Button { item.quantity -= 1; try? context.save() } label: { Label("−1", systemImage: "minus") }
                                    }
                                    Button(role: .destructive) { context.delete(item); try? context.save() } label: { Label("Eliminar", systemImage: "trash") }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
            .background(ScreenBackground(color: gameFilter?.color ?? .vaultBlue))
            .animation(Motion.gentle, value: gameFilter)
            .navigationTitle("Colección")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Filtrar por nombre o número")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Ordenar", selection: $sort) {
                            ForEach(CollectionSort.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                        }
                    } label: {
                        Label("Ordenar", systemImage: "arrow.up.arrow.down")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showScanner = true } label: { Label("Escanear cartas", systemImage: "camera") }
                }
            }
            .fullScreenCover(isPresented: $showScanner) { ScannerView(autoAddToCollection: true) }
            .sheet(item: $deckTarget) { AddToDeckLoader(card: $0) }
            .cardViewer(for: $viewerCard)
            .onChange(of: gameFilter) { _, newValue in model.collectionGame = newValue }
            .onAppear { model.collectionGame = gameFilter }
        }
    }

    private var header: some View {
        GradientCard(colors: gameFilter.map { [$0.color, $0.color.opacity(0.7)] } ?? [.vaultBlue, .vaultBlueDark], foreground: gameFilter?.onColor ?? .white) {
            VStack(alignment: .leading, spacing: 18) {
                BigAmountView(
                    title: "Valor de mercado",
                    amount: total.referenceValue,
                    currency: total.currency,
                    previous: previousValue,
                    footnote: previousValue == nil ? "\(total.totalCards) cartas" : nil,
                    onGradient: true
                )
                Divider().overlay((gameFilter?.onColor ?? .white).opacity(0.45))
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Lo que pagaste").font(.footnote).opacity(0.85)
                        MoneyText(amount: total.localValue, currency: total.currency, font: .title3.weight(.bold), onGradient: true)
                        Text("\(total.cardsWithLocalPrice) de \(total.totalCards) con precio local").font(.caption).opacity(0.85)
                    }
                    Spacer()
                    if total.localValue > 0 {
                        let diff = total.referenceValue - total.localValue
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(diff >= 0 ? "Ganancia" : "Pérdida").font(.footnote).opacity(0.85)
                            MoneyText(amount: diff, currency: total.currency, font: .title3.weight(.bold), onGradient: true)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background((gameFilter?.onColor ?? .white).opacity(0.22), in: Capsule())
                        }
                    }
                }
            }
        }
    }
}

struct CollectionTile: View {
    let item: CollectionItem
    var wished = false

    var body: some View {
        let card = CardSummary(game: item.game, providerID: item.providerID, name: item.name, setName: item.setName, number: item.number,
                               rarity: nil, thumbnailURL: item.imageURL, imageURL: item.imageURL, canonicalKey: item.canonicalKey)
        CardGridTile(
            card: card,
            owned: item.quantity,
            wished: wished,
            subtitle: item.localPrice.map { "Pagaste \(MoneyFormatter.string($0, currency: item.localCurrency))" } ?? item.setLine,
            price: item.referencePrice.map { $0 * Double(item.quantity) },
            priceCurrency: item.referenceCurrency,
            updatedAt: item.priceUpdatedAt
        )
    }
}

/// Orden de la colección.
enum CollectionSorter {
    static func sort(_ items: [CollectionItem], by sort: CollectionSort, value: (CollectionItem) -> Double?) -> [CollectionItem] {
        switch sort {
        case .recent:
            return items.sorted { $0.addedAt > $1.addedAt }
        case .name:
            return items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .valueDesc:
            return items.sorted { (value($0) ?? -1) > (value($1) ?? -1) }
        case .quantityDesc:
            return items.sorted { $0.quantity == $1.quantity ? $0.name < $1.name : $0.quantity > $1.quantity }
        case .set:
            return items.sorted {
                $0.setName == $1.setName
                    ? $0.number.localizedStandardCompare($1.number) == .orderedAscending
                    : $0.setName.localizedStandardCompare($1.setName) == .orderedAscending
            }
        }
    }
}
