import Testing
import Foundation
@testable import AppCards

struct CurrencyConverterTests {
    private let rates = ExchangeRates(base: "USD", date: "2026-10-16", rates: ["MXN": 18.0, "EUR": 0.9], fetchedAt: .now)

    @Test func convertsThroughUSD() {
        let converter = CurrencyConverter(rates: rates, manualUSDMXN: nil)
        #expect(converter.convert(10, from: "USD", to: "MXN") == 180)
        #expect(converter.convert(9, from: "EUR", to: "USD") == 10)
        #expect(converter.convert(9, from: "EUR", to: "MXN") == 180)
        #expect(converter.convert(5, from: "MXN", to: "MXN") == 5)
    }

    @Test func manualRateOverridesMXNOnly() {
        let converter = CurrencyConverter(rates: rates, manualUSDMXN: 20)
        #expect(converter.convert(1, from: "USD", to: "MXN") == 20)
        #expect(converter.convert(1, from: "USD", to: "EUR") == 0.9)
    }

    @Test func unknownCurrencyReturnsNil() {
        let converter = CurrencyConverter(rates: nil, manualUSDMXN: nil)
        #expect(converter.convert(1, from: "USD", to: "MXN") == nil)
        #expect(converter.convert(1, from: "USD", to: "USD") == 1)
    }
}

struct DeckMathTests {
    private let converter = CurrencyConverter(
        rates: ExchangeRates(base: "USD", date: "2026-10-16", rates: ["MXN": 20.0, "EUR": 0.8], fetchedAt: .now),
        manualUSDMXN: nil
    )

    @Test func sumsQuantitiesAndConverts() {
        let lines = [
            DeckLine(quantity: 4, unitPrice: 1.5, currency: "USD"),   // 6 USD  = 120 MXN
            DeckLine(quantity: 1, unitPrice: 8, currency: "EUR"),     // 10 USD = 200 MXN
            DeckLine(quantity: 2, unitPrice: nil, currency: "USD"),   // sin precio
        ]
        let total = DeckMath.total(lines: lines, in: "MXN", converter: converter)
        #expect(total.amount == 320)
        #expect(total.currency == "MXN")
        #expect(total.totalCards == 7)
        #expect(total.unpricedCards == 2)
    }

    @Test func missingRateCountsAsUnpriced() {
        let lines = [DeckLine(quantity: 3, unitPrice: 2, currency: "GBP")]
        let total = DeckMath.total(lines: lines, in: "MXN", converter: converter)
        #expect(total.amount == 0)
        #expect(total.unpricedCards == 3)
    }

    @Test func emptyDeckIsZero() {
        let total = DeckMath.total(lines: [], in: "USD", converter: converter)
        #expect(total == DeckTotal(amount: 0, currency: "USD", totalCards: 0, unpricedCards: 0, missingAmount: 0, missingCards: 0, ownedCards: 0))
    }
}

struct StoreMarkupTests {
    @Test func storePriceAndMarkupAmount() {
        #expect(StoreMarkup.storePrice(100, percent: 25) == 125)
        #expect(StoreMarkup.markupAmount(100, percent: 25) == 25)
        #expect(StoreMarkup.storePrice(80, percent: 0) == 80)
    }

    @Test func percentAboveMarket() {
        #expect(StoreMarkup.percentAbove(market: 100, quoted: 120) == 20)
        #expect(StoreMarkup.percentAbove(market: 100, quoted: 90) == -10)
        #expect(StoreMarkup.percentAbove(market: 0, quoted: 50) == nil)
    }
}
