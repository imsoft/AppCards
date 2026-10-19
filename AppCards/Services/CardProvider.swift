import Foundation

protocol CardProvider: Sendable {
    var game: Game { get }
    /// Búsqueda por texto con filtros. `query` puede ir vacío si hay al menos un filtro.
    func search(_ query: String, filters: SearchFilters) async throws -> [CardSummary]
    func filterOptions() async throws -> FilterOptions
    func detail(providerID: String) async throws -> CardDetail
    /// Todas las impresiones de la misma carta (incluida la recibida). Por defecto solo la propia.
    func printings(of detail: CardDetail) async throws -> [CardDetail]
}

extension CardProvider {
    func search(_ query: String) async throws -> [CardSummary] {
        try await search(query, filters: .none)
    }

    func printings(of detail: CardDetail) async throws -> [CardDetail] { [detail] }

    func cheapestPrinting(of detail: CardDetail, preferring currency: String = "USD") async throws -> (detail: CardDetail, quote: PriceQuote)? {
        let all = try await printings(of: detail)
        return PrintingPicker.cheapest(all, preferring: currency)
    }
}

enum ProviderError: LocalizedError {
    case notFound
    case badURL

    var errorDescription: String? {
        switch self {
        case .notFound: "No se encontró la carta."
        case .badURL: "URL inválida."
        }
    }
}
