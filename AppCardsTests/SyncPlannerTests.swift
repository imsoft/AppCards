import Testing
import Foundation
@testable import AppCards

struct SyncPlannerTests {
    private func local(_ id: String, _ payload: String, synced: String?) -> SyncPlanner.LocalRecord {
        .init(id: id, payload: payload, lastSyncedHash: synced.map(SyncCoding.hash) ?? "")
    }

    @Test func newRemoteRecordIsApplied() {
        let actions = SyncPlanner.plan(remote: [.init(id: "a", payload: #"{"x":1}"#, deleted: false)], local: [:])
        #expect(actions == [.apply(id: "a", payload: #"{"x":1}"#)])
    }

    @Test func ownEchoIsSkipped() {
        let payload = #"{"x":1}"#
        let actions = SyncPlanner.plan(remote: [.init(id: "a", payload: payload, deleted: false)],
                                       local: ["a": local("a", payload, synced: payload)])
        #expect(actions == [.skip(id: "a")])
    }

    @Test func remoteChangeAppliesWhenLocalIsClean() {
        let actions = SyncPlanner.plan(remote: [.init(id: "a", payload: #"{"x":2}"#, deleted: false)],
                                       local: ["a": local("a", #"{"x":1}"#, synced: #"{"x":1}"#)])
        #expect(actions == [.apply(id: "a", payload: #"{"x":2}"#)])
    }

    @Test func localUnsyncedChangeWins() {
        let actions = SyncPlanner.plan(remote: [.init(id: "a", payload: #"{"x":2}"#, deleted: false)],
                                       local: ["a": local("a", #"{"x":3}"#, synced: #"{"x":1}"#)])
        #expect(actions == [.skip(id: "a")])
    }

    @Test func remoteDeletionRemovesCleanLocal() {
        let actions = SyncPlanner.plan(remote: [.init(id: "a", payload: "{}", deleted: true)],
                                       local: ["a": local("a", #"{"x":1}"#, synced: #"{"x":1}"#)])
        #expect(actions == [.deleteLocal(id: "a")])
        #expect(SyncPlanner.plan(remote: [.init(id: "b", payload: "{}", deleted: true)], local: [:]) == [.skip(id: "b")])
    }

    @Test func pushesDirtyRecordsAndDeletions() {
        let records = [
            local("a", #"{"x":1}"#, synced: #"{"x":1}"#),
            local("b", #"{"x":2}"#, synced: nil),
            local("c", #"{"x":3}"#, synced: #"{"x":0}"#),
        ]
        let plan = SyncPlanner.pushes(local: records, knownIDs: ["a", "c", "gone"])
        #expect(plan.upserts.map(\.id) == ["b", "c"])
        #expect(plan.deletions == ["gone"])
    }

    @Test func payloadEncodingIsStableForHashing() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let a = DeckPayload(name: "Luffy", gameRaw: "onePiece", createdAt: date)
        let encoded = SyncCoding.encode(a)
        #expect(encoded == SyncCoding.encode(a))
        #expect(SyncCoding.decode(DeckPayload.self, from: encoded) == a)
        #expect(SyncCoding.hash(encoded) == SyncCoding.hash(SyncCoding.encode(a)))
        #expect(SyncCoding.hash(encoded) != SyncCoding.hash(SyncCoding.encode(DeckPayload(name: "Zoro", gameRaw: "onePiece", createdAt: date))))
    }
}
