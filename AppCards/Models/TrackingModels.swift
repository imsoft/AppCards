import Foundation
import SwiftData

/// Un precio observado de una carta en una fecha. Máximo uno por carta, cotización y día.
@Model
final class PricePoint {
    var cardID: String = ""
    var gameRaw: String = Game.magic.rawValue
    var quoteID: String = ""
    var price: Double = 0
    var currency: String = "USD"
    var date: Date = Date()

    init(cardID: String, game: Game, quote: PriceQuote, price: Double, date: Date = .now) {
        self.cardID = cardID
        self.gameRaw = game.rawValue
        self.quoteID = quote.id
        self.price = price
        self.currency = quote.currency
        self.date = date
    }
}

@Model
final class WishlistItem {
    /// Identificador para sincronizar entre dispositivos (se asigna en la primera sincronización).
    var syncID: String = ""
    /// Huella de lo último que se sincronizó; si cambia, hay algo por subir.
    var lastSyncedHash: String = ""
    var cardID: String = ""
    var providerID: String = ""
    var gameRaw: String = Game.magic.rawValue
    var canonicalKey: String = ""
    var name: String = ""
    var setName: String = ""
    var number: String = ""
    var imageURLString: String?
    var quoteID: String = ""
    var variantTitle: String = ""
    /// Cuántas copias quieres de esta carta.
    var quantity: Int = 1

    /// Precio objetivo en `targetCurrency` (la moneda que mostrabas al crearlo). Nil = avisar con cualquier baja.
    var targetPrice: Double?
    var targetCurrency: String = "MXN"

    var lastPrice: Double?
    var lastCurrency: String = "USD"
    var previousPrice: Double?
    var lastCheckedAt: Date?
    var notifiedAt: Date?
    var addedAt: Date = Date()

    init(syncID: String) { self.syncID = syncID }

    init(card: CardSummary, quote: PriceQuote?, targetPrice: Double?, targetCurrency: String, quantity: Int = 1) {
        self.cardID = card.id
        self.providerID = card.providerID
        self.gameRaw = card.game.rawValue
        self.canonicalKey = card.canonicalKey
        self.name = card.name
        self.setName = card.setName
        self.number = card.number
        self.imageURLString = card.imageURL?.absoluteString ?? card.thumbnailURL?.absoluteString
        self.quoteID = quote?.id ?? ""
        self.variantTitle = quote?.title ?? ""
        self.targetPrice = targetPrice
        self.targetCurrency = targetCurrency
        self.quantity = max(1, quantity)
        self.lastPrice = quote?.reference
        self.lastCurrency = quote?.currency ?? "USD"
        self.lastCheckedAt = quote == nil ? nil : .now
        self.addedAt = .now
    }

    var game: Game { Game(rawValue: gameRaw) ?? .magic }
    /// Imagen para cuadrícula y filas, en buena resolución aunque se haya guardado una miniatura.
    var imageURL: URL? { ImageQuality.best(imageURLString.flatMap { URL(string: $0) }, size: .grid) }
    var fullImageURL: URL? { ImageQuality.best(imageURLString.flatMap { URL(string: $0) }, size: .full) }

    var artworkFallback: ArtworkFallback {
        ArtworkFallback(game: game, providerID: providerID, number: number, name: name)
    }

    /// Para abrir el perfil completo de la carta.
    var summary: CardSummary {
        CardSummary(game: game, providerID: providerID, name: name, setName: setName, number: number,
                    rarity: nil, thumbnailURL: imageURL, imageURL: fullImageURL, canonicalKey: canonicalKey)
    }
    var setLine: String { [setName, "#\(number)"].filter { !$0.isEmpty }.joined(separator: " · ") }

    func record(quote: PriceQuote) {
        previousPrice = lastPrice
        lastPrice = quote.reference
        lastCurrency = quote.currency
        quoteID = quote.id
        variantTitle = quote.title
        lastCheckedAt = .now
    }
}

/// Valor de la colección en un día.
@Model
final class CollectionSnapshot {
    var date: Date = Date()
    var currency: String = "MXN"
    var referenceValue: Double = 0
    var localValue: Double = 0
    var cardCount: Int = 0

    init(date: Date = .now, currency: String, referenceValue: Double, localValue: Double, cardCount: Int) {
        self.date = date
        self.currency = currency
        self.referenceValue = referenceValue
        self.localValue = localValue
        self.cardCount = cardCount
    }
}

// MARK: - Reglas puras (probadas en tests)

enum PriceTracking {
    /// ¿Ya hay un punto de este mismo día? Se guarda uno por día como máximo.
    static func hasPoint(on date: Date, in existing: [Date], calendar: Calendar = .current) -> Bool {
        existing.contains { calendar.isDate($0, inSameDayAs: date) }
    }

    /// Reduce una serie a como mucho `limit` puntos, conservando el primero y el último.
    static func downsample<T>(_ points: [T], limit: Int) -> [T] {
        guard points.count > limit, limit >= 2 else { return points }
        let step = Double(points.count - 1) / Double(limit - 1)
        return (0..<limit).map { points[Int((Double($0) * step).rounded())] }
    }

    static func change(from previous: Double?, to current: Double?) -> Double? {
        guard let previous, let current, previous > 0 else { return nil }
        return (current - previous) / previous
    }
}

enum WishlistRule {
    enum Status: Equatable {
        case reached          // precio actual <= objetivo
        case dropped(Double)  // bajó X (fracción) respecto a la revisión anterior, sin objetivo
        case waiting
        case unknown          // sin precio
    }

    /// `current` y `target` ya convertidos a la misma moneda.
    static func status(current: Double?, target: Double?, previous: Double?) -> Status {
        guard let current else { return .unknown }
        if let target { return current <= target ? .reached : .waiting }
        if let change = PriceTracking.change(from: previous, to: current), change <= -0.05 { return .dropped(change) }
        return .waiting
    }

    /// Solo avisa una vez por día por carta.
    static func shouldNotify(status: Status, lastNotified: Date?, now: Date = .now, calendar: Calendar = .current) -> Bool {
        switch status {
        case .reached, .dropped:
            guard let lastNotified else { return true }
            return !calendar.isDate(lastNotified, inSameDayAs: now)
        case .waiting, .unknown:
            return false
        }
    }
}
