import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private enum Keys {
        static let displayCurrency = "displayCurrency"
        static let useManualRate = "useManualRate"
        static let manualUSDMXN = "manualUSDMXN"
        static let rates = "exchangeRates"
    }

    var displayCurrency: String {
        didSet { defaults.set(displayCurrency, forKey: Keys.displayCurrency) }
    }
    var useManualRate: Bool {
        didSet { defaults.set(useManualRate, forKey: Keys.useManualRate) }
    }
    var manualUSDMXN: Double {
        didSet { defaults.set(manualUSDMXN, forKey: Keys.manualUSDMXN) }
    }
    /// Margen de tienda en %. Se muestra junto al precio de mercado.
    var storeMarkupPercent: Double {
        didSet { defaults.set(storeMarkupPercent, forKey: "storeMarkupPercent") }
    }
    var showStorePrice: Bool {
        didSet { defaults.set(showStorePrice, forKey: "showStorePrice") }
    }

    /// Mensaje breve tipo toast (por ejemplo "+1 Luffy en colección").
    var toast: String?

    /// Juego activo en Buscar y filtro activo en Colección; tiñen la barra de pestañas.
    var searchGame: Game = .magic
    var collectionGame: Game?

    private var filterOptionsCache: [Game: FilterOptions] = [:]
    var lastRefreshAt: Date? {
        didSet { defaults.set(lastRefreshAt, forKey: "lastRefreshAt") }
    }
    var isRefreshingPrices = false

    private(set) var rates: ExchangeRates?
    private(set) var ratesError: String?
    private(set) var isRefreshingRates = false

    let client: HTTPClient
    let scryfall: ScryfallProvider
    let tcgdex: TCGdexProvider
    let onePiece: OnePieceProvider
    let rateService: ExchangeRateService
    let sync = SyncService()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let client = HTTPClient()
        self.client = client
        self.scryfall = ScryfallProvider(client: client)
        self.tcgdex = TCGdexProvider(client: client)
        self.onePiece = OnePieceProvider(client: client)
        self.rateService = ExchangeRateService(client: client)

        self.displayCurrency = defaults.string(forKey: Keys.displayCurrency) ?? "MXN"
        self.useManualRate = defaults.bool(forKey: Keys.useManualRate)
        let manual = defaults.double(forKey: Keys.manualUSDMXN)
        self.manualUSDMXN = manual > 0 ? manual : 18.0
        self.storeMarkupPercent = defaults.object(forKey: "storeMarkupPercent") as? Double ?? StoreMarkup.defaultPercent
        self.showStorePrice = defaults.object(forKey: "showStorePrice") as? Bool ?? true
        self.lastRefreshAt = defaults.object(forKey: "lastRefreshAt") as? Date
        if let data = defaults.data(forKey: Keys.rates) {
            self.rates = try? JSONDecoder().decode(ExchangeRates.self, from: data)
        }
    }

    func provider(for game: Game) -> any CardProvider {
        switch game {
        case .magic: scryfall
        case .pokemon: tcgdex
        case .onePiece: onePiece
        }
    }

    var converter: CurrencyConverter {
        CurrencyConverter(rates: rates, manualUSDMXN: useManualRate ? manualUSDMXN : nil)
    }

    func refreshRatesIfNeeded() async {
        if let rates, Date().timeIntervalSince(rates.fetchedAt) < 12 * 60 * 60 { return }
        await refreshRates()
    }

    func refreshRates() async {
        isRefreshingRates = true
        defer { isRefreshingRates = false }
        do {
            let fresh = try await rateService.fetchUSDRates()
            rates = fresh
            ratesError = nil
            if let data = try? JSONEncoder().encode(fresh) {
                defaults.set(data, forKey: Keys.rates)
            }
        } catch {
            ratesError = error.localizedDescription
        }
    }

    func filterOptions(for game: Game) async throws -> FilterOptions {
        if let cached = filterOptionsCache[game] { return cached }
        let options = try await provider(for: game).filterOptions()
        filterOptionsCache[game] = options
        return options
    }

    func showToast(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            if toast == message { toast = nil }
        }
    }

    /// Convierte a la moneda elegida. Si no hay tipo de cambio, regresa nil.
    func converted(_ amount: Double, from currency: String) -> Double? {
        converter.convert(amount, from: currency, to: displayCurrency)
    }

    /// Texto en la moneda elegida; si no se puede convertir, muestra el original.
    func display(_ amount: Double, currency: String) -> String {
        if let value = converted(amount, from: currency) {
            return MoneyFormatter.string(value, currency: displayCurrency)
        }
        return MoneyFormatter.string(amount, currency: currency)
    }
}
