import Testing
import SwiftUI
@testable import AppCards

struct DeckColorsTests {
    @Test func toggleKeepsOrderAndMaximum() {
        var value = ""
        value = DeckColors.toggle("#2F5BEA", in: value)
        value = DeckColors.toggle("#D93A3A", in: value)
        value = DeckColors.toggle("#1F9D55", in: value)
        #expect(DeckColors.hexes(value) == ["#2F5BEA", "#D93A3A", "#1F9D55"])
        // Con 3, un cuarto reemplaza al último.
        value = DeckColors.toggle("#F2A623", in: value)
        #expect(DeckColors.hexes(value) == ["#2F5BEA", "#D93A3A", "#F2A623"])
        // Tocar uno elegido lo quita.
        value = DeckColors.toggle("#D93A3A", in: value)
        #expect(DeckColors.hexes(value) == ["#2F5BEA", "#F2A623"])
    }

    @Test func singleColorDecksStillWork() {
        // Decks guardados antes, con un solo color.
        #expect(DeckColors.colors(from: "#2F5BEA", fallback: .gray).count == 1)
        #expect(DeckColors.colors(from: "", fallback: .gray) == [.gray])
        #expect(DeckColors.colors(from: "#2F5BEA,basura,#1F9D55", fallback: .gray).count == 2)
    }

    @Test func foregroundReadableOnGradient() {
        #expect(DeckColors.foreground([.black, Color(hex: "#2F5BEA")!]) == .white)
        #expect(DeckColors.foreground([.white, Color(hex: "#F2A623")!]) != .white)
    }
}
