import Testing
import Foundation
@testable import AppCards

struct WishlistQuantityTests {
    @Test func oldPayloadWithoutQuantityMeansOneCopy() throws {
        let json = #"{"addedAt":0,"cardID":"op-1","canonicalKey":"k","gameRaw":"onePiece","name":"Buggy","number":"OP02-058","providerID":"1","quoteID":"","setName":"OP02","targetCurrency":"MXN","variantTitle":""}"#
        let payload = try #require(SyncCoding.decode(WishlistItemPayload.self, from: json))
        let item = WishlistItem(syncID: "a")
        item.apply(payload)
        #expect(item.quantity == 1)
    }

    @Test func quantityRoundTripsThroughSync() throws {
        let item = WishlistItem(syncID: "a")
        item.quantity = 3
        let copy = WishlistItem(syncID: "b")
        copy.apply(try #require(SyncCoding.decode(WishlistItemPayload.self, from: SyncCoding.encode(item.syncPayload))))
        #expect(copy.quantity == 3)
    }

    @Test func oneCopyKeepsTheOldHash() {
        // Con una copia no se escribe el campo: los registros ya sincronizados no se vuelven a subir.
        let item = WishlistItem(syncID: "a")
        #expect(!SyncCoding.encode(item.syncPayload).contains("quantity"))
    }
}
