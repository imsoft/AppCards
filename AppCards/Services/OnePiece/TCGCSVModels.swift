import Foundation

struct TCGCSVResponse<T: Decodable & Sendable>: Decodable, Sendable {
    let results: [T]
}

struct TCGCSVGroup: Decodable, Sendable {
    let groupId: Int
    let name: String
    let abbreviation: String?
}

struct TCGCSVProduct: Decodable, Sendable {
    struct ExtendedDatum: Decodable, Sendable {
        let name: String
        let displayName: String?
        let value: String
    }

    let productId: Int
    let name: String
    let imageUrl: String?
    let url: String?
    let groupId: Int
    let extendedData: [ExtendedDatum]?

    func extended(_ name: String) -> String? {
        extendedData?.first { $0.name == name }?.value
    }
}

struct TCGCSVPrice: Decodable, Sendable {
    let productId: Int
    let lowPrice: Double?
    let midPrice: Double?
    let highPrice: Double?
    let marketPrice: Double?
    let subTypeName: String?
}
