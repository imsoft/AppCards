import Foundation
import SwiftData

/// Operaciones sobre la colección que se usan desde varias pantallas.
enum CollectionStore {
    /// Suma `quantity` copias de la impresión. Si ya existe, incrementa; si no, crea el registro con el precio más barato de esa impresión.
    @MainActor
    static func add(_ detail: CardDetail, quantity: Int = 1, in context: ModelContext) -> CollectionItem {
        let cardID = detail.summary.id
        let descriptor = FetchDescriptor<CollectionItem>(predicate: #Predicate { $0.cardID == cardID })
        if let existing = try? context.fetch(descriptor).first {
            existing.quantity += quantity
            if existing.referencePrice == nil, let quote = detail.cheapestQuote() {
                existing.apply(quote: quote)
            }
            try? context.save()
            return existing
        }
        let item = CollectionItem(card: detail.summary, quantity: quantity, quote: detail.cheapestQuote())
        context.insert(item)
        try? context.save()
        return item
    }

    @MainActor
    static func owned(game: Game, in context: ModelContext) -> [String: Int] {
        let raw = game.rawValue
        let descriptor = FetchDescriptor<CollectionItem>(predicate: #Predicate { $0.gameRaw == raw })
        let items = (try? context.fetch(descriptor)) ?? []
        return CollectionMath.owned(items.map(\.line))
    }
}
