import Testing
import Foundation
@testable import AppCards

struct ScanInterpreterTests {
    private func line(_ text: String, y: CGFloat = 0.85, height: CGFloat = 0.05, confidence: Float = 0.9) -> RecognizedLine {
        RecognizedLine(text: text, confidence: confidence, box: CGRect(x: 0.1, y: y, width: 0.6, height: height))
    }

    @Test func detectsOnePieceNumberEvenWithOCRNoise() {
        let lines = [line("Monkey.D.Luffy"), line("0P01-003 L", y: 0.05)]
        #expect(ScanInterpreter.interpret(lines: lines) == .onePiece(number: "OP01-003"))
        #expect(ScanInterpreter.interpret(lines: [line("ST 01 - 002", y: 0.05)]) == .onePiece(number: "ST01-002"))
        #expect(ScanInterpreter.interpret(lines: [line("EB01-010")], forced: .onePiece) == .onePiece(number: "EB01-010"))
        #expect(ScanInterpreter.interpret(lines: [line("Pikachu")], forced: .onePiece) == nil)
    }

    @Test func detectsPokemonByHPAndFraction() {
        let lines = [
            line("Basic", y: 0.9, height: 0.02),
            line("Furret HP 110", y: 0.88, height: 0.06),
            line("Scout", y: 0.6, height: 0.04),
            line("136/189", y: 0.03, height: 0.02),
        ]
        let hint = ScanInterpreter.interpret(lines: lines)
        #expect(hint == .pokemon(nameCandidates: ["Furret", "Scout"], number: "136", total: 189))
        #expect(hint?.game == .pokemon)
    }

    @Test func detectsMagicBySetCodeAndName() {
        let lines = [
            line("Lightning Bolt", y: 0.9, height: 0.06),
            line("Instant", y: 0.5, height: 0.04),
            line("Lightning Bolt deals 3 damage to any target.", y: 0.4, height: 0.03),
            line("150/271 C", y: 0.04, height: 0.02),
            line("MSC • EN", y: 0.02, height: 0.02),
        ]
        let hint = ScanInterpreter.interpret(lines: lines)
        #expect(hint == .magic(nameCandidates: ["Lightning Bolt"], setCode: "msc", collectorNumber: "150"))
    }

    @Test func fallsBackToMagicWhenOnlyNameIsReadable() {
        let hint = ScanInterpreter.interpret(lines: [line("Sol Ring", height: 0.07)])
        #expect(hint == .magic(nameCandidates: ["Sol Ring"], setCode: nil, collectorNumber: nil))
    }

    @Test func nameCandidatesIgnoreTemplateWordsAndBottomText() {
        let lines = [
            line("Stage 1", y: 0.92, height: 0.02),
            line("Charizard HP 170", y: 0.88, height: 0.07),
            line("Illus. Mitsuhiro Arita", y: 0.05, height: 0.02),
            line("Weakness", y: 0.1, height: 0.02),
        ]
        #expect(ScanInterpreter.nameCandidates(from: lines) == ["Charizard"])
    }

    @Test func returnsNilWithoutUsableText() {
        #expect(ScanInterpreter.interpret(lines: []) == nil)
        #expect(ScanInterpreter.interpret(lines: [RecognizedLine(text: "HP", confidence: 0.9, box: CGRect(x: 0, y: 0.9, width: 1, height: 0.05))]) == nil)
    }
}
