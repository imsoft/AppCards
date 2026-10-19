import Foundation

struct CardSummary: Identifiable, Hashable, Codable, Sendable {
    let game: Game
    let providerID: String
    let name: String
    let setName: String
    let number: String
    var rarity: String?
    let thumbnailURL: URL?
    let imageURL: URL?
    /// Agrupa reimpresiones de la misma carta: oracle_id en Magic, número (OP01-003) en One Piece, id en Pokémon.
    let canonicalKey: String
    /// Precio de referencia para listas y ordenar (USD si existe). No todas las fuentes lo traen en búsqueda.
    var price: Double? = nil
    var priceCurrency: String? = nil

    var id: String { "\(game.rawValue):\(providerID)" }
    var setLine: String { [setName, "#\(number)"].filter { !$0.isEmpty }.joined(separator: " · ") }
}

struct CardAttribute: Hashable, Codable, Identifiable, Sendable {
    let label: String
    let value: String
    var id: String { label }
}

struct PriceQuote: Hashable, Codable, Identifiable, Sendable {
    enum Source: String, Codable, Sendable {
        case tcgplayer
        case cardmarket

        var title: String {
            switch self {
            case .tcgplayer: "TCGplayer"
            case .cardmarket: "Cardmarket"
            }
        }
    }

    let source: Source
    let variant: String
    let currency: String
    let market: Double?
    let low: Double?
    let mid: Double?
    let high: Double?

    var id: String { "\(source.rawValue)|\(variant)" }
    var title: String { "\(source.title) · \(variant)" }
    /// Precio de referencia para sumar en un deck.
    var reference: Double? { market ?? mid ?? low }
    var isEmpty: Bool { market == nil && low == nil && mid == nil && high == nil }
}

struct CardDetail: Hashable, Codable, Sendable {
    let summary: CardSummary
    let attributes: [CardAttribute]
    let text: String?
    let prices: [PriceQuote]
    let externalURL: URL?

    var pricedQuotes: [PriceQuote] { prices.filter { $0.reference != nil } }

    func quote(id: String) -> PriceQuote? {
        prices.first { $0.id == id }
    }

    /// Cotización más barata de esta impresión. Prefiere la moneda indicada para comparar peras con peras.
    func cheapestQuote(preferring currency: String = "USD") -> PriceQuote? {
        let candidates = pricedQuotes
        let preferred = candidates.filter { $0.currency == currency }
        let pool = preferred.isEmpty ? candidates : preferred
        return pool.min { ($0.reference ?? .infinity) < ($1.reference ?? .infinity) }
    }
}

enum PrintingPicker {
    static func cheapestReference(_ quotes: [PriceQuote], currency: String = "USD") -> Double? {
        quotes.filter { $0.currency == currency }.compactMap(\.reference).min()
    }

    /// Entre varias impresiones, la que tenga la cotización más baja (comparando en la misma moneda).
    static func cheapest(_ printings: [CardDetail], preferring currency: String = "USD") -> (detail: CardDetail, quote: PriceQuote)? {
        let scored = printings.compactMap { detail -> (CardDetail, PriceQuote)? in
            guard let quote = detail.cheapestQuote(preferring: currency) else { return nil }
            return (detail, quote)
        }
        let sameCurrency = scored.filter { $0.1.currency == currency }
        let pool = sameCurrency.isEmpty ? scored : sameCurrency
        return pool.min { ($0.1.reference ?? .infinity) < ($1.1.reference ?? .infinity) }
    }
}

extension String {
    func strippingHTML() -> String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
