import Testing
import Foundation
@testable import AppCards

struct OnePieceCatalogTests {
    private func makeCatalog() throws -> OnePieceCatalog {
        let groups = try Fixtures.decode(TCGCSVResponse<TCGCSVGroup>.self, from: "tcgcsv_groups").results
        let products = try Fixtures.decode(TCGCSVResponse<TCGCSVProduct>.self, from: "tcgcsv_products").results
        let prices = try Fixtures.decode(TCGCSVResponse<TCGCSVPrice>.self, from: "tcgcsv_prices").results
        return OnePieceCatalog.build(groups: groups, products: products, prices: prices)
    }

    @Test func excludesSealedProducts() throws {
        let catalog = try makeCatalog()
        #expect(catalog.entries.count == 6)
        #expect(!catalog.entries.contains { $0.name.contains("Booster") })
    }

    @Test func searchByNameIgnoresPunctuation() throws {
        let catalog = try makeCatalog()
        let results = catalog.search("monkey d luffy")
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.number == "OP01-003" })
        // La impresión base va antes que la paralela por orden alfabético del nombre.
        #expect(results.first?.name == "Monkey.D.Luffy (003)")
    }

    @Test func searchByNumber() throws {
        let catalog = try makeCatalog()
        #expect(catalog.search("OP01-077").map(\.name).sorted() == ["Perona", "Perona (Box Topper)"])
        #expect(catalog.search("op01").count == 6)
        #expect(catalog.search("zzz").isEmpty)
    }

    @Test func detailHasAttributesPricesAndCleanText() throws {
        let catalog = try makeCatalog()
        let luffy = try #require(catalog.entry(id: 453506))
        let detail = OnePieceCatalog.detail(luffy)

        #expect(detail.summary.setName == "Romance Dawn")
        #expect(detail.summary.imageURL?.absoluteString == "https://product-images.tcgplayer.com/fit-in/1000x1000/453506.jpg")
        #expect(detail.attributes.contains { $0.label == "Número" && $0.value == "OP01-003" })
        #expect(detail.attributes.contains { $0.label == "Rareza" && $0.value == "L" })
        #expect(detail.text?.contains("<em>") == false)
        #expect(detail.text?.contains("Once Per Turn") == true)

        let quote = try #require(detail.prices.first)
        #expect(quote.source == .tcgplayer)
        #expect(quote.variant == "Foil")
        #expect(quote.currency == "USD")
        #expect(quote.market == 1023.34)
    }

    @Test func catalogRoundTripsThroughJSON() throws {
        let catalog = try makeCatalog()
        let data = try JSONEncoder().encode(catalog)
        let decoded = try JSONDecoder().decode(OnePieceCatalog.self, from: data)
        #expect(decoded.entries.count == catalog.entries.count)
        #expect(decoded.isFresh(maxAge: 60))
    }
}
