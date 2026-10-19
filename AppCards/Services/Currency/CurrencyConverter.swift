import Foundation

struct ExchangeRates: Codable, Sendable, Equatable {
    let base: String
    let date: String
    let rates: [String: Double]
    let fetchedAt: Date
}

struct CurrencyConverter: Sendable {
    static let supported = ["MXN", "USD", "EUR"]

    var rates: ExchangeRates?
    var manualUSDMXN: Double?

    /// Cuántas unidades de `code` vale 1 USD.
    func rate(for code: String) -> Double? {
        if code == "USD" { return 1 }
        if code == "MXN", let manualUSDMXN, manualUSDMXN > 0 { return manualUSDMXN }
        guard let value = rates?.rates[code], value > 0 else { return nil }
        return value
    }

    func convert(_ amount: Double, from: String, to: String) -> Double? {
        if from == to { return amount }
        guard let fromRate = rate(for: from), let toRate = rate(for: to) else { return nil }
        return amount / fromRate * toRate
    }
}

struct ExchangeRateService: Sendable {
    let client: HTTPClient

    func fetchUSDRates() async throws -> ExchangeRates {
        struct Response: Decodable {
            let base: String
            let date: String
            let rates: [String: Double]
        }
        guard let url = URL(string: "https://api.frankfurter.dev/v1/latest?base=USD&symbols=MXN,EUR") else { throw ProviderError.badURL }
        let response = try await client.json(Response.self, from: url)
        return ExchangeRates(base: response.base, date: response.date, rates: response.rates, fetchedAt: .now)
    }
}

enum MoneyFormatter {
    /// Símbolo corto por moneda. Nunca "$" solo, para no confundir pesos con dólares.
    static func symbol(for currency: String) -> String {
        switch currency {
        case "MXN": "$"
        case "USD": "$"
        case "EUR": "€"
        default: ""
        }
    }

    /// Solo el número con símbolo: "$1,148.97". Úsalo junto a una etiqueta con el código.
    static func number(_ amount: Double, currency: String) -> String {
        let value = amount.formatted(.number.precision(.fractionLength(2)).grouping(.automatic))
        let symbol = symbol(for: currency)
        return amount < 0 ? "-\(symbol)\(value.dropFirst())" : "\(symbol)\(value)"
    }

    /// Número con el código de moneda siempre visible: "$1,148.97 MXN", "$62.50 USD", "€17.26 EUR".
    static func string(_ amount: Double, currency: String) -> String {
        "\(number(amount, currency: currency)) \(currency)"
    }
}

/// Margen que suelen cargar las tiendas sobre el precio de mercado.
enum StoreMarkup {
    static let defaultPercent = 25.0
    static let range: ClosedRange<Double> = 0...60

    /// Precio estimado en tienda.
    static func storePrice(_ market: Double, percent: Double) -> Double {
        market * (1 + percent / 100)
    }

    /// Cuánto de ese precio es margen de la tienda.
    static func markupAmount(_ market: Double, percent: Double) -> Double {
        market * percent / 100
    }

    /// Qué tanto arriba del mercado está un precio que te cotizaron (en %).
    static func percentAbove(market: Double, quoted: Double) -> Double? {
        guard market > 0 else { return nil }
        return (quoted - market) / market * 100
    }
}
