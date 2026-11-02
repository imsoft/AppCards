import Foundation

/// TCGdex no manda precios en la lista de resultados: se piden al detalle de cada carta conforme aparece en pantalla.
@MainActor
@Observable
final class SearchPriceBackfill {
    struct Price: Equatable {
        let amount: Double
        let currency: String
    }

    /// Precio encontrado por `CardSummary.id`.
    private(set) var prices: [String: Price] = [:]
    @ObservationIgnored private var requested: Set<String> = []
    @ObservationIgnored private let limiter = ConcurrencyLimiter(limit: 6)

    func price(for card: CardSummary) -> Price? { prices[card.id] }

    /// Pide el precio si la carta no trae uno. Si la carta sale de pantalla antes, se cancela y se vuelve a pedir después.
    func load(_ card: CardSummary, using provider: any CardProvider) async {
        guard card.price == nil, prices[card.id] == nil, !requested.contains(card.id) else { return }
        requested.insert(card.id)
        await limiter.acquire()
        defer { Task { await limiter.release() } }
        guard !Task.isCancelled,
              let detail = try? await provider.detail(providerID: card.providerID) else {
            requested.remove(card.id)
            return
        }
        // Se queda en `requested` aunque no tenga precio: así no se vuelve a preguntar.
        // TCGdex a veces manda 0 cuando no hay ventas: eso no es un precio.
        let quotes = detail.pricedQuotes.filter { ($0.reference ?? 0) > 0 }
        let pool = quotes.contains { $0.currency == "USD" } ? quotes.filter { $0.currency == "USD" } : quotes
        if let quote = pool.min(by: { ($0.reference ?? .infinity) < ($1.reference ?? .infinity) }), let amount = quote.reference {
            prices[card.id] = Price(amount: amount, currency: quote.currency)
        }
    }
}

/// Deja pasar a lo más `limit` tareas a la vez.
actor ConcurrencyLimiter {
    private let limit: Int
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { self.limit = limit }

    func acquire() async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    func release() {
        if waiting.isEmpty {
            running -= 1
        } else {
            waiting.removeFirst().resume()
        }
    }
}
