import Testing
import Foundation
@testable import AppCards

struct TCGdexTests {
    @Test func decodesDynamicPricing() throws {
        let card = try Fixtures.decode(TCGdexCard.self, from: "tcgdex_card")
        let pricing = try #require(card.pricing)

        #expect(card.name == "Furret")
        #expect(card.set?.name == "Darkness Ablaze")
        #expect(pricing.tcgplayerUnit == "USD")
        #expect(pricing.tcgplayerVariants["normal"]?.marketPrice == 0.27)
        #expect(pricing.tcgplayerVariants["reverse-holofoil"] != nil)
        #expect(pricing.cardmarketUnit == "EUR")
        #expect(pricing.cardmarketValues["trend"] == 0.04)
        #expect(pricing.cardmarketValues["idProduct"] == nil)
    }

    @Test func mapsQuotesForBothSources() throws {
        let card = try Fixtures.decode(TCGdexCard.self, from: "tcgdex_card")
        let quotes = TCGdexMapper.quotes(card.pricing)

        let normal = try #require(quotes.first { $0.source == .tcgplayer && $0.variant == "Normal" })
        #expect(normal.market == 0.27)
        #expect(normal.low == 0.02)
        #expect(normal.currency == "USD")

        let reverse = try #require(quotes.first { $0.source == .tcgplayer && $0.variant == "Reverse Holofoil" })
        #expect(reverse.low == 0.17)

        let cmNormal = try #require(quotes.first { $0.source == .cardmarket && $0.variant == "Normal" })
        #expect(cmNormal.market == 0.04)   // trend
        #expect(cmNormal.mid == 0.07)      // avg
        #expect(cmNormal.low == 0.02)

        let cmHolo = try #require(quotes.first { $0.source == .cardmarket && $0.variant == "Holo" })
        #expect(cmHolo.market == 0.26)
        #expect(cmHolo.currency == "EUR")

        // avg1 / avg7 / avg30 no deben generar variantes.
        #expect(!quotes.contains { $0.variant.hasPrefix("Avg") })
    }

    @Test func imageURLsAndSetCode() {
        let brief = TCGdexBrief(id: "swsh3-136", localId: "136", name: "Furret", image: "https://assets.tcgdex.net/en/swsh/swsh3/136")
        let summary = TCGdexMapper.summary(brief)

        #expect(summary.thumbnailURL?.absoluteString == "https://assets.tcgdex.net/en/swsh/swsh3/136/high.webp")
        #expect(summary.imageURL?.absoluteString == "https://assets.tcgdex.net/en/swsh/swsh3/136/high.webp")
        #expect(summary.setName == "SWSH3")
        #expect(summary.number == "136")
    }
}
