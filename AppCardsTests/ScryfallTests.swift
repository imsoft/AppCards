import Testing
import Foundation
@testable import AppCards

struct ScryfallTests {
    @Test func decodesCardAndMapsSummary() throws {
        let card = try Fixtures.decode(ScryfallCard.self, from: "scryfall_card", decoder: ScryfallMapper.decoder)
        let summary = ScryfallMapper.summary(card)

        #expect(summary.game == .magic)
        #expect(summary.name == "Lightning Bolt")
        #expect(summary.setName.contains("(MSC)"))
        #expect(summary.providerID == card.id)
        #expect(summary.thumbnailURL != nil)
        #expect(summary.imageURL != nil)
    }

    @Test func mapsUSDToTCGplayerAndEURToCardmarket() throws {
        let card = try Fixtures.decode(ScryfallCard.self, from: "scryfall_card", decoder: ScryfallMapper.decoder)
        let quotes = ScryfallMapper.quotes(card.prices)

        let usd = try #require(quotes.first { $0.source == .tcgplayer && $0.variant == "Normal" })
        #expect(usd.currency == "USD")
        #expect(usd.market == Double(card.prices.usd ?? ""))

        let eur = try #require(quotes.first { $0.source == .cardmarket && $0.variant == "Normal" })
        #expect(eur.currency == "EUR")
        #expect(eur.market == Double(card.prices.eur ?? ""))

        // Sin precio etched no debe aparecer una cotización vacía.
        #expect(!quotes.contains { $0.variant == "Etched" })
    }

    @Test func detailIncludesOracleTextAndLink() throws {
        let card = try Fixtures.decode(ScryfallCard.self, from: "scryfall_card", decoder: ScryfallMapper.decoder)
        let detail = ScryfallMapper.detail(card)

        #expect(detail.text?.contains("3 damage") == true)
        #expect(detail.externalURL?.host?.contains("scryfall.com") == true)
        #expect(detail.attributes.contains { $0.label == "Tipo" && $0.value == "Instant" })
    }
}
