import Foundation
import SwiftData

@Model
final class CollectionItem {
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
    var quantity: Int = 1

    // Precio de referencia (TCGplayer / Cardmarket) de esta impresión.
    var referencePrice: Double?
    var referenceCurrency: String = "USD"
    var referenceQuoteID: String = ""
    var referenceVariant: String = ""
    var priceUpdatedAt: Date?

    // Lo que de verdad pagaste o te cotizaron aquí.
    var localPrice: Double?
    var localCurrency: String = "MXN"
    var store: String = ""
    var localPriceDate: Date?

    var addedAt: Date = Date()

    init(syncID: String) { self.syncID = syncID }

    init(card: CardSummary, quantity: Int = 1, quote: PriceQuote?) {
        self.cardID = card.id
        self.providerID = card.providerID
        self.gameRaw = card.game.rawValue
        self.canonicalKey = card.canonicalKey
        self.name = card.name
        self.setName = card.setName
        self.number = card.number
        self.imageURLString = card.imageURL?.absoluteString ?? card.thumbnailURL?.absoluteString
        self.quantity = quantity
        self.addedAt = .now
        if let quote { apply(quote: quote) }
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

    func apply(quote: PriceQuote) {
        referencePrice = quote.reference
        referenceCurrency = quote.currency
        referenceQuoteID = quote.id
        referenceVariant = quote.title
        priceUpdatedAt = .now
    }

    var line: CollectionLine {
        CollectionLine(
            canonicalKey: canonicalKey,
            quantity: quantity,
            referencePrice: referencePrice,
            referenceCurrency: referenceCurrency,
            localPrice: localPrice,
            localCurrency: localCurrency
        )
    }
}

struct CollectionLine: Sendable, Equatable {
    let canonicalKey: String
    let quantity: Int
    let referencePrice: Double?
    let referenceCurrency: String
    let localPrice: Double?
    let localCurrency: String
}

struct CollectionTotal: Equatable, Sendable {
    let currency: String
    let totalCards: Int
    /// Valor a precio de mercado (referencia), solo cartas con precio.
    let referenceValue: Double
    /// Suma de lo que pagaste (precio local × cantidad), solo cartas con precio local.
    let localValue: Double
    let cardsWithLocalPrice: Int
}

enum CollectionMath {
    static func owned(_ lines: [CollectionLine]) -> [String: Int] {
        lines.reduce(into: [:]) { $0[$1.canonicalKey, default: 0] += $1.quantity }
    }

    static func total(lines: [CollectionLine], in currency: String, converter: CurrencyConverter) -> CollectionTotal {
        var reference = 0.0
        var local = 0.0
        var withLocal = 0
        var cards = 0
        for line in lines {
            cards += line.quantity
            if let price = line.referencePrice, let converted = converter.convert(price, from: line.referenceCurrency, to: currency) {
                reference += converted * Double(line.quantity)
            }
            if let price = line.localPrice, let converted = converter.convert(price, from: line.localCurrency, to: currency) {
                local += converted * Double(line.quantity)
                withLocal += line.quantity
            }
        }
        return CollectionTotal(currency: currency, totalCards: cards, referenceValue: reference, localValue: local, cardsWithLocalPrice: withLocal)
    }
}
