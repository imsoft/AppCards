import Foundation

struct FilterOption: Hashable, Identifiable, Sendable, Codable {
    let id: String
    let title: String
}

enum CardSort: String, CaseIterable, Identifiable, Sendable {
    case relevance
    case priceAsc
    case priceDesc
    case nameAsc
    case nameDesc
    case number
    case newest
    case oldest

    var id: String { rawValue }
    var title: String {
        switch self {
        case .relevance: "Relevancia"
        case .priceAsc: "Precio: menor a mayor"
        case .priceDesc: "Precio: mayor a menor"
        case .nameAsc: "Nombre: A → Z"
        case .nameDesc: "Nombre: Z → A"
        case .number: "Número de carta"
        case .newest: "Más nuevas primero"
        case .oldest: "Más viejas primero"
        }
    }

    var isPrice: Bool { self == .priceAsc || self == .priceDesc }
    var isDate: Bool { self == .newest || self == .oldest }
}

/// Filtro local según tu colección (se aplica después de buscar).
enum OwnershipFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case owned
    case missing

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "Todas"
        case .owned: "Las que tengo"
        case .missing: "Las que no tengo"
        }
    }
}

struct SearchFilters: Equatable, Sendable {
    var cardSet: FilterOption?
    var color: FilterOption?
    var cardType: FilterOption?
    var cost: Int?
    var rarity: FilterOption?
    var parallelOnly = false
    /// Texto dentro de la carta (efecto, habilidad).
    var cardText = ""
    /// Subtipo o tribu: "Elf", "Straw Hat Crew".
    var subtype = ""
    /// Formato donde es legal: Commander, Standard…
    var format: FilterOption?
    /// Habilidad (Magic), tipo ex/V (Pokémon) o atributo (One Piece).
    var mechanic: FilterOption?
    /// Etapa de evolución (Pokémon).
    var stage: FilterOption?
    /// Poder mínimo (Magic, One Piece) o HP mínimo (Pokémon).
    var minPower: Int?
    /// Rango de precio en USD (la hoja lo edita en tu moneda).
    var priceMinUSD: Double?
    var priceMaxUSD: Double?
    var ownership: OwnershipFilter = .all
    var sort: CardSort = .relevance

    /// `true` si no hay ningún filtro que la fuente pueda usar para buscar (orden y "las que tengo" no cuentan).
    var isEmpty: Bool {
        cardSet == nil && color == nil && cardType == nil && cost == nil && rarity == nil && !parallelOnly
            && cardText.trimmed.isEmpty && subtype.trimmed.isEmpty && format == nil && mechanic == nil
            && stage == nil && minPower == nil && priceMinUSD == nil && priceMaxUSD == nil
    }

    var activeCount: Int { chips.count }

    static let none = SearchFilters()

    // MARK: Chips de filtros activos

    enum Key: Hashable, Sendable {
        case set, color, type, cost, rarity, parallel, text, subtype, format, mechanic, stage, power, price, ownership, sort
    }

    struct Chip: Identifiable, Hashable, Sendable {
        let key: Key
        let label: String
        var id: Key { key }
    }

    /// Lo que está activo, para mostrarlo como chips quitables debajo del selector de juego.
    var chips: [Chip] {
        var result: [Chip] = []
        if let cardSet { result.append(.init(key: .set, label: cardSet.title)) }
        if let color { result.append(.init(key: .color, label: color.title)) }
        if let cardType { result.append(.init(key: .type, label: cardType.title)) }
        if let stage { result.append(.init(key: .stage, label: stage.title)) }
        if let cost { result.append(.init(key: .cost, label: "Costo \(cost)")) }
        if let rarity { result.append(.init(key: .rarity, label: rarity.title)) }
        if let mechanic { result.append(.init(key: .mechanic, label: mechanic.title)) }
        if let format { result.append(.init(key: .format, label: format.title)) }
        if !subtype.trimmed.isEmpty { result.append(.init(key: .subtype, label: subtype.trimmed)) }
        if !cardText.trimmed.isEmpty { result.append(.init(key: .text, label: "“\(cardText.trimmed)”")) }
        if let minPower { result.append(.init(key: .power, label: "≥ \(minPower)")) }
        if priceMinUSD != nil || priceMaxUSD != nil { result.append(.init(key: .price, label: "Precio")) }
        if parallelOnly { result.append(.init(key: .parallel, label: "Paralelas")) }
        if ownership != .all { result.append(.init(key: .ownership, label: ownership.title)) }
        if sort != .relevance { result.append(.init(key: .sort, label: sort.title)) }
        return result
    }

    mutating func remove(_ key: Key) {
        switch key {
        case .set: cardSet = nil
        case .color: color = nil
        case .type: cardType = nil
        case .cost: cost = nil
        case .rarity: rarity = nil
        case .parallel: parallelOnly = false
        case .text: cardText = ""
        case .subtype: subtype = ""
        case .format: format = nil
        case .mechanic: mechanic = nil
        case .stage: stage = nil
        case .power: minPower = nil
        case .price: priceMinUSD = nil; priceMaxUSD = nil
        case .ownership: ownership = .all
        case .sort: sort = .relevance
        }
    }

    /// ¿El precio (USD) cae en el rango? Sin precio no pasa si hay rango.
    func priceMatches(_ usd: Double?) -> Bool {
        guard priceMinUSD != nil || priceMaxUSD != nil else { return true }
        guard let usd else { return false }
        if let priceMinUSD, usd < priceMinUSD { return false }
        if let priceMaxUSD, usd > priceMaxUSD { return false }
        return true
    }
}

/// Qué filtros ofrece cada juego y con qué valores.
struct FilterOptions: Sendable, Equatable {
    var sets: [FilterOption] = []
    var colors: [FilterOption] = []
    var cardTypes: [FilterOption] = []
    var costs: [Int] = []
    var rarities: [FilterOption] = []
    var supportsParallel = false
    var supportsPriceSort = true
    var priceSortNote: String?

    var formats: [FilterOption] = []
    var mechanics: [FilterOption] = []
    var mechanicTitle = "Habilidad"
    var stages: [FilterOption] = []
    var supportsCardText = false
    var cardTextPlaceholder = ""
    var supportsSubtype = false
    var subtypePlaceholder = ""
    /// Título del filtro de poder ("Poder mínimo", "HP mínimo"); nil si no aplica.
    var powerTitle: String?
    var powerValues: [Int] = []
    var supportsPriceRange = false
    var supportsDateSort = false

    /// Órdenes que tienen sentido para este juego.
    var sorts: [CardSort] {
        CardSort.allCases.filter { sort in
            if sort.isPrice { return supportsPriceSort }
            if sort.isDate { return supportsDateSort }
            return true
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension Array where Element == CardSummary {
    func sorted(by sort: CardSort) -> [CardSummary] {
        switch sort {
        case .relevance:
            return self
        case .priceAsc:
            return sorted { ($0.price ?? .infinity) < ($1.price ?? .infinity) }
        case .priceDesc:
            return sorted { ($0.price ?? -1) > ($1.price ?? -1) }
        case .nameAsc:
            return sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .nameDesc:
            return sorted { $0.name.localizedStandardCompare($1.name) == .orderedDescending }
        case .number:
            return sorted { ($0.setName, $0.number).0 == ($1.setName, $1.number).0
                ? $0.number.localizedStandardCompare($1.number) == .orderedAscending
                : $0.setName.localizedStandardCompare($1.setName) == .orderedAscending }
        case .newest, .oldest:
            // El orden por fecha lo resuelve la fuente (Scryfall); aquí se respeta el que llegó.
            return self
        }
    }
}

// MARK: - Orden en Colección y en decks

enum CollectionSort: String, CaseIterable, Identifiable, Sendable {
    case recent, name, valueDesc, quantityDesc, set

    var id: String { rawValue }
    var title: String {
        switch self {
        case .recent: "Agregadas recientemente"
        case .name: "Nombre"
        case .valueDesc: "Valor: mayor a menor"
        case .quantityDesc: "Más copias primero"
        case .set: "Set y número"
        }
    }
    var symbol: String {
        switch self {
        case .recent: "clock"
        case .name: "textformat"
        case .valueDesc: "dollarsign.circle"
        case .quantityDesc: "square.stack.3d.up"
        case .set: "number"
        }
    }
}

enum DeckSort: String, CaseIterable, Identifiable, Sendable {
    case missingFirst, name, priceDesc, set

    var id: String { rawValue }
    var title: String {
        switch self {
        case .missingFirst: "Las que me faltan primero"
        case .name: "Nombre"
        case .priceDesc: "Precio: mayor a menor"
        case .set: "Set y número"
        }
    }
    var symbol: String {
        switch self {
        case .missingFirst: "cart"
        case .name: "textformat"
        case .priceDesc: "dollarsign.circle"
        case .set: "number"
        }
    }
}

enum DeckViewMode: String, CaseIterable, Identifiable, Sendable {
    case list, grid, status

    var id: String { rawValue }
    var title: String {
        switch self {
        case .list: "Lista"
        case .grid: "Cuadrícula"
        case .status: "Por estado"
        }
    }
    var symbol: String {
        switch self {
        case .list: "list.bullet"
        case .grid: "square.grid.2x2"
        case .status: "checklist"
        }
    }
}
