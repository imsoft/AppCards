import Testing
import Foundation
@testable import AppCards

struct DeckListParserTests {
    @Test func parsesCommonFormats() {
        let text = """
        // Mi deck
        Leader: 1xOP01-001
        4xOP01-003
        2 OP01-077
        OP01-003 x2
        3 Monkey.D.Luffy (OP01-003)
        2 Perona
        Characters
        st01-002 X1
        """
        let lines = DeckListParser.parse(text)
        #expect(lines.map(\.number) == ["OP01-001", "OP01-003", "OP01-077", nil, "ST01-002"])
        #expect(lines.map(\.quantity) == [1, 9, 2, 2, 1])
        #expect(lines[3].name == "Perona")
        #expect(lines[1].name == "Monkey.D.Luffy")
    }

    @Test func ignoresEmptyAndHeaderLines() {
        let lines = DeckListParser.parse("\n\nDeck\n# comentario\n\n")
        #expect(lines.isEmpty)
    }

    @Test func numberWithoutQuantityIsOne() {
        let lines = DeckListParser.parse("EB01-010")
        #expect(lines == [DeckListLine(raw: "EB01-010", quantity: 1, number: "EB01-010", name: nil)])
    }
}

struct SearchFilterTests {
    private func catalog() throws -> OnePieceCatalog {
        let groups = try Fixtures.decode(TCGCSVResponse<TCGCSVGroup>.self, from: "tcgcsv_groups").results
        let products = try Fixtures.decode(TCGCSVResponse<TCGCSVProduct>.self, from: "tcgcsv_products").results
        let prices = try Fixtures.decode(TCGCSVResponse<TCGCSVPrice>.self, from: "tcgcsv_prices").results
        return OnePieceCatalog.build(groups: groups, products: products, prices: prices)
    }

    @Test func onePieceFiltersBySetColorTypeAndParallel() throws {
        let catalog = try catalog()
        #expect(catalog.sets.map(\.name) == ["Romance Dawn"])

        var filters = SearchFilters()
        filters.cardSet = FilterOption(id: "3188", title: "Romance Dawn")
        #expect(catalog.search("", filters: filters).count == 6)

        filters.parallelOnly = true
        #expect(catalog.search("", filters: filters).map(\.number) == ["OP01-001", "OP01-003"])

        filters = SearchFilters()
        filters.color = FilterOption(id: "Blue", title: "Blue")
        #expect(catalog.search("", filters: filters).allSatisfy { $0.color?.contains("Blue") == true })

        filters = SearchFilters()
        filters.cardType = FilterOption(id: "Leader", title: "Leader")
        #expect(catalog.search("", filters: filters).allSatisfy { $0.cardType == "Leader" })

        // Sin texto ni filtros no se regresa el catálogo completo.
        #expect(catalog.search("", filters: .none).isEmpty)
    }

    @Test func onePieceSortsByPrice() throws {
        let catalog = try catalog()
        var filters = SearchFilters()
        filters.sort = .priceDesc
        let prices = catalog.search("luffy", filters: filters).map { PrintingPicker.cheapestReference($0.prices) ?? -1 }
        #expect(prices == prices.sorted(by: >))
        filters.sort = .priceAsc
        let asc = catalog.search("luffy", filters: filters).map { PrintingPicker.cheapestReference($0.prices) ?? .infinity }
        #expect(asc == asc.sorted())
    }

    @Test func scryfallQueryBuilder() {
        var filters = SearchFilters()
        filters.cardSet = FilterOption(id: "blb", title: "Bloomburrow")
        filters.color = FilterOption(id: "r", title: "Rojo")
        filters.cardType = FilterOption(id: "creature", title: "Creature")
        filters.cost = 7
        filters.rarity = FilterOption(id: "rare", title: "Rara")
        #expect(ScryfallQueryBuilder.query(text: " bolt ", filters: filters) == "bolt set:blb c:r t:creature mv>=7 r:rare game:paper")
        #expect(ScryfallQueryBuilder.query(text: "", filters: .none) == "game:paper")
    }

    @Test func summaryPriceSorting() {
        func card(_ name: String, _ price: Double?) -> CardSummary {
            CardSummary(game: .magic, providerID: name, name: name, setName: "", number: "", rarity: nil, thumbnailURL: nil, imageURL: nil, canonicalKey: name, price: price, priceCurrency: "USD")
        }
        let cards = [card("a", 5), card("b", nil), card("c", 1)]
        #expect(cards.sorted(by: .priceAsc).map(\.name) == ["c", "a", "b"])
        #expect(cards.sorted(by: .priceDesc).map(\.name) == ["a", "c", "b"])
        #expect(cards.sorted(by: .relevance).map(\.name) == ["a", "b", "c"])
    }
}
