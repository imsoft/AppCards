import Foundation

/// One Piece no tiene un API público gratuito con precios, así que se descarga el catálogo completo
/// de TCGplayer desde tcgcsv.com (actualizado a diario) y se busca en memoria.
actor OnePieceProvider: CardProvider {
    nonisolated let game: Game = .onePiece
    let client: HTTPClient
    let cacheURL: URL
    let maxAge: TimeInterval

    private var catalog: OnePieceCatalog?
    private var loadingTask: Task<OnePieceCatalog, Error>?

    private static let base = "https://tcgcsv.com/tcgplayer/68"
    private static let batchSize = 8

    static var defaultCacheURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("onepiece-catalog.json")
    }

    init(client: HTTPClient, cacheURL: URL = OnePieceProvider.defaultCacheURL, maxAge: TimeInterval = 24 * 60 * 60) {
        self.client = client
        self.cacheURL = cacheURL
        self.maxAge = maxAge
    }

    /// `true` si hay catálogo fresco en memoria o en disco (no habrá descarga larga).
    nonisolated func hasFreshCache() -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: cacheURL.path),
              let modified = attrs[.modificationDate] as? Date else { return false }
        return Date().timeIntervalSince(modified) < maxAge
    }

    func search(_ query: String, filters: SearchFilters) async throws -> [CardSummary] {
        let catalog = try await loadCatalog()
        return catalog.search(query, filters: filters).map(OnePieceCatalog.summary)
    }

    func filterOptions() async throws -> FilterOptions {
        try await loadCatalog().filterOptions()
    }

    /// Impresión más barata de un número de carta (OP01-003). Nil si no existe.
    func cheapestPrinting(number: String) async throws -> (detail: CardDetail, quote: PriceQuote)? {
        let catalog = try await loadCatalog()
        let printings = catalog.printings(number: number).map(OnePieceCatalog.detail)
        if let cheapest = PrintingPicker.cheapest(printings) { return cheapest }
        // Sin precio en ninguna impresión: regresa la primera igual para que el deck no la pierda.
        guard let first = printings.first else { return nil }
        return (first, PriceQuote(source: .tcgplayer, variant: "Normal", currency: "USD", market: nil, low: nil, mid: nil, high: nil))
    }

    /// Para listas que solo traen nombre: primer número cuyo nombre coincide.
    func number(forName name: String) async throws -> String? {
        let catalog = try await loadCatalog()
        return catalog.search(name, limit: 1).first?.number
    }

    func detail(providerID: String) async throws -> CardDetail {
        let catalog = try await loadCatalog()
        guard let id = Int(providerID), let entry = catalog.entry(id: id) else { throw ProviderError.notFound }
        return OnePieceCatalog.detail(entry)
    }

    func printings(of detail: CardDetail) async throws -> [CardDetail] {
        let catalog = try await loadCatalog()
        let all = catalog.printings(number: detail.summary.canonicalKey).map(OnePieceCatalog.detail)
        return all.isEmpty ? [detail] : all
    }

    func loadCatalog(force: Bool = false) async throws -> OnePieceCatalog {
        if !force, let catalog, catalog.isFresh(maxAge: maxAge) { return catalog }
        if !force, let cached = readCache(), cached.isFresh(maxAge: maxAge) {
            catalog = cached
            return cached
        }
        if let loadingTask { return try await loadingTask.value }

        let task = Task { try await download() }
        loadingTask = task
        defer { loadingTask = nil }
        let built = try await task.value
        catalog = built
        writeCache(built)
        return built
    }

    func clearCache() {
        catalog = nil
        try? FileManager.default.removeItem(at: cacheURL)
    }

    // MARK: - Red y disco

    private func download() async throws -> OnePieceCatalog {
        let groups = try await client.json(TCGCSVResponse<TCGCSVGroup>.self, from: url("groups")).results
        var products: [TCGCSVProduct] = []
        var prices: [TCGCSVPrice] = []

        for batch in stride(from: 0, to: groups.count, by: Self.batchSize).map({ Array(groups[$0..<min($0 + Self.batchSize, groups.count)]) }) {
            try await withThrowingTaskGroup(of: ([TCGCSVProduct], [TCGCSVPrice]).self) { group in
                for g in batch {
                    group.addTask { [client] in
                        async let p = client.json(TCGCSVResponse<TCGCSVProduct>.self, from: self.url("\(g.groupId)/products"))
                        async let pr = client.json(TCGCSVResponse<TCGCSVPrice>.self, from: self.url("\(g.groupId)/prices"))
                        return try await (p.results, pr.results)
                    }
                }
                for try await (p, pr) in group {
                    products.append(contentsOf: p)
                    prices.append(contentsOf: pr)
                }
            }
        }
        return OnePieceCatalog.build(groups: groups, products: products, prices: prices)
    }

    private nonisolated func url(_ path: String) -> URL {
        URL(string: "\(Self.base)/\(path)")!
    }

    private func readCache() -> OnePieceCatalog? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(OnePieceCatalog.self, from: data)
    }

    private func writeCache(_ catalog: OnePieceCatalog) {
        guard let data = try? JSONEncoder().encode(catalog) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }
}
