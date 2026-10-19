import Foundation
import SwiftUI
import SwiftData

// Nota: todas las propiedades tienen valor por defecto y las relaciones son opcionales
// para que el esquema sea compatible con CloudKit.

@Model
final class Deck {
    /// Identificador para sincronizar entre dispositivos (se asigna en la primera sincronización).
    var syncID: String = ""
    /// Huella de lo último que se sincronizó; si cambia, hay algo por subir.
    var lastSyncedHash: String = ""
    var name: String = ""
    var gameRaw: String = Game.magic.rawValue
    var createdAt: Date = Date()
    /// Colores del deck en hex separados por coma ("#2F5BEA,#1F9D55"); vacío = color del juego. Máximo 3.
    var colorHex: String = ""
    @Relationship(deleteRule: .cascade, inverse: \DeckEntry.deck) var entries: [DeckEntry]? = []

    init(syncID: String) { self.syncID = syncID }

    init(name: String, game: Game) {
        self.name = name
        self.gameRaw = game.rawValue
        self.createdAt = .now
        self.entries = []
    }

    var game: Game { Game(rawValue: gameRaw) ?? .magic }
    var entryList: [DeckEntry] { entries ?? [] }
    /// Cartas del deck (sin las opciones o sustituciones).
    var mainEntries: [DeckEntry] { entryList.filter { !$0.isAlternative } }
    /// Otras cartas a considerar; no cuentan en el total del deck.
    var alternativeEntries: [DeckEntry] { entryList.filter(\.isAlternative) }
    var cardCount: Int { mainEntries.reduce(0) { $0 + $1.quantity } }
    /// Colores elegidos, en el orden en que se eligieron.
    var accentColors: [Color] { DeckColors.colors(from: colorHex, fallback: game.color) }
    /// Color principal (el primero).
    var accentColor: Color { accentColors.first ?? game.color }
    /// Degradado con los colores del deck (con uno solo, ese color y una variante más clara).
    var accentGradient: LinearGradient { DeckColors.gradient(accentColors) }
    /// Texto legible encima del degradado.
    var accentForeground: Color { DeckColors.foreground(accentColors) }

    var lines: [DeckLine] {
        mainEntries.map(\.line)
    }
}

@Model
final class DeckEntry {
    /// Identificador para sincronizar entre dispositivos (se asigna en la primera sincronización).
    var syncID: String = ""
    /// Huella de lo último que se sincronizó; si cambia, hay algo por subir.
    var lastSyncedHash: String = ""
    var cardID: String = ""
    var providerID: String = ""
    var gameRaw: String = Game.magic.rawValue
    var canonicalKey: String = ""
    var name: String = ""
    var setName: String = ""
    var number: String = ""
    var imageURLString: String?
    var quantity: Int = 1
    /// Copias que ya tienes para este deck (lo editas tú; se puede rellenar desde la colección).
    var ownedQuantity: Int = 0
    /// "Otras cartas a incluir / posibles sustituciones": no cuenta en el total.
    var isAlternative: Bool = false
    /// Nota libre, por ejemplo "sustituye a Luffy".
    var note: String = ""
    /// Si es una opción: el `syncID` de la carta del deck a la que sustituiría.
    var replacesID: String = ""
    var quoteID: String = ""
    var variantTitle: String = ""
    var unitPrice: Double?
    var currency: String = "USD"
    var priceUpdatedAt: Date?
    var deck: Deck?

    init(syncID: String) { self.syncID = syncID }

    init(card: CardSummary, quantity: Int, quote: PriceQuote?) {
        self.cardID = card.id
        self.providerID = card.providerID
        self.gameRaw = card.game.rawValue
        self.canonicalKey = card.canonicalKey
        self.name = card.name
        self.setName = card.setName
        self.number = card.number
        self.imageURLString = card.imageURL?.absoluteString ?? card.thumbnailURL?.absoluteString
        self.quantity = quantity
        self.quoteID = quote?.id ?? ""
        self.variantTitle = quote?.title ?? "Sin precio"
        self.unitPrice = quote?.reference
        self.currency = quote?.currency ?? "USD"
        self.priceUpdatedAt = quote == nil ? nil : .now
    }

    var game: Game { Game(rawValue: gameRaw) ?? .magic }
    /// Imagen para cuadrícula y filas, en buena resolución aunque se haya guardado una miniatura.
    var imageURL: URL? { ImageQuality.best(imageURLString.flatMap { URL(string: $0) }, size: .grid) }
    var fullImageURL: URL? { ImageQuality.best(imageURLString.flatMap { URL(string: $0) }, size: .full) }

    var artworkFallback: ArtworkFallback {
        ArtworkFallback(game: game, providerID: providerID, number: number, name: name)
    }

    /// Para abrir el perfil completo de la carta.
    var summary: CardSummary {
        CardSummary(game: game, providerID: providerID, name: name, setName: setName, number: number,
                    rarity: nil, thumbnailURL: imageURL, imageURL: fullImageURL, canonicalKey: canonicalKey)
    }
    var setLine: String { [setName, "#\(number)"].filter { !$0.isEmpty }.joined(separator: " · ") }
    var missingQuantity: Int { max(quantity - ownedQuantity, 0) }

    var line: DeckLine {
        DeckLine(canonicalKey: canonicalKey, quantity: quantity, ownedQuantity: min(ownedQuantity, quantity), unitPrice: unitPrice, currency: currency)
    }

    /// Cambia la impresión y el precio de esta línea (por ejemplo, a la más barata).
    func apply(summary: CardSummary, quote: PriceQuote) {
        cardID = summary.id
        providerID = summary.providerID
        canonicalKey = summary.canonicalKey
        name = summary.name
        setName = summary.setName
        number = summary.number
        imageURLString = summary.imageURL?.absoluteString ?? summary.thumbnailURL?.absoluteString
        apply(quote: quote)
    }

    func apply(quote: PriceQuote) {
        quoteID = quote.id
        variantTitle = quote.title
        unitPrice = quote.reference
        currency = quote.currency
        priceUpdatedAt = .now
    }
}

struct DeckLine: Sendable, Equatable {
    var canonicalKey: String = ""
    let quantity: Int
    var ownedQuantity: Int = 0
    let unitPrice: Double?
    let currency: String
}

struct DeckTotal: Equatable, Sendable {
    let amount: Double
    let currency: String
    let totalCards: Int
    let unpricedCards: Int
    /// Lo que falta comprar descontando la colección.
    let missingAmount: Double
    let missingCards: Int
    let ownedCards: Int
}

enum DeckMath {
    /// Cuántas copias de cada línea cubre la colección (por clave canónica).
    /// Si varias líneas piden la misma carta, lo que tienes se reparte en orden.
    static func coveredByCollection(lines: [DeckLine], owned: [String: Int]) -> [Int] {
        var remaining = owned
        return lines.map { line in
            let have = remaining[line.canonicalKey] ?? 0
            let used = min(have, line.quantity)
            remaining[line.canonicalKey] = have - used
            return used
        }
    }

    static func missingQuantities(lines: [DeckLine], owned: [String: Int]) -> [Int] {
        zip(lines, coveredByCollection(lines: lines, owned: owned)).map { $0.quantity - $1 }
    }

    /// Total del deck y lo que falta según el conteo "tengo" de cada línea.
    /// Si se pasa `owned` (colección), se usa como mínimo garantizado por línea.
    static func total(lines: [DeckLine], owned: [String: Int] = [:], in currency: String, converter: CurrencyConverter) -> DeckTotal {
        let covered = coveredByCollection(lines: lines, owned: owned)
        let missing = zip(lines, covered).map { line, fromCollection in
            max(line.quantity - max(line.ownedQuantity, fromCollection), 0)
        }
        var amount = 0.0
        var missingAmount = 0.0
        var unpriced = 0
        var total = 0
        var missingCards = 0

        for (line, missingQty) in zip(lines, missing) {
            total += line.quantity
            missingCards += missingQty
            guard let unit = line.unitPrice,
                  let converted = converter.convert(unit, from: line.currency, to: currency) else {
                unpriced += line.quantity
                continue
            }
            amount += converted * Double(line.quantity)
            missingAmount += converted * Double(missingQty)
        }
        return DeckTotal(
            amount: amount,
            currency: currency,
            totalCards: total,
            unpricedCards: unpriced,
            missingAmount: missingAmount,
            missingCards: missingCards,
            ownedCards: total - missingCards
        )
    }
}

/// Sustituciones: "cambiaría esta carta del deck por esta opción".
enum DeckSubstitution {
    /// Asegura un identificador estable para poder enlazar cartas (también sirve para sincronizar).
    static func ensureID(_ entry: DeckEntry) {
        if entry.syncID.isEmpty { entry.syncID = UUID().uuidString }
    }

    /// Marca `option` como sustituto de `target` (o quita el enlace si `target` es nil).
    static func link(_ option: DeckEntry, to target: DeckEntry?) {
        option.isAlternative = true
        guard let target else { option.replacesID = ""; return }
        ensureID(target)
        option.replacesID = target.syncID
    }

    /// La carta del deck a la que sustituiría esta opción.
    static func target(of option: DeckEntry, in entries: [DeckEntry]) -> DeckEntry? {
        guard option.isAlternative, !option.replacesID.isEmpty else { return nil }
        return entries.first { !$0.isAlternative && $0.syncID == option.replacesID }
    }

    /// Opciones que sustituirían a esta carta del deck.
    static func substitutes(for entry: DeckEntry, in entries: [DeckEntry]) -> [DeckEntry] {
        guard !entry.isAlternative, !entry.syncID.isEmpty else { return [] }
        return entries.filter { $0.isAlternative && $0.replacesID == entry.syncID }
    }

    /// Hace el cambio: la opción entra al deck y la carta que sustituye pasa a opciones,
    /// enlazada al revés para poder deshacerlo con el mismo botón.
    @discardableResult
    static func swap(_ option: DeckEntry, in entries: [DeckEntry]) -> DeckEntry? {
        guard let target = target(of: option, in: entries) else { return nil }
        ensureID(option)
        option.isAlternative = false
        option.replacesID = ""
        target.isAlternative = true
        target.replacesID = option.syncID
        // Otras opciones que apuntaban a la carta vieja ahora apuntan a la nueva.
        for other in entries where other !== option && other !== target && other.replacesID == target.syncID {
            other.replacesID = option.syncID
        }
        return target
    }

    /// Cuánto cambia el costo del deck al hacer el cambio (positivo = más caro). Nil si falta algún precio.
    static func costDifference(option: DeckEntry, target: DeckEntry, convert: (Double, String) -> Double?) -> Double? {
        guard let optionUnit = option.unitPrice, let targetUnit = target.unitPrice,
              let optionCost = convert(optionUnit * Double(option.quantity), option.currency),
              let targetCost = convert(targetUnit * Double(target.quantity), target.currency) else { return nil }
        return optionCost - targetCost
    }
}

/// Colores de un deck guardados como "#A,#B,#C".
enum DeckColors {
    static let maxColors = 3

    static func hexes(_ value: String) -> [String] {
        value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { Color(hex: $0) != nil }
    }

    static func colors(from value: String, fallback: Color) -> [Color] {
        let parsed = hexes(value).compactMap { Color(hex: $0) }
        return parsed.isEmpty ? [fallback] : parsed
    }

    /// Agrega o quita un color, respetando el máximo (si ya hay 3, reemplaza el último).
    static func toggle(_ hex: String, in value: String) -> String {
        var list = hexes(value)
        if let index = list.firstIndex(of: hex) {
            list.remove(at: index)
        } else if list.count >= maxColors {
            list[list.count - 1] = hex
        } else {
            list.append(hex)
        }
        return list.joined(separator: ",")
    }

    static func gradient(_ colors: [Color]) -> LinearGradient {
        let stops = colors.count > 1 ? colors : [colors.first ?? .gray, (colors.first ?? .gray).opacity(0.7)]
        return LinearGradient(colors: stops, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Blanco u oscuro según qué tan claros sean, en promedio, los colores.
    static func foreground(_ colors: [Color]) -> Color {
        let dark = Color(red: 0.12, green: 0.1, blue: 0.08)
        let lightCount = colors.filter { $0.readableForeground != .white }.count
        return lightCount * 2 > colors.count ? dark : .white
    }
}
