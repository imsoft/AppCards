import Testing
import Foundation
@testable import AppCards

struct ExtendedFilterTests {
    @Test func scryfallBuildsExtendedQuery() {
        var f = SearchFilters()
        f.cardText = "draw a card"
        f.subtype = "Elf"
        f.format = FilterOption(id: "commander", title: "Commander")
        f.mechanic = FilterOption(id: "first strike", title: "First strike")
        f.minPower = 4
        f.priceMinUSD = 1
        f.priceMaxUSD = 10.5
        #expect(ScryfallQueryBuilder.query(text: "", filters: f)
                == #"o:"draw a card" t:Elf f:commander k:"first strike" pow>=4 usd>=1.00 usd<=10.50 game:paper"#)
    }

    @Test func tcgdexBuildsExtendedItems() {
        var f = SearchFilters()
        f.stage = FilterOption(id: "Basic", title: "Básico")
        f.mechanic = FilterOption(id: "ex", title: "ex")
        f.format = FilterOption(id: "standard", title: "Standard")
        f.minPower = 120
        let items = TCGdexProvider.queryItems(text: "pikachu", filters: f)
        let dict = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        #expect(dict["name"] == "like:pikachu")
        #expect(dict["stage"] == "eq:Basic")
        #expect(dict["suffix"] == "eq:ex")
        #expect(dict["legal.standard"] == "true")
        #expect(dict["hp"] == "gte:120")
    }

    @Test func chipsListAndRemoveActiveFilters() {
        var f = SearchFilters()
        #expect(f.chips.isEmpty)
        f.subtype = "Navy"
        f.minPower = 5000
        f.ownership = .missing
        f.priceMaxUSD = 3
        #expect(f.chips.map(\.key) == [.subtype, .power, .price, .ownership])
        #expect(!f.isEmpty)
        f.remove(.price)
        f.remove(.subtype)
        f.remove(.power)
        #expect(f.isEmpty) // "las que no tengo" no cuenta para buscar
        #expect(f.chips.map(\.key) == [.ownership])
    }

    @Test func priceRangeMatching() {
        var f = SearchFilters()
        #expect(f.priceMatches(nil))
        f.priceMinUSD = 2
        f.priceMaxUSD = 10
        #expect(f.priceMatches(5))
        #expect(!f.priceMatches(1))
        #expect(!f.priceMatches(11))
        #expect(!f.priceMatches(nil))
    }

    @Test func onePieceExtendedFilters() throws {
        let groups = try Fixtures.decode(TCGCSVResponse<TCGCSVGroup>.self, from: "tcgcsv_groups").results
        let products = try Fixtures.decode(TCGCSVResponse<TCGCSVProduct>.self, from: "tcgcsv_products").results
        let prices = try Fixtures.decode(TCGCSVResponse<TCGCSVPrice>.self, from: "tcgcsv_prices").results
        let catalog = OnePieceCatalog.build(groups: groups, products: products, prices: prices)

        var f = SearchFilters()
        f.cardText = "once per turn"
        #expect(catalog.search("", filters: f).allSatisfy { $0.number == "OP01-003" })
        #expect(!catalog.search("", filters: f).isEmpty)

        f = SearchFilters()
        f.priceMaxUSD = 6
        let cheap = catalog.search("", filters: f)
        #expect(!cheap.isEmpty)
        #expect(cheap.allSatisfy { (PrintingPicker.cheapestReference($0.prices) ?? 99) <= 6 })

        f = SearchFilters()
        f.subtype = "zzz no existe"
        #expect(catalog.search("", filters: f).isEmpty)
    }
}
