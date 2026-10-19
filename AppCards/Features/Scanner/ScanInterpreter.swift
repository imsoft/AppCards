import Foundation
import CoreGraphics

/// Una línea de texto reconocida por Vision. `box` está normalizado con origen abajo-izquierda.
struct RecognizedLine: Equatable, Sendable {
    let text: String
    let confidence: Float
    let box: CGRect

    init(text: String, confidence: Float = 1, box: CGRect = CGRect(x: 0, y: 0.8, width: 1, height: 0.05)) {
        self.text = text
        self.confidence = confidence
        self.box = box
    }
}

enum ScanHint: Equatable, Sendable {
    case onePiece(number: String)
    case pokemon(nameCandidates: [String], number: String?, total: Int?)
    case magic(nameCandidates: [String], setCode: String?, collectorNumber: String?)

    var game: Game {
        switch self {
        case .onePiece: .onePiece
        case .pokemon: .pokemon
        case .magic: .magic
        }
    }
}

/// Convierte el texto leído de una carta en una pista de qué carta es. Sin red, probado en tests.
enum ScanInterpreter {
    private static let onePiecePattern = #"(?i)\b(OP|ST|EB|PRB|P)\s?-?\s?(\d{2})\s?-\s?(\d{3})\b"#
    private static let fractionPattern = #"\b(\d{1,3})\s*/\s*(\d{1,3})\b"#
    private static let magicSetPattern = #"\b([A-Z0-9]{3,4})\s*[•·\.\*]\s*(EN|ES|FR|DE|IT|PT|JA|KO|RU|ZH[ST]?)\b"#
    private static let magicCollectorPattern = #"\b(\d{1,4})\s*/\s*(\d{1,4})\s*([CURM])?\b"#
    private static let stopWords: Set<String> = ["hp", "basic", "stage", "stage 1", "stage 2", "trainer", "item", "supporter", "stadium", "energy", "pokemon", "pokémon", "evolves from", "legendary", "creature", "instant", "sorcery", "artifact", "enchantment", "land", "planeswalker", "leader", "character", "event", "stage", "don"]

    static func interpret(lines: [RecognizedLine], forced: Game? = nil) -> ScanHint? {
        let joined = lines.map(\.text).joined(separator: "\n")
        let normalizedJoined = joined
            .replacingOccurrences(of: "0P", with: "OP")
            .replacingOccurrences(of: "5T", with: "ST")

        if forced == nil || forced == .onePiece,
           let match = normalizedJoined.firstMatch(pattern: onePiecePattern) {
            return .onePiece(number: "\(match[1].uppercased())\(match[2])-\(match[3])")
        }
        if forced == .onePiece { return nil }

        let names = nameCandidates(from: lines)
        let fraction = joined.firstMatch(pattern: fractionPattern)
        let hasHP = joined.range(of: #"\bHP\s*\d{2,3}\b|\b\d{2,3}\s*HP\b"#, options: .regularExpression) != nil
        let setMatch = joined.firstMatch(pattern: magicSetPattern)

        let looksPokemon = hasHP || (fraction != nil && setMatch == nil && (Int(fraction![2]) ?? 999) <= 400)
        let game = forced ?? (looksPokemon ? .pokemon : .magic)

        switch game {
        case .pokemon:
            guard !names.isEmpty || fraction != nil else { return nil }
            return .pokemon(nameCandidates: names, number: fraction?[1], total: fraction.flatMap { Int($0[2]) })
        case .magic:
            guard !names.isEmpty else { return nil }
            let collector = joined.firstMatch(pattern: magicCollectorPattern)?[1]
            return .magic(nameCandidates: names, setCode: setMatch?[1].lowercased(), collectorNumber: collector)
        case .onePiece:
            return nil
        }
    }

    /// Líneas de la parte alta de la carta, grandes, con letras, que no sean palabras de plantilla.
    static func nameCandidates(from lines: [RecognizedLine], limit: Int = 3) -> [String] {
        lines
            .filter { $0.box.minY >= 0.55 && $0.confidence >= 0.3 }
            .map { ($0, clean($0.text)) }
            .filter { $0.1.count >= 3 && $0.1.rangeOfCharacter(from: .letters) != nil && !stopWords.contains($0.1.lowercased()) }
            .sorted { $0.0.box.height > $1.0.box.height }
            .prefix(limit)
            .map(\.1)
    }

    private static func clean(_ text: String) -> String {
        var cleaned = text
        if let range = cleaned.range(of: #"\s*\bHP\s*\d+.*$"#, options: .regularExpression) { cleaned.removeSubrange(range) }
        if let range = cleaned.range(of: #"^\s*(Basic|Stage \d|BASIC|STAGE \d)\s+"#, options: .regularExpression) { cleaned.removeSubrange(range) }
        cleaned = cleaned.replacingOccurrences(of: #"[^\p{L}\p{N}' ,\-\.]"#, with: " ", options: .regularExpression)
        return cleaned.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }
}

extension String {
    /// Grupos de la primera coincidencia (índice 0 = coincidencia completa).
    func firstMatch(pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self)) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: self) else { return "" }
            return String(self[range])
        }
    }
}
