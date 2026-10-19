import Foundation

struct TCGdexBrief: Decodable, Sendable {
    let id: String
    let localId: String
    let name: String
    let image: String?
}

struct TCGdexCard: Decodable, Sendable {
    struct SetRef: Decodable, Sendable {
        let id: String
        let name: String
    }

    let id: String
    let localId: String
    let name: String
    let image: String?
    let rarity: String?
    let set: SetRef?
    let illustrator: String?
    let category: String?
    let hp: Int?
    let types: [String]?
    let stage: String?
    let pricing: TCGdexPricing?
}

/// `pricing` de TCGdex trae llaves dinámicas: variantes de TCGplayer (`normal`, `reverse-holofoil`, ...)
/// y valores planos de Cardmarket (`avg`, `low-holo`, `trend-reverse`, ...).
struct TCGdexPricing: Decodable, Sendable {
    struct Variant: Decodable, Sendable {
        let lowPrice: Double?
        let midPrice: Double?
        let highPrice: Double?
        let marketPrice: Double?
    }

    var tcgplayerUnit: String?
    var tcgplayerVariants: [String: Variant] = [:]
    var cardmarketUnit: String?
    var cardmarketValues: [String: Double] = [:]

    init(tcgplayerUnit: String? = nil, tcgplayerVariants: [String: Variant] = [:],
         cardmarketUnit: String? = nil, cardmarketValues: [String: Double] = [:]) {
        self.tcgplayerUnit = tcgplayerUnit
        self.tcgplayerVariants = tcgplayerVariants
        self.cardmarketUnit = cardmarketUnit
        self.cardmarketValues = cardmarketValues
    }

    init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: AnyCodingKey.self)
        let skipped: Set<String> = ["unit", "updated", "idProduct"]

        if let tcg = try? root.nestedContainer(keyedBy: AnyCodingKey.self, forKey: AnyCodingKey("tcgplayer")) {
            tcgplayerUnit = try? tcg.decodeIfPresent(String.self, forKey: AnyCodingKey("unit"))
            for key in tcg.allKeys where !skipped.contains(key.stringValue) {
                if let variant = try? tcg.decode(Variant.self, forKey: key) {
                    tcgplayerVariants[key.stringValue] = variant
                }
            }
        }

        if let cm = try? root.nestedContainer(keyedBy: AnyCodingKey.self, forKey: AnyCodingKey("cardmarket")) {
            cardmarketUnit = try? cm.decodeIfPresent(String.self, forKey: AnyCodingKey("unit"))
            for key in cm.allKeys where !skipped.contains(key.stringValue) {
                if let value = try? cm.decode(Double.self, forKey: key) {
                    cardmarketValues[key.stringValue] = value
                }
            }
        }
    }
}

enum TCGdexMapper {
    static func thumbnail(_ image: String?) -> URL? {
        image.flatMap { URL(string: "\($0)/high.webp") }
    }

    static func large(_ image: String?) -> URL? {
        image.flatMap { URL(string: "\($0)/high.webp") }
    }

    static func setCode(from id: String) -> String {
        guard let range = id.range(of: "-", options: .backwards) else { return id }
        return String(id[..<range.lowerBound]).uppercased()
    }

    static func summary(_ brief: TCGdexBrief) -> CardSummary {
        CardSummary(
            game: .pokemon,
            providerID: brief.id,
            name: brief.name,
            setName: setCode(from: brief.id),
            number: brief.localId,
            rarity: nil,
            thumbnailURL: thumbnail(brief.image),
            imageURL: large(brief.image),
            canonicalKey: brief.id
        )
    }

    static func summary(_ card: TCGdexCard) -> CardSummary {
        CardSummary(
            game: .pokemon,
            providerID: card.id,
            name: card.name,
            setName: card.set?.name ?? setCode(from: card.id),
            number: card.localId,
            rarity: card.rarity,
            thumbnailURL: thumbnail(card.image),
            imageURL: large(card.image),
            canonicalKey: card.id
        )
    }

    static func detail(_ card: TCGdexCard) -> CardDetail {
        var attributes: [CardAttribute] = []
        if let set = card.set { attributes.append(.init(label: "Set", value: "\(set.name) (\(set.id.uppercased()))")) }
        attributes.append(.init(label: "Número", value: card.localId))
        if let rarity = card.rarity { attributes.append(.init(label: "Rareza", value: rarity)) }
        if let category = card.category { attributes.append(.init(label: "Categoría", value: category)) }
        if let stage = card.stage { attributes.append(.init(label: "Etapa", value: stage)) }
        if let hp = card.hp { attributes.append(.init(label: "HP", value: String(hp))) }
        if let types = card.types, !types.isEmpty { attributes.append(.init(label: "Tipo", value: types.joined(separator: ", "))) }
        if let illustrator = card.illustrator { attributes.append(.init(label: "Ilustrador", value: illustrator)) }

        return CardDetail(
            summary: summary(card),
            attributes: attributes,
            text: nil,
            prices: quotes(card.pricing),
            externalURL: URL(string: "https://tcgdex.dev/card/\(card.id)")
        )
    }

    static func variantTitle(_ key: String) -> String {
        key.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    static func quotes(_ pricing: TCGdexPricing?) -> [PriceQuote] {
        guard let pricing else { return [] }
        var result: [PriceQuote] = []

        for (key, variant) in pricing.tcgplayerVariants.sorted(by: { $0.key < $1.key }) {
            let quote = PriceQuote(
                source: .tcgplayer,
                variant: variantTitle(key),
                currency: pricing.tcgplayerUnit ?? "USD",
                market: variant.marketPrice,
                low: variant.lowPrice,
                mid: variant.midPrice,
                high: variant.highPrice
            )
            if !quote.isEmpty { result.append(quote) }
        }

        // Cardmarket: avg / low / trend con sufijo opcional de variante (-holo, -reverse, ...).
        var grouped: [String: [String: Double]] = [:]
        for (key, value) in pricing.cardmarketValues {
            let parts = key.split(separator: "-", maxSplits: 1).map(String.init)
            guard let metric = parts.first, ["avg", "low", "trend"].contains(metric) else { continue }
            let suffix = parts.count > 1 ? parts[1] : ""
            grouped[suffix, default: [:]][metric] = value
        }
        for (suffix, values) in grouped.sorted(by: { $0.key < $1.key }) {
            let variant = suffix.isEmpty ? "Normal" : variantTitle(suffix)
            let quote = PriceQuote(
                source: .cardmarket,
                variant: variant,
                currency: pricing.cardmarketUnit ?? "EUR",
                market: values["trend"],
                low: values["low"],
                mid: values["avg"],
                high: nil
            )
            if !quote.isEmpty { result.append(quote) }
        }
        return result
    }
}

struct TCGdexProvider: CardProvider {
    let game: Game = .pokemon
    let client: HTTPClient

    private static let base = "https://api.tcgdex.net/v2/en"

    static let types: [FilterOption] = ["Grass", "Fire", "Water", "Lightning", "Psychic", "Fighting", "Darkness", "Metal", "Fairy", "Dragon", "Colorless"]
        .map { FilterOption(id: $0, title: $0) }
    static let categories: [FilterOption] = [
        .init(id: "Pokemon", title: "Pokémon"), .init(id: "Trainer", title: "Entrenador"), .init(id: "Energy", title: "Energía"),
    ]

    static let formats: [FilterOption] = [.init(id: "standard", title: "Standard"), .init(id: "expanded", title: "Expanded")]
    static let suffixes: [FilterOption] = ["ex", "EX", "V", "VMAX", "VSTAR", "GX"].map { FilterOption(id: $0, title: $0) }
    static let stages: [FilterOption] = [
        .init(id: "Basic", title: "Básico"), .init(id: "Stage1", title: "Fase 1"), .init(id: "Stage2", title: "Fase 2"),
        .init(id: "VMAX", title: "VMAX"), .init(id: "VSTAR", title: "VSTAR"),
    ]

    /// Parámetros de búsqueda de TCGdex (se prueban en tests).
    static func queryItems(text: String, filters: SearchFilters) -> [URLQueryItem] {
        var items: [URLQueryItem] = []
        let trimmed = text.trimmed
        if !trimmed.isEmpty { items.append(URLQueryItem(name: "name", value: "like:\(trimmed)")) }
        // `eq:` = coincidencia exacta. Sin eso TCGdex busca "contiene": "Rare" traería también "Holo Rare" y "Ultra Rare".
        if let set = filters.cardSet { items.append(URLQueryItem(name: "set.id", value: "eq:\(set.id)")) }
        if let type = filters.color { items.append(URLQueryItem(name: "types", value: "eq:\(type.id)")) }
        if let category = filters.cardType { items.append(URLQueryItem(name: "category", value: "eq:\(category.id)")) }
        if let rarity = filters.rarity { items.append(URLQueryItem(name: "rarity", value: "eq:\(rarity.id)")) }
        if let stage = filters.stage { items.append(URLQueryItem(name: "stage", value: "eq:\(stage.id)")) }
        if let suffix = filters.mechanic { items.append(URLQueryItem(name: "suffix", value: "eq:\(suffix.id)")) }
        if let format = filters.format { items.append(URLQueryItem(name: "legal.\(format.id)", value: "true")) }
        if let hp = filters.minPower { items.append(URLQueryItem(name: "hp", value: "gte:\(hp)")) }
        if !filters.cardText.trimmed.isEmpty { items.append(URLQueryItem(name: "illustrator", value: "like:\(filters.cardText.trimmed)")) }
        items.append(URLQueryItem(name: "sort:field", value: filters.cardSet == nil ? "name" : "localId"))
        return items
    }

    func search(_ query: String, filters: SearchFilters) async throws -> [CardSummary] {
        guard var components = URLComponents(string: "\(Self.base)/cards") else { throw ProviderError.badURL }
        components.queryItems = Self.queryItems(text: query, filters: filters)
        guard let url = components.url else { throw ProviderError.badURL }
        let briefs = try await client.json([TCGdexBrief].self, from: url)
        return briefs.map(TCGdexMapper.summary)
    }

    /// Sets cuyo total oficial de cartas coincide (el "189" de "136/189"). Llave: id del set en minúsculas.
    func setIDs(byOfficialCount count: Int) async throws -> [String: String] {
        struct SetBrief: Decodable { struct Count: Decodable { let official: Int?; let total: Int? }; let id: String; let name: String; let cardCount: Count? }
        guard let url = URL(string: "\(Self.base)/sets") else { throw ProviderError.badURL }
        let sets = try await client.json([SetBrief].self, from: url)
        return Dictionary(sets.filter { $0.cardCount?.official == count }.map { ($0.id.lowercased(), $0.name) }, uniquingKeysWith: { a, _ in a })
    }

    func filterOptions() async throws -> FilterOptions {
        struct SetBrief: Decodable { let id: String; let name: String }
        guard let setsURL = URL(string: "\(Self.base)/sets"), let raritiesURL = URL(string: "\(Self.base)/rarities") else { throw ProviderError.badURL }
        async let sets = client.json([SetBrief].self, from: setsURL)
        async let rarities = client.json([String].self, from: raritiesURL)
        return try await FilterOptions(
            sets: sets.reversed().map { FilterOption(id: $0.id, title: "\($0.name) (\($0.id.uppercased()))") },
            colors: Self.types,
            cardTypes: Self.categories,
            costs: [],
            rarities: rarities.filter { $0 != "None" }.map { FilterOption(id: $0, title: $0) },
            supportsParallel: false,
            supportsPriceSort: false,
            priceSortNote: "TCGdex no da precios en la lista de resultados, así que no se puede ordenar ni filtrar por precio.",
            formats: Self.formats,
            mechanics: Self.suffixes,
            mechanicTitle: "Tipo de carta (ex, V, VMAX…)",
            stages: Self.stages,
            supportsCardText: true,
            cardTextPlaceholder: "Ilustrador: Mitsuhiro Arita…",
            powerTitle: "HP mínimo",
            powerValues: stride(from: 30, through: 340, by: 10).map { $0 }
        )
    }

    func detail(providerID: String) async throws -> CardDetail {
        guard let url = URL(string: "\(Self.base)/cards/\(providerID)") else { throw ProviderError.badURL }
        let card = try await client.json(TCGdexCard.self, from: url)
        return TCGdexMapper.detail(card)
    }
}
