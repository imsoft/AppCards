import Foundation

struct HTTPError: Error, LocalizedError, Sendable {
    let statusCode: Int
    let url: URL

    var errorDescription: String? { "HTTP \(statusCode) en \(url.host ?? url.absoluteString)" }
}

struct HTTPClient: Sendable {
    static let userAgent = "AppCards/1.0 (iOS)"

    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw HTTPError(statusCode: http.statusCode, url: url)
        }
        return data
    }

    func json<T: Decodable>(_ type: T.Type, from url: URL, decoder: JSONDecoder = JSONDecoder()) async throws -> T {
        let data = try await data(from: url)
        return try decoder.decode(T.self, from: data)
    }
}

/// Clave genérica para decodificar diccionarios con llaves dinámicas.
struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { self.intValue = intValue; stringValue = String(intValue) }
}
