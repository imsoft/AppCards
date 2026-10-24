import Testing
@testable import AppCards

struct DeckShareTests {
    @Test func onePieceShowsCardNumber() {
        #expect(DeckShareCard.code(game: .onePiece, setName: "Romance Dawn", number: "OP01-016") == "OP01-016")
    }

    @Test func magicUsesSetCodeInParentheses() {
        #expect(DeckShareCard.code(game: .magic, setName: "Star Trek (TRK)", number: "1704") == "TRK #1704")
    }

    @Test func fallsBackToSetName() {
        #expect(DeckShareCard.code(game: .pokemon, setName: "Surging Sparks", number: "57") == "Surging Sparks #57")
        #expect(DeckShareCard.code(game: .pokemon, setName: "Surging Sparks", number: "") == "Surging Sparks")
    }
}
