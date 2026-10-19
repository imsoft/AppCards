import Foundation

final class FixtureAnchor {}

enum Fixtures {
    static func data(_ name: String) throws -> Data {
        let bundle = Bundle(for: FixtureAnchor.self)
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw NSError(domain: "Fixtures", code: 1, userInfo: [NSLocalizedDescriptionKey: "No existe el fixture \(name).json"])
        }
        return try Data(contentsOf: url)
    }

    static func decode<T: Decodable>(_ type: T.Type, from name: String, decoder: JSONDecoder = JSONDecoder()) throws -> T {
        try decoder.decode(T.self, from: data(name))
    }
}
