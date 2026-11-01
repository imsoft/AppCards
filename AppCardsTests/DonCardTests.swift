import Testing
import Foundation
@testable import AppCards

struct DonCardTests {
    /// Así vienen las DON!! en TCGplayer: sin número y con tipo "DON!!".
    private func catalog() throws -> OnePieceCatalog {
        let json = #"""
        {"results": [
          {"productId": 1, "name": "DON!! Card (Alternate Art) (Gold)", "groupId": 3188, "imageUrl": null, "url": null,
           "extendedData": [{"name": "Rarity", "value": "DON!!"}, {"name": "CardType", "value": "DON!!"}]},
          {"productId": 2, "name": "DON!! Card", "groupId": 3188, "imageUrl": null, "url": null,
           "extendedData": [{"name": "Rarity", "value": "DON!!"}, {"name": "CardType", "value": "DON!!"}]},
          {"productId": 3, "name": "Booster Box", "groupId": 3188, "imageUrl": null, "url": null, "extendedData": []}
        ]}
        """#
        let products = try JSONDecoder().decode(TCGCSVResponse<TCGCSVProduct>.self, from: Data(json.utf8)).results
        let groups = try Fixtures.decode(TCGCSVResponse<TCGCSVGroup>.self, from: "tcgcsv_groups").results
        return OnePieceCatalog.build(groups: groups, products: products, prices: [])
    }

    @Test func donCardsAreIncludedButSealedProductIsNot() throws {
        let catalog = try catalog()
        #expect(catalog.entries.map(\.id).sorted() == [1, 2])
        #expect(catalog.entries.allSatisfy { $0.number == "DON" })
    }

    @Test func searchingDonFindsThem() throws {
        let catalog = try catalog()
        #expect(catalog.search("don").count == 2)
        #expect(catalog.search("DON!!").count == 2)
        #expect(catalog.printings(number: "DON").count == 2)
    }

    @Test func donIsACardTypeFilter() throws {
        var filters = SearchFilters()
        filters.cardType = FilterOption(id: "DON!!", title: "DON!!")
        #expect(try catalog().search("", filters: filters).count == 2)
    }
}
