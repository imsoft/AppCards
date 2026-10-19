import Foundation

enum Game: String, CaseIterable, Codable, Identifiable, Sendable {
    case magic
    case pokemon
    case onePiece

    var id: String { rawValue }

    var title: String {
        switch self {
        case .magic: "Magic"
        case .pokemon: "Pokémon"
        case .onePiece: "One Piece"
        }
    }

    var systemImage: String {
        switch self {
        case .magic: "wand.and.stars"
        case .pokemon: "bolt.circle"
        case .onePiece: "sailboat"
        }
    }

    var sourceName: String {
        switch self {
        case .magic: "Scryfall"
        case .pokemon: "TCGdex"
        case .onePiece: "TCGplayer (tcgcsv.com)"
        }
    }
}
