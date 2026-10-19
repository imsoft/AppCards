import Testing
import Foundation
@testable import AppCards

private func summary(_ name: String, key: String, set: String = "S", number: String = "1") -> CardSummary {
    CardSummary(game: .onePiece, providerID: "\(key)-\(set)", name: name, setName: set, number: number,
                rarity: nil, thumbnailURL: nil, imageURL: nil, canonicalKey: key)
}

private func detail(_ s: CardSummary, quotes: [PriceQuote]) -> CardDetail {
    CardDetail(summary: s, attributes: [], text: nil, prices: quotes, externalURL: nil)
}

private func usd(_ v: Double, variant: String = "Normal") -> PriceQuote {
    PriceQuote(source: .tcgplayer, variant: variant, currency: "USD", market: v, low: nil, mid: nil, high: nil)
}

private func eur(_ v: Double) -> PriceQuote {
    PriceQuote(source: .cardmarket, variant: "Normal", currency: "EUR", market: v, low: nil, mid: nil, high: nil)
}

struct MissingCardsTests {
    private let converter = CurrencyConverter(rates: ExchangeRates(base: "USD", date: "d", rates: ["MXN": 20], fetchedAt: .now), manualUSDMXN: nil)

    @Test func ownedQuantityPerLineDrivesMissing() {
        let lines = [
            DeckLine(canonicalKey: "a", quantity: 4, ownedQuantity: 3, unitPrice: 10, currency: "USD"),
            DeckLine(canonicalKey: "b", quantity: 2, ownedQuantity: 2, unitPrice: 100, currency: "USD"),
            DeckLine(canonicalKey: "c", quantity: 1, ownedQuantity: 0, unitPrice: nil, currency: "USD"),
        ]
        let total = DeckMath.total(lines: lines, in: "USD", converter: converter)
        #expect(total.missingCards == 2)
        #expect(total.ownedCards == 5)
        #expect(total.missingAmount == 10)
        #expect(total.amount == 240)
        #expect(total.unpricedCards == 1)
    }

    @Test func collectionActsAsFloorForOwnedCount() {
        let lines = [DeckLine(canonicalKey: "a", quantity: 4, ownedQuantity: 1, unitPrice: 1, currency: "USD")]
        let total = DeckMath.total(lines: lines, owned: ["a": 3], in: "USD", converter: converter)
        #expect(total.ownedCards == 3)
        #expect(total.missingCards == 1)
        #expect(DeckMath.coveredByCollection(lines: lines, owned: ["a": 10]) == [4])
    }

    @Test func subtractsOwnedCopiesAcrossLines() {
        let lines = [
            DeckLine(canonicalKey: "OP01-003", quantity: 4, unitPrice: 5, currency: "USD"),
            DeckLine(canonicalKey: "OP01-003", quantity: 2, unitPrice: 1000, currency: "USD"), // paralela
            DeckLine(canonicalKey: "OP01-001", quantity: 1, unitPrice: 2, currency: "USD"),
        ]
        let missing = DeckMath.missingQuantities(lines: lines, owned: ["OP01-003": 5])
        #expect(missing == [0, 1, 1])

        let total = DeckMath.total(lines: lines, owned: ["OP01-003": 5], in: "MXN", converter: converter)
        #expect(total.amount == (20 + 2000 + 2) * 20)
        #expect(total.missingAmount == (1000 + 2) * 20)
        #expect(total.missingCards == 2)
        #expect(total.ownedCards == 5)
    }

    @Test func nothingOwnedMeansEverythingMissing() {
        let lines = [DeckLine(canonicalKey: "a", quantity: 3, unitPrice: 1, currency: "USD")]
        let total = DeckMath.total(lines: lines, in: "USD", converter: converter)
        #expect(total.missingAmount == total.amount)
        #expect(total.missingCards == 3)
    }
}

struct CollectionMathTests {
    private let converter = CurrencyConverter(rates: ExchangeRates(base: "USD", date: "d", rates: ["MXN": 20], fetchedAt: .now), manualUSDMXN: nil)

    @Test func ownedGroupsByCanonicalKey() {
        let lines = [
            CollectionLine(canonicalKey: "OP01-003", quantity: 2, referencePrice: nil, referenceCurrency: "USD", localPrice: nil, localCurrency: "MXN"),
            CollectionLine(canonicalKey: "OP01-003", quantity: 1, referencePrice: nil, referenceCurrency: "USD", localPrice: nil, localCurrency: "MXN"),
            CollectionLine(canonicalKey: "OP01-001", quantity: 4, referencePrice: nil, referenceCurrency: "USD", localPrice: nil, localCurrency: "MXN"),
        ]
        #expect(CollectionMath.owned(lines) == ["OP01-003": 3, "OP01-001": 4])
    }

    @Test func totalsReferenceAndLocalSeparately() {
        let lines = [
            CollectionLine(canonicalKey: "a", quantity: 2, referencePrice: 5, referenceCurrency: "USD", localPrice: 90, localCurrency: "MXN"),
            CollectionLine(canonicalKey: "b", quantity: 1, referencePrice: nil, referenceCurrency: "USD", localPrice: 30, localCurrency: "MXN"),
            CollectionLine(canonicalKey: "c", quantity: 3, referencePrice: 1, referenceCurrency: "USD", localPrice: nil, localCurrency: "MXN"),
        ]
        let total = CollectionMath.total(lines: lines, in: "MXN", converter: converter)
        #expect(total.totalCards == 6)
        #expect(total.referenceValue == 200 + 60)
        #expect(total.localValue == 180 + 30)
        #expect(total.cardsWithLocalPrice == 3)
    }
}

struct PrintingPickerTests {
    @Test func cheapestQuotePrefersUSD() {
        let d = detail(summary("x", key: "k"), quotes: [eur(0.5), usd(2), usd(1.5, variant: "Foil")])
        #expect(d.cheapestQuote()?.reference == 1.5)
        #expect(d.cheapestQuote(preferring: "EUR")?.reference == 0.5)
    }

    @Test func picksCheapestPrintingAcrossSets() {
        let base = detail(summary("Luffy", key: "OP01-003", set: "Romance Dawn"), quotes: [usd(5)])
        let parallel = detail(summary("Luffy (Parallel)", key: "OP01-003", set: "Romance Dawn"), quotes: [usd(1023, variant: "Foil")])
        let reprint = detail(summary("Luffy", key: "OP01-003", set: "Starter"), quotes: [usd(0.8)])
        let unpriced = detail(summary("Luffy", key: "OP01-003", set: "Promo"), quotes: [])
        let picked = PrintingPicker.cheapest([parallel, base, unpriced, reprint])
        #expect(picked?.detail.summary.setName == "Starter")
        #expect(picked?.quote.reference == 0.8)
        #expect(PrintingPicker.cheapest([unpriced]) == nil)
    }

    @Test func onePieceCatalogGroupsPrintingsByNumber() throws {
        let groups = try Fixtures.decode(TCGCSVResponse<TCGCSVGroup>.self, from: "tcgcsv_groups").results
        let products = try Fixtures.decode(TCGCSVResponse<TCGCSVProduct>.self, from: "tcgcsv_products").results
        let prices = try Fixtures.decode(TCGCSVResponse<TCGCSVPrice>.self, from: "tcgcsv_prices").results
        let catalog = OnePieceCatalog.build(groups: groups, products: products, prices: prices)

        let printings = catalog.printings(number: "op01-003").map(OnePieceCatalog.detail)
        #expect(printings.count == 2)
        let cheapest = PrintingPicker.cheapest(printings)
        #expect(cheapest?.detail.summary.name == "Monkey.D.Luffy (003)")
        #expect(cheapest?.quote.reference == 5.01)
        #expect(printings.allSatisfy { $0.summary.canonicalKey == "OP01-003" })
    }
}
