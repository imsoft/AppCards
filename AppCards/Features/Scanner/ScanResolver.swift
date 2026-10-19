import Foundation

struct ScanResult: Equatable, Sendable {
    let hint: ScanHint
    let best: CardDetail
    let others: [CardSummary]
}

/// Convierte una pista del escáner en cartas reales consultando las fuentes.
struct ScanResolver: Sendable {
    let scryfall: ScryfallProvider
    let tcgdex: TCGdexProvider
    let onePiece: OnePieceProvider

    func resolve(_ hint: ScanHint) async throws -> ScanResult? {
        switch hint {
        case .onePiece(let number):
            guard let cheapest = try await onePiece.cheapestPrinting(number: number) else { return nil }
            let all = try await onePiece.printings(of: cheapest.detail).map(\.summary).filter { $0.id != cheapest.detail.summary.id }
            return ScanResult(hint: hint, best: cheapest.detail, others: all)

        case .pokemon(let names, let number, let total):
            let setsByTotal = total == nil ? [:] : (try? await tcgdex.setIDs(byOfficialCount: total!)) ?? [:]
            for name in names {
                let found = try await tcgdex.search(name)
                var candidates = number == nil ? found : found.filter { $0.number == number }
                if candidates.isEmpty { candidates = found.filter { $0.name.lowercased() == name.lowercased() } }
                guard !candidates.isEmpty else { continue }
                let preferred = candidates.filter { setsByTotal[TCGdexMapper.setCode(from: $0.providerID).lowercased()] != nil }
                let ordered = preferred + candidates.filter { !preferred.contains($0) }
                let best = try await tcgdex.detail(providerID: ordered[0].providerID)
                return ScanResult(hint: hint, best: best, others: Array(ordered.dropFirst().prefix(12)))
            }
            return nil

        case .magic(let names, let setCode, let collector):
            for name in names {
                if let setCode, let collector, let exact = try await scryfall.card(set: setCode, collectorNumber: collector), exact.summary.name.lowercased().hasPrefix(name.lowercased().prefix(4)) {
                    return ScanResult(hint: hint, best: exact, others: [])
                }
                if let setCode, let detail = try await scryfall.named(fuzzy: name, set: setCode) {
                    return ScanResult(hint: hint, best: detail, others: [])
                }
                if let detail = try await scryfall.named(fuzzy: name, set: nil) {
                    let others = (try? await scryfall.printings(of: detail))?.map(\.summary).filter { $0.id != detail.summary.id } ?? []
                    return ScanResult(hint: hint, best: detail, others: Array(others.prefix(12)))
                }
            }
            return nil
        }
    }
}
