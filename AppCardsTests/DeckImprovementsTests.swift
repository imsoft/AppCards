import Testing
import Foundation
import SwiftUI
@testable import AppCards

private func card(_ name: String, set: String = "S", number: String = "1", game: Game = .onePiece) -> CardSummary {
    CardSummary(game: game, providerID: name, name: name, setName: set, number: number, rarity: nil,
                thumbnailURL: nil, imageURL: nil, canonicalKey: name)
}

private func quote(_ usd: Double) -> PriceQuote {
    PriceQuote(source: .tcgplayer, variant: "Normal", currency: "USD", market: usd, low: nil, mid: nil, high: nil)
}

struct DeckImprovementsTests {
    @Test func alternativesDoNotCountInDeckTotals() {
        let deck = Deck(name: "Luffy", game: .onePiece)
        let main = DeckEntry(card: card("Luffy"), quantity: 4, quote: quote(5))
        let option = DeckEntry(card: card("Zoro"), quantity: 2, quote: quote(100))
        option.isAlternative = true
        deck.entries = [main, option]

        #expect(deck.mainEntries.map(\.name) == ["Luffy"])
        #expect(deck.alternativeEntries.map(\.name) == ["Zoro"])
        #expect(deck.cardCount == 4)
        let converter = CurrencyConverter(rates: nil, manualUSDMXN: nil)
        let total = DeckMath.total(lines: deck.lines, in: "USD", converter: converter)
        #expect(total.amount == 20)
        #expect(total.totalCards == 4)
    }

    @Test func deckSortMissingFirstThenName() {
        let a = DeckEntry(card: card("Zoro"), quantity: 2, quote: quote(1)); a.ownedQuantity = 2
        let b = DeckEntry(card: card("Nami"), quantity: 2, quote: quote(9)); b.ownedQuantity = 0
        let c = DeckEntry(card: card("Ace"), quantity: 1, quote: quote(3)); c.ownedQuantity = 0
        #expect(DeckEntrySorter.sort([a, b, c], by: .missingFirst).map(\.name) == ["Ace", "Nami", "Zoro"])
        #expect(DeckEntrySorter.sort([a, b, c], by: .priceDesc).map(\.name) == ["Nami", "Ace", "Zoro"])
        #expect(DeckEntrySorter.sort([a, b, c], by: .name).map(\.name) == ["Ace", "Nami", "Zoro"])
    }

    @Test func collectionSortByValueAndQuantity() {
        let a = CollectionItem(card: card("A"), quantity: 1, quote: quote(10))
        let b = CollectionItem(card: card("B"), quantity: 5, quote: quote(1))
        let c = CollectionItem(card: card("C"), quantity: 2, quote: nil)
        let value: (CollectionItem) -> Double? = { item in item.referencePrice.map { $0 * Double(item.quantity) } }
        #expect(CollectionSorter.sort([a, b, c], by: .valueDesc, value: value).map(\.name) == ["A", "B", "C"])
        #expect(CollectionSorter.sort([a, b, c], by: .quantityDesc, value: value).map(\.name) == ["B", "C", "A"])
    }

    @Test func searchSortsByNameAndNumber() {
        let cards = [card("Charizard", number: "10"), card("abra", number: "2"), card("Blastoise", number: "9")]
        #expect(cards.sorted(by: .nameAsc).map(\.name) == ["abra", "Blastoise", "Charizard"])
        #expect(cards.sorted(by: .nameDesc).map(\.name) == ["Charizard", "Blastoise", "abra"])
        #expect(cards.sorted(by: .number).map(\.number) == ["2", "9", "10"])
    }

    @Test func sortOptionsDependOnGame() {
        var options = FilterOptions()
        options.supportsPriceSort = false
        #expect(!options.sorts.contains(.priceAsc))
        #expect(!options.sorts.contains(.newest))
        options.supportsPriceSort = true
        options.supportsDateSort = true
        #expect(options.sorts.contains(.priceDesc) && options.sorts.contains(.oldest))
    }

    @Test func hexColorsAndReadableText() {
        #expect(Color(hex: "#2F5BEA") != nil)
        #expect(Color(hex: "2F5BEA") != nil)
        #expect(Color(hex: "") == nil)
        #expect(Color(hex: "#XYZ") == nil)
        #expect(Color.white.readableForeground != .white)
        #expect(Color.black.readableForeground == .white)
    }

    @Test func olderSyncPayloadsStillDecode() {
        // Lo que ya estaba en Supabase antes de agregar color y opciones.
        let oldDeck = #"{"createdAt":1792343996152,"gameRaw":"magic","name":"Viejo"}"#
        let deck = SyncCoding.decode(DeckPayload.self, from: oldDeck)
        #expect(deck?.name == "Viejo")
        #expect(deck?.colorHex == nil)

        let oldEntry = #"{"canonicalKey":"k","cardID":"c","currency":"USD","deckID":"d","gameRaw":"magic","name":"N","number":"1","ownedQuantity":0,"providerID":"p","quantity":1,"quoteID":"q","setName":"S","variantTitle":"Normal"}"#
        let entry = SyncCoding.decode(DeckEntryPayload.self, from: oldEntry)
        #expect(entry?.isAlternative == nil)
        #expect(entry?.note == nil)
    }
}
