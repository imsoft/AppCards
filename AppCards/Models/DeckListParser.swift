import Foundation

struct DeckListLine: Equatable, Sendable, Identifiable {
    let raw: String
    var quantity: Int
    /// Número de carta normalizado (OP01-003) si la línea lo trae.
    var number: String?
    /// Nombre si la línea no trae número.
    var name: String?

    var id: String { raw }
}

/// Lee listas de One Piece en los formatos comunes:
/// "4xOP01-003", "4 OP01-003", "OP01-003 x4", "4 Monkey.D.Luffy (OP01-003)", "4 Monkey.D.Luffy".
enum DeckListParser {
    static let numberPattern = #"(?i)\b(OP|ST|EB|PRB|OPB|P)\s?-?(\d{2})-(\d{3})\b"#
    private static let leadingQuantity = #"^\s*(\d+)\s*[xX×]?\s+"#
    private static let leadingQuantityTight = #"^\s*(\d+)\s*[xX×]"#
    private static let trailingQuantity = #"\s*[xX×]\s*(\d+)\s*$"#
    private static let headers: Set<String> = ["leader", "leaders", "characters", "character", "events", "event", "stages", "stage", "don", "deck", "main", "sideboard", "side"]

    static func parse(_ text: String) -> [DeckListLine] {
        var lines: [DeckListLine] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("//"), !trimmed.hasPrefix("#") else { continue }
            var work = trimmed
            var quantity = 1

            // Encabezados tipo "Leader:" o "Characters"
            let headerCandidate = work.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ": "))
            if headers.contains(headerCandidate) { continue }
            if let colon = work.firstIndex(of: ":"), headers.contains(work[..<colon].lowercased().trimmingCharacters(in: .whitespaces)) {
                work = String(work[work.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            }

            if let match = work.firstMatch(of: leadingQuantity), let q = Int(match.1) {
                quantity = q
                work = String(work[match.range.upperBound...])
            } else if let match = work.firstMatch(of: leadingQuantityTight), let q = Int(match.1) {
                quantity = q
                work = String(work[match.range.upperBound...])
            } else if let match = work.firstMatch(of: trailingQuantity), let q = Int(match.1) {
                quantity = q
                work = String(work[..<match.range.lowerBound])
            }
            work = work.trimmingCharacters(in: .whitespaces)

            var number: String?
            if let match = work.firstMatch(of: numberPattern) {
                number = "\(match.1.uppercased())\(match.2)-\(match.3)"
                work.removeSubrange(match.range)
            }
            let name = work
                .replacingOccurrences(of: #"[()\[\]]"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: " -–:,"))

            guard number != nil || !name.isEmpty else { continue }
            lines.append(DeckListLine(raw: trimmed, quantity: max(quantity, 1), number: number, name: name.isEmpty ? nil : name))
        }
        return merge(lines)
    }

    /// Junta líneas repetidas del mismo número o nombre.
    static func merge(_ lines: [DeckListLine]) -> [DeckListLine] {
        var result: [DeckListLine] = []
        for line in lines {
            if let index = result.firstIndex(where: { ($0.number != nil && $0.number == line.number) || ($0.number == nil && line.number == nil && $0.name?.lowercased() == line.name?.lowercased()) }) {
                result[index].quantity += line.quantity
                if result[index].name == nil { result[index].name = line.name }
            } else {
                result.append(line)
            }
        }
        return result
    }
}

private extension String {
    func firstMatch(of pattern: String) -> (range: Range<String.Index>, _1: String, _2: String, _3: String)? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self)),
              let range = Range(match.range, in: self) else { return nil }
        func group(_ i: Int) -> String {
            guard i < match.numberOfRanges, let r = Range(match.range(at: i), in: self) else { return "" }
            return String(self[r])
        }
        return (range, group(1), group(2), group(3))
    }
}
