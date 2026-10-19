import Foundation

struct ScryfallCard: Decodable, Sendable {
    struct ImageURIs: Decodable, Sendable {
        let small: URL?
        let normal: URL?
        let large: URL?
    }

    struct Face: Decodable, Sendable {
        let name: String?
        let imageUris: ImageURIs?
        let oracleText: String?
        let manaCost: String?
        let typeLine: String?
    }

    struct Prices: Decodable, Sendable {
        let usd: String?
        let usdFoil: String?
        let usdEtched: String?
        let eur: String?
        let eurFoil: String?
    }

    let id: String
    let oracleId: String?
    let name: String
    let setName: String
    let set: String
    let collectorNumber: String
    let rarity: String
    let imageUris: ImageURIs?
    let cardFaces: [Face]?
    let prices: Prices
    let oracleText: String?
    let manaCost: String?
    let typeLine: String?
    let artist: String?
    let scryfallUri: URL?
}

struct ScryfallList: Decodable, Sendable {
    let data: [ScryfallCard]
}

struct ScryfallSet: Decodable, Sendable {
    let code: String
    let name: String
    let setType: String
    let digital: Bool
    let releasedAt: String?
}

enum ScryfallQueryBuilder {
    static let colors: [FilterOption] = [
        .init(id: "w", title: "Blanco"), .init(id: "u", title: "Azul"), .init(id: "b", title: "Negro"),
        .init(id: "r", title: "Rojo"), .init(id: "g", title: "Verde"), .init(id: "c", title: "Incoloro"),
        .init(id: "m", title: "Multicolor"),
    ]
    static let types: [FilterOption] = ["Creature", "Instant", "Sorcery", "Artifact", "Enchantment", "Planeswalker", "Land", "Battle"]
        .map { FilterOption(id: $0.lowercased(), title: $0) }
    static let rarities: [FilterOption] = [
        .init(id: "common", title: "Común"), .init(id: "uncommon", title: "Infrecuente"),
        .init(id: "rare", title: "Rara"), .init(id: "mythic", title: "Mítica"),
    ]
    static let formats: [FilterOption] = [
        .init(id: "commander", title: "Commander"), .init(id: "standard", title: "Standard"),
        .init(id: "pioneer", title: "Pioneer"), .init(id: "modern", title: "Modern"),
        .init(id: "legacy", title: "Legacy"), .init(id: "vintage", title: "Vintage"),
        .init(id: "pauper", title: "Pauper"), .init(id: "brawl", title: "Brawl"),
    ]
    static let keywords: [FilterOption] = ["Flying", "Trample", "Haste", "Deathtouch", "Lifelink", "Vigilance",
                                           "First strike", "Double strike", "Flash", "Hexproof", "Indestructible",
                                           "Menace", "Reach", "Ward", "Prowess", "Cycling", "Flashback", "Convoke"]
        .map { FilterOption(id: $0.lowercased(), title: $0) }

    private static func quoted(_ value: String) -> String {
        let clean = value.trimmed.replacingOccurrences(of: "\"", with: "")
        return clean.contains(" ") ? "\"\(clean)\"" : clean
    }

    private static func usd(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    /// Sintaxis de búsqueda de Scryfall. Siempre limita a papel para no traer Alchemy ni digitales.
    static func query(text: String, filters: SearchFilters) -> String {
        var parts: [String] = []
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { parts.append(trimmed) }
        if let set = filters.cardSet { parts.append("set:\(set.id)") }
        if let color = filters.color { parts.append("c:\(color.id)") }
        if let type = filters.cardType { parts.append("t:\(type.id)") }
        if let cost = filters.cost { parts.append(cost >= 7 ? "mv>=7" : "mv=\(cost)") }
        if let rarity = filters.rarity { parts.append("r:\(rarity.id)") }
        if !filters.cardText.trimmed.isEmpty { parts.append("o:\(quoted(filters.cardText))") }
        if !filters.subtype.trimmed.isEmpty { parts.append("t:\(quoted(filters.subtype))") }
        if let format = filters.format { parts.append("f:\(format.id)") }
        if let mechanic = filters.mechanic { parts.append("k:\(quoted(mechanic.id))") }
        if let minPower = filters.minPower { parts.append("pow>=\(minPower)") }
        if let min = filters.priceMinUSD { parts.append("usd>=\(usd(min))") }
        if let max = filters.priceMaxUSD { parts.append("usd<=\(usd(max))") }
        parts.append("game:paper")
        return parts.joined(separator: " ")
    }
}

enum ScryfallMapper {
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    static func summary(_ card: ScryfallCard) -> CardSummary {
        let images = card.imageUris ?? card.cardFaces?.first?.imageUris
        return CardSummary(
            game: .magic,
            providerID: card.id,
            name: card.name,
            setName: "\(card.setName) (\(card.set.uppercased()))",
            number: card.collectorNumber,
            rarity: card.rarity.capitalized,
            thumbnailURL: images?.normal ?? images?.small,
            imageURL: images?.large ?? images?.normal,
            canonicalKey: card.oracleId ?? card.name,
            price: card.prices.usd.flatMap(Double.init),
            priceCurrency: "USD"
        )
    }

    static func detail(_ card: ScryfallCard) -> CardDetail {
        var attributes: [CardAttribute] = []
        if let typeLine = card.typeLine ?? card.cardFaces?.first?.typeLine {
            attributes.append(.init(label: "Tipo", value: typeLine))
        }
        if let mana = card.manaCost ?? card.cardFaces?.first?.manaCost, !mana.isEmpty {
            attributes.append(.init(label: "Costo de maná", value: mana))
        }
        attributes.append(.init(label: "Rareza", value: card.rarity.capitalized))
        attributes.append(.init(label: "Set", value: "\(card.setName) (\(card.set.uppercased()))"))
        attributes.append(.init(label: "Número", value: card.collectorNumber))
        if let artist = card.artist {
            attributes.append(.init(label: "Artista", value: artist))
        }

        let text = card.oracleText ?? card.cardFaces?.compactMap(\.oracleText).joined(separator: "\n\n")

        return CardDetail(
            summary: summary(card),
            attributes: attributes,
            text: text,
            prices: quotes(card.prices),
            externalURL: card.scryfallUri
        )
    }

    /// Scryfall toma los precios USD de TCGplayer y los EUR de Cardmarket.
    static func quotes(_ prices: ScryfallCard.Prices) -> [PriceQuote] {
        func quote(_ raw: String?, source: PriceQuote.Source, variant: String, currency: String) -> PriceQuote? {
            guard let raw, let value = Double(raw) else { return nil }
            return PriceQuote(source: source, variant: variant, currency: currency, market: value, low: nil, mid: nil, high: nil)
        }
        return [
            quote(prices.usd, source: .tcgplayer, variant: "Normal", currency: "USD"),
            quote(prices.usdFoil, source: .tcgplayer, variant: "Foil", currency: "USD"),
            quote(prices.usdEtched, source: .tcgplayer, variant: "Etched", currency: "USD"),
            quote(prices.eur, source: .cardmarket, variant: "Normal", currency: "EUR"),
            quote(prices.eurFoil, source: .cardmarket, variant: "Foil", currency: "EUR"),
        ].compactMap { $0 }
    }
}

struct ScryfallProvider: CardProvider {
    let game: Game = .magic
    let client: HTTPClient

    private static let base = "https://api.scryfall.com"

    func search(_ query: String, filters: SearchFilters) async throws -> [CardSummary] {
        guard var components = URLComponents(string: "\(Self.base)/cards/search") else { throw ProviderError.badURL }
        let order: String
        switch filters.sort {
        case .priceAsc, .priceDesc: order = "usd"
        case .nameAsc, .nameDesc: order = "name"
        case .number: order = "set"
        default: order = "released"
        }
        let descending = filters.sort == .priceDesc || filters.sort == .nameDesc || filters.sort == .newest || filters.sort == .relevance
        components.queryItems = [
            URLQueryItem(name: "q", value: ScryfallQueryBuilder.query(text: query, filters: filters)),
            URLQueryItem(name: "unique", value: "prints"),
            URLQueryItem(name: "order", value: order),
            URLQueryItem(name: "dir", value: descending ? "desc" : "asc"),
        ]
        guard let url = components.url else { throw ProviderError.badURL }
        do {
            let list = try await client.json(ScryfallList.self, from: url, decoder: ScryfallMapper.decoder)
            return list.data.map(ScryfallMapper.summary).sorted(by: filters.sort)
        } catch let error as HTTPError where error.statusCode == 404 {
            return []
        }
    }

    func filterOptions() async throws -> FilterOptions {
        struct SetList: Decodable { let data: [ScryfallSet] }
        guard let url = URL(string: "\(Self.base)/sets") else { throw ProviderError.badURL }
        let sets = try await client.json(SetList.self, from: url, decoder: ScryfallMapper.decoder).data
        let today = ISO8601DateFormatter().string(from: .now).prefix(10)
        let paper = sets
            .filter { !$0.digital && ["expansion", "core", "masters", "commander", "draft_innovation", "starter", "funny", "box", "duel_deck", "premium_deck", "planechase"].contains($0.setType) }
            .filter { ($0.releasedAt ?? "9999") <= today }
            .map { FilterOption(id: $0.code, title: "\($0.name) (\($0.code.uppercased()))") }
        return FilterOptions(
            sets: paper,
            colors: ScryfallQueryBuilder.colors,
            cardTypes: ScryfallQueryBuilder.types,
            costs: Array(0...7),
            rarities: ScryfallQueryBuilder.rarities,
            supportsParallel: false,
            supportsPriceSort: true,
            formats: ScryfallQueryBuilder.formats,
            mechanics: ScryfallQueryBuilder.keywords,
            mechanicTitle: "Habilidad",
            supportsCardText: true,
            cardTextPlaceholder: "draw a card, destroy target…",
            supportsSubtype: true,
            subtypePlaceholder: "Elf, Dragon, Wizard…",
            powerTitle: "Poder mínimo",
            powerValues: Array(0...10),
            supportsPriceRange: true,
            supportsDateSort: true
        )
    }

    func detail(providerID: String) async throws -> CardDetail {
        guard let url = URL(string: "\(Self.base)/cards/\(providerID)") else { throw ProviderError.badURL }
        let card = try await client.json(ScryfallCard.self, from: url, decoder: ScryfallMapper.decoder)
        return ScryfallMapper.detail(card)
    }

    /// Búsqueda difusa por nombre (tolera errores de OCR). Nil si Scryfall no encuentra nada.
    func named(fuzzy name: String, set: String?) async throws -> CardDetail? {
        guard var components = URLComponents(string: "\(Self.base)/cards/named") else { throw ProviderError.badURL }
        var items = [URLQueryItem(name: "fuzzy", value: name)]
        if let set { items.append(URLQueryItem(name: "set", value: set)) }
        components.queryItems = items
        guard let url = components.url else { throw ProviderError.badURL }
        do {
            return ScryfallMapper.detail(try await client.json(ScryfallCard.self, from: url, decoder: ScryfallMapper.decoder))
        } catch let error as HTTPError where error.statusCode == 404 {
            return nil
        }
    }

    /// Carta exacta por código de set y número de coleccionista.
    func card(set: String, collectorNumber: String) async throws -> CardDetail? {
        guard let url = URL(string: "\(Self.base)/cards/\(set.lowercased())/\(collectorNumber)") else { throw ProviderError.badURL }
        do {
            return ScryfallMapper.detail(try await client.json(ScryfallCard.self, from: url, decoder: ScryfallMapper.decoder))
        } catch let error as HTTPError where error.statusCode == 404 {
            return nil
        }
    }

    /// Reimpresiones por oracle_id (solo papel, sin Alchemy ni digitales).
    func printings(of detail: CardDetail) async throws -> [CardDetail] {
        let key = detail.summary.canonicalKey
        guard var components = URLComponents(string: "\(Self.base)/cards/search") else { return [detail] }
        components.queryItems = [
            URLQueryItem(name: "q", value: "oracleid:\(key) game:paper"),
            URLQueryItem(name: "unique", value: "prints"),
            URLQueryItem(name: "order", value: "usd"),
            URLQueryItem(name: "dir", value: "asc"),
        ]
        guard let url = components.url else { return [detail] }
        do {
            let list = try await client.json(ScryfallList.self, from: url, decoder: ScryfallMapper.decoder)
            let all = list.data.map(ScryfallMapper.detail)
            return all.isEmpty ? [detail] : all
        } catch let error as HTTPError where error.statusCode == 404 {
            return [detail]
        }
    }
}
