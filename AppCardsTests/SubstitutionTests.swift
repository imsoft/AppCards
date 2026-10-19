import Testing
import Foundation
@testable import AppCards

private func entry(_ name: String, usd: Double?, qty: Int = 1) -> DeckEntry {
    let card = CardSummary(game: .onePiece, providerID: name, name: name, setName: "S", number: "1", rarity: nil,
                           thumbnailURL: nil, imageURL: nil, canonicalKey: name)
    let quote = usd.map { PriceQuote(source: .tcgplayer, variant: "Normal", currency: "USD", market: $0, low: nil, mid: nil, high: nil) }
    return DeckEntry(card: card, quantity: qty, quote: quote)
}

struct SubstitutionTests {
    @Test func linkAndFindTarget() {
        let luffy = entry("Luffy", usd: 5)
        let ace = entry("Ace", usd: 8)
        DeckSubstitution.link(ace, to: luffy)
        let all = [luffy, ace]
        #expect(ace.isAlternative)
        #expect(!luffy.syncID.isEmpty)
        #expect(DeckSubstitution.target(of: ace, in: all) === luffy)
        #expect(DeckSubstitution.substitutes(for: luffy, in: all).map(\.name) == ["Ace"])

        DeckSubstitution.link(ace, to: nil)
        #expect(DeckSubstitution.target(of: ace, in: all) == nil)
        #expect(ace.isAlternative)
    }

    @Test func swapIsReversible() {
        let luffy = entry("Luffy", usd: 5)
        let ace = entry("Ace", usd: 8)
        DeckSubstitution.link(ace, to: luffy)
        let all = [luffy, ace]

        let out = DeckSubstitution.swap(ace, in: all)
        #expect(out === luffy)
        #expect(!ace.isAlternative && ace.replacesID.isEmpty)
        #expect(luffy.isAlternative)
        #expect(DeckSubstitution.target(of: luffy, in: all) === ace)

        // Hacer el cambio de nuevo lo deshace.
        DeckSubstitution.swap(luffy, in: all)
        #expect(!luffy.isAlternative)
        #expect(DeckSubstitution.target(of: ace, in: all) === luffy)
    }

    @Test func otherOptionsFollowTheNewCard() {
        let luffy = entry("Luffy", usd: 5)
        let ace = entry("Ace", usd: 8)
        let sabo = entry("Sabo", usd: 3)
        DeckSubstitution.link(ace, to: luffy)
        DeckSubstitution.link(sabo, to: luffy)
        let all = [luffy, ace, sabo]
        DeckSubstitution.swap(ace, in: all)
        #expect(DeckSubstitution.target(of: sabo, in: all) === ace)
    }

    @Test func costDifferenceUsesQuantities() {
        let luffy = entry("Luffy", usd: 5, qty: 4)   // 20
        let ace = entry("Ace", usd: 8, qty: 2)       // 16
        let same: (Double, String) -> Double? = { amount, _ in amount }
        #expect(DeckSubstitution.costDifference(option: ace, target: luffy, convert: same) == -4)
        #expect(DeckSubstitution.costDifference(option: entry("X", usd: nil), target: luffy, convert: same) == nil)
    }

    @Test func swapWithoutLinkDoesNothing() {
        let a = entry("A", usd: 1)
        a.isAlternative = true
        #expect(DeckSubstitution.swap(a, in: [a]) == nil)
        #expect(a.isAlternative)
    }
}
