import Foundation
import CryptoKit

/// Tipos de dato que se sincronizan. El historial de precios y las fotos de valor se quedan en cada dispositivo.
enum SyncKind: String, CaseIterable, Codable, Sendable {
    case deck
    case deckEntry
    case collectionItem
    case wishlistItem

    /// Orden para aplicar lo que llega: primero los decks, para que las cartas de deck encuentren a su deck.
    static let applyOrder: [SyncKind] = [.deck, .deckEntry, .collectionItem, .wishlistItem]
}

enum SyncCoding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()

    static func encode<T: Encodable>(_ value: T) -> String {
        (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    static func decode<T: Decodable>(_ type: T.Type, from json: String) -> T? {
        try? decoder.decode(T.self, from: Data(json.utf8))
    }

    /// Huella estable de un payload: si no cambia, no hay nada que subir.
    static func hash(_ json: String) -> String {
        SHA256.hash(data: Data(json.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Payloads
// Solo lo que decide el usuario. Los precios que se refrescan solos cada día no viajan: cada dispositivo los actualiza.

struct DeckPayload: Codable, Equatable, Sendable {
    var name: String
    var gameRaw: String
    var createdAt: Date
    var colorHex: String? = nil
}

struct DeckEntryPayload: Codable, Equatable, Sendable {
    var deckID: String
    var cardID: String
    var providerID: String
    var gameRaw: String
    var canonicalKey: String
    var name: String
    var setName: String
    var number: String
    var imageURLString: String?
    var quantity: Int
    var ownedQuantity: Int
    var quoteID: String
    var variantTitle: String
    var unitPrice: Double?
    var currency: String
    var isAlternative: Bool? = nil
    var note: String? = nil
    var replacesID: String? = nil
}

struct CollectionItemPayload: Codable, Equatable, Sendable {
    var cardID: String
    var providerID: String
    var gameRaw: String
    var canonicalKey: String
    var name: String
    var setName: String
    var number: String
    var imageURLString: String?
    var quantity: Int
    var referenceQuoteID: String
    var referenceVariant: String
    var localPrice: Double?
    var localCurrency: String
    var store: String
    var localPriceDate: Date?
    var addedAt: Date
}

struct WishlistItemPayload: Codable, Equatable, Sendable {
    var cardID: String
    var providerID: String
    var gameRaw: String
    var canonicalKey: String
    var name: String
    var setName: String
    var number: String
    var imageURLString: String?
    var quoteID: String
    var variantTitle: String
    var targetPrice: Double?
    var targetCurrency: String
    var addedAt: Date
    /// Opcional para leer registros guardados antes de que existiera.
    var quantity: Int? = nil
}

// MARK: - Modelos ↔ payloads

extension Deck {
    var syncPayload: DeckPayload { DeckPayload(name: name, gameRaw: gameRaw, createdAt: createdAt, colorHex: colorHex.isEmpty ? nil : colorHex) }
    func apply(_ p: DeckPayload) {
        name = p.name; gameRaw = p.gameRaw; createdAt = p.createdAt; colorHex = p.colorHex ?? ""
    }
}

extension DeckEntry {
    var syncPayload: DeckEntryPayload {
        DeckEntryPayload(deckID: deck?.syncID ?? "", cardID: cardID, providerID: providerID, gameRaw: gameRaw,
                         canonicalKey: canonicalKey, name: name, setName: setName, number: number,
                         imageURLString: imageURLString, quantity: quantity, ownedQuantity: ownedQuantity,
                         quoteID: quoteID, variantTitle: variantTitle, unitPrice: unitPrice, currency: currency,
                         isAlternative: isAlternative ? true : nil, note: note.isEmpty ? nil : note,
                         replacesID: replacesID.isEmpty ? nil : replacesID)
    }
    func apply(_ p: DeckEntryPayload) {
        cardID = p.cardID; providerID = p.providerID; gameRaw = p.gameRaw; canonicalKey = p.canonicalKey
        name = p.name; setName = p.setName; number = p.number; imageURLString = p.imageURLString
        quantity = p.quantity; ownedQuantity = p.ownedQuantity; quoteID = p.quoteID
        variantTitle = p.variantTitle; unitPrice = p.unitPrice; currency = p.currency
        isAlternative = p.isAlternative ?? false; note = p.note ?? ""; replacesID = p.replacesID ?? ""
    }
}

extension CollectionItem {
    var syncPayload: CollectionItemPayload {
        CollectionItemPayload(cardID: cardID, providerID: providerID, gameRaw: gameRaw, canonicalKey: canonicalKey,
                              name: name, setName: setName, number: number, imageURLString: imageURLString,
                              quantity: quantity, referenceQuoteID: referenceQuoteID, referenceVariant: referenceVariant,
                              localPrice: localPrice, localCurrency: localCurrency, store: store,
                              localPriceDate: localPriceDate, addedAt: addedAt)
    }
    func apply(_ p: CollectionItemPayload) {
        cardID = p.cardID; providerID = p.providerID; gameRaw = p.gameRaw; canonicalKey = p.canonicalKey
        name = p.name; setName = p.setName; number = p.number; imageURLString = p.imageURLString
        quantity = p.quantity; referenceQuoteID = p.referenceQuoteID; referenceVariant = p.referenceVariant
        localPrice = p.localPrice; localCurrency = p.localCurrency; store = p.store
        localPriceDate = p.localPriceDate; addedAt = p.addedAt
    }
}

extension WishlistItem {
    var syncPayload: WishlistItemPayload {
        WishlistItemPayload(cardID: cardID, providerID: providerID, gameRaw: gameRaw, canonicalKey: canonicalKey,
                            name: name, setName: setName, number: number, imageURLString: imageURLString,
                            quoteID: quoteID, variantTitle: variantTitle, targetPrice: targetPrice,
                            targetCurrency: targetCurrency, addedAt: addedAt, quantity: quantity == 1 ? nil : quantity)
    }
    func apply(_ p: WishlistItemPayload) {
        cardID = p.cardID; providerID = p.providerID; gameRaw = p.gameRaw; canonicalKey = p.canonicalKey
        name = p.name; setName = p.setName; number = p.number; imageURLString = p.imageURLString
        quoteID = p.quoteID; variantTitle = p.variantTitle; targetPrice = p.targetPrice
        targetCurrency = p.targetCurrency; addedAt = p.addedAt; quantity = max(1, p.quantity ?? 1)
    }
}
