import Foundation

/// Catálogo completo de One Piece construido a partir de los volcados diarios de TCGplayer (tcgcsv.com).
struct OnePieceCatalog: Codable, Sendable {
    struct SetRef: Codable, Sendable, Hashable {
        let id: Int
        let name: String
    }

    struct Entry: Codable, Sendable, Identifiable {
        let id: Int
        let name: String
        let groupID: Int
        let groupName: String
        let number: String
        let rarity: String?
        let color: String?
        let cardType: String?
        let cost: Int?
        let isParallel: Bool
        let imageURL: URL?
        let largeImageURL: URL?
        let url: URL?
        let attributes: [CardAttribute]
        let text: String?
        let prices: [PriceQuote]

        func attribute(_ label: String) -> String? {
            attributes.first { $0.label == label }?.value
        }
    }

    let builtAt: Date
    let sets: [SetRef]
    let entries: [Entry]

    func isFresh(maxAge: TimeInterval) -> Bool {
        Date().timeIntervalSince(builtAt) < maxAge
    }

    static let attributeLabels: [(key: String, label: String)] = [
        ("Number", "Número"),
        ("Rarity", "Rareza"),
        ("Color", "Color"),
        ("CardType", "Tipo"),
        ("Cost", "Costo"),
        ("Power", "Poder"),
        ("Counterplus", "Counter"),
        ("Attribute", "Atributo"),
        ("Subtypes", "Subtipos"),
        ("Life", "Vida"),
    ]

    static func build(groups: [TCGCSVGroup], products: [TCGCSVProduct], prices: [TCGCSVPrice]) -> OnePieceCatalog {
        let groupNames = Dictionary(groups.map { ($0.groupId, $0.name) }, uniquingKeysWith: { first, _ in first })
        let pricesByProduct = Dictionary(grouping: prices, by: \.productId)

        let entries: [Entry] = products.compactMap { product in
            // Solo cartas sueltas: boosters, cajas y decks no tienen número.
            guard let number = product.extended("Number"), !number.isEmpty else { return nil }

            let attributes = attributeLabels.compactMap { key, label -> CardAttribute? in
                guard let value = product.extended(key)?.strippingHTML(), !value.isEmpty else { return nil }
                return CardAttribute(label: label, value: value)
            }
            let quotes = (pricesByProduct[product.productId] ?? []).compactMap { price -> PriceQuote? in
                let quote = PriceQuote(
                    source: .tcgplayer,
                    variant: price.subTypeName ?? "Normal",
                    currency: "USD",
                    market: price.marketPrice,
                    low: price.lowPrice,
                    mid: price.midPrice,
                    high: price.highPrice
                )
                return quote.isEmpty ? nil : quote
            }
            let source = product.imageUrl.flatMap(URL.init(string:))
            let image = ImageQuality.best(source, size: .grid)
            let large = ImageQuality.best(source, size: .full)

            let lowerName = product.name.lowercased()
            return Entry(
                id: product.productId,
                name: product.name,
                groupID: product.groupId,
                groupName: groupNames[product.groupId] ?? "",
                number: number,
                rarity: product.extended("Rarity"),
                color: product.extended("Color"),
                cardType: product.extended("CardType"),
                cost: product.extended("Cost").flatMap(Int.init),
                isParallel: lowerName.contains("parallel") || lowerName.contains("alternate art") || lowerName.contains("manga"),
                imageURL: image,
                largeImageURL: large,
                url: product.url.flatMap(URL.init(string:)),
                attributes: attributes,
                text: product.extended("Description")?.strippingHTML(),
                prices: quotes
            )
        }
        let usedGroups = Set(entries.map(\.groupID))
        let sets = groups.filter { usedGroups.contains($0.groupId) }.map { SetRef(id: $0.groupId, name: $0.name) }
        return OnePieceCatalog(builtAt: .now, sets: sets, entries: entries)
    }

    static let colors: [FilterOption] = ["Red", "Green", "Blue", "Purple", "Black", "Yellow"].map { FilterOption(id: $0, title: $0) }
    static let attributes: [FilterOption] = ["Slash", "Strike", "Ranged", "Special", "Wisdom"].map { FilterOption(id: $0, title: $0) }
    static let cardTypes: [FilterOption] = ["Leader", "Character", "Event", "Stage"].map { FilterOption(id: $0, title: $0) }
    static let rarities: [FilterOption] = [
        .init(id: "L", title: "Leader (L)"), .init(id: "C", title: "Común (C)"), .init(id: "UC", title: "Infrecuente (UC)"),
        .init(id: "R", title: "Rara (R)"), .init(id: "SR", title: "Super rara (SR)"), .init(id: "SEC", title: "Secreta (SEC)"),
        .init(id: "P", title: "Promo (P)"), .init(id: "SP", title: "Especial (SP)"), .init(id: "TR", title: "Treasure (TR)"),
    ]

    func filterOptions() -> FilterOptions {
        FilterOptions(
            sets: sets.map { FilterOption(id: String($0.id), title: $0.name) },
            colors: Self.colors,
            cardTypes: Self.cardTypes,
            costs: Array(0...10),
            rarities: Self.rarities,
            supportsParallel: true,
            supportsPriceSort: true,
            mechanics: Self.attributes,
            mechanicTitle: "Atributo",
            supportsCardText: true,
            cardTextPlaceholder: "Rush, Blocker, [On Play]…",
            supportsSubtype: true,
            subtypePlaceholder: "Straw Hat Crew, Navy…",
            powerTitle: "Poder mínimo",
            powerValues: stride(from: 0, through: 12000, by: 1000).map { $0 },
            supportsPriceRange: true
        )
    }

    func matches(_ entry: Entry, filters: SearchFilters) -> Bool {
        if let set = filters.cardSet, String(entry.groupID) != set.id { return false }
        if let color = filters.color {
            let colors = (entry.color ?? "").split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            if !colors.contains(color.id) { return false }
        }
        if let type = filters.cardType, entry.cardType != type.id { return false }
        if let cost = filters.cost, entry.cost != cost { return false }
        if let rarity = filters.rarity, entry.rarity != rarity.id { return false }
        if filters.parallelOnly && !entry.isParallel { return false }
        if let attribute = filters.mechanic {
            let value = entry.attribute("Atributo") ?? ""
            if !value.localizedCaseInsensitiveContains(attribute.id) { return false }
        }
        let subtype = filters.subtype.trimmed
        if !subtype.isEmpty, !(entry.attribute("Subtipos") ?? "").localizedCaseInsensitiveContains(subtype) { return false }
        let text = filters.cardText.trimmed
        if !text.isEmpty, !(entry.text ?? "").localizedCaseInsensitiveContains(text) { return false }
        if let minPower = filters.minPower {
            guard let power = entry.attribute("Poder").flatMap({ Int($0.filter(\.isNumber)) }), power >= minPower else { return false }
        }
        if !filters.priceMatches(PrintingPicker.cheapestReference(entry.prices)) { return false }
        return true
    }

    func search(_ query: String, filters: SearchFilters, limit: Int = 300) -> [Entry] {
        let needle = Self.normalize(query)
        let base: [Entry]
        if needle.isEmpty {
            guard !filters.isEmpty else { return [] }
            base = entries.filter { matches($0, filters: filters) }.sorted { ($0.number, $0.name) < ($1.number, $1.name) }
        } else {
            base = search(query, limit: .max).filter { matches($0, filters: filters) }
        }
        let summaries = base.map(Self.summary)
        switch filters.sort {
        case .relevance, .newest, .oldest:
            return Array(base.prefix(limit))
        case .priceAsc, .priceDesc, .nameAsc, .nameDesc, .number:
            let order = summaries.sorted(by: filters.sort).map(\.providerID)
            let index = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
            return Array(base.sorted { (index[String($0.id)] ?? 0) < (index[String($1.id)] ?? 0) }.prefix(limit))
        }
    }

    static func normalize(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    func search(_ query: String, limit: Int = 150) -> [Entry] {
        let needle = Self.normalize(query)
        guard !needle.isEmpty else { return [] }

        let scored: [(score: Int, entry: Entry)] = entries.compactMap { entry in
            let name = Self.normalize(entry.name)
            let number = Self.normalize(entry.number)
            if name.hasPrefix(needle) { return (0, entry) }
            if number.hasPrefix(needle) { return (1, entry) }
            if name.contains(needle) { return (2, entry) }
            if number.contains(needle) { return (3, entry) }
            return nil
        }
        return scored
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score < rhs.score }
                if lhs.entry.number != rhs.entry.number { return lhs.entry.number < rhs.entry.number }
                return lhs.entry.name < rhs.entry.name
            }
            .prefix(limit)
            .map(\.entry)
    }

    func entry(id: Int) -> Entry? {
        entries.first { $0.id == id }
    }

    /// Todas las impresiones con el mismo número (normal, paralela, box topper...).
    func printings(number: String) -> [Entry] {
        let key = number.uppercased()
        return entries.filter { $0.number.uppercased() == key }
    }

    static func summary(_ entry: Entry) -> CardSummary {
        CardSummary(
            game: .onePiece,
            providerID: String(entry.id),
            name: entry.name,
            setName: entry.groupName,
            number: entry.number,
            rarity: entry.rarity,
            thumbnailURL: ImageQuality.best(entry.imageURL, size: .grid),
            imageURL: ImageQuality.best(entry.largeImageURL ?? entry.imageURL, size: .full),
            canonicalKey: entry.number.uppercased(),
            price: PrintingPicker.cheapestReference(entry.prices),
            priceCurrency: "USD"
        )
    }

    static func detail(_ entry: Entry) -> CardDetail {
        CardDetail(
            summary: summary(entry),
            attributes: [CardAttribute(label: "Set", value: entry.groupName)] + entry.attributes,
            text: entry.text,
            prices: entry.prices,
            externalURL: entry.url
        )
    }
}
