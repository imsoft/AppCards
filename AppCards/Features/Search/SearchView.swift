import SwiftUI
import SwiftData

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query private var collection: [CollectionItem]
    @Query private var wishlist: [WishlistItem]

    @State private var game: Game = .magic
    @State private var query = ""
    @State private var results: [CardSummary] = []
    @State private var isLoading = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var filters: SearchFilters = .none
    @State private var showFilters = false
    @State private var showScanner = false
    @State private var deckTarget: CardDetail?
    @State private var wishTarget: CardDetail?
    @State private var viewerCard: CardSummary?

    private struct SearchKey: Equatable {
        let game: Game
        let query: String
        let filters: SearchFilters
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var ownership: OwnershipIndex { OwnershipIndex(collection: collection, wishlist: wishlist) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    SingleGameSelector(game: $game)
                    // Siempre visible, también mientras escribes en la búsqueda.
                    FilterButton(count: filters.activeCount, color: game.color) { showFilters = true }
                        .padding(.trailing, Theme.screenPadding)
                }
                ActiveFilterChips(filters: $filters, color: game.color) { showFilters = true }

                let index = ownership
                CardGrid(items: results) { card in
                    NavigationLink(value: card) {
                        CardGridTile(card: card, owned: index.owned(card), wished: index.isWished(card)) {
                            Task { await addToCollection(card) }
                        }
                    }
                    .buttonStyle(PressableStyle())
                    .contextMenu {
                        Button { viewerCard = card } label: { Label("Ver carta completa", systemImage: "arrow.up.left.and.arrow.down.right") }
                        Button { Task { await addToCollection(card) } } label: { Label("+1 colección", systemImage: "plus.square.on.square") }
                        Button { Task { deckTarget = try? await detail(card) } } label: { Label("Agregar a deck", systemImage: "plus.rectangle.on.rectangle") }
                        Button { Task { wishTarget = try? await detail(card) } } label: { Label("Lista de deseos", systemImage: "heart") }
                    }
                }
                .overlay { overlayContent }
                .animation(Motion.gentle, value: results.map(\.id))
            }
            .background(ScreenBackground(color: game.color))
            .animation(Motion.gentle, value: game)
            .navigationTitle("Buscar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showScanner = true } label: { Label("Escanear", systemImage: "camera") }
                }
            }
            .fullScreenCover(isPresented: $showScanner) { ScannerView(autoAddToCollection: false) }
            .sheet(isPresented: $showFilters) { FilterSheet(game: game, filters: $filters).presentationDetents([.large]) }
            .sheet(item: $deckTarget) { AddToDeckSheet(detail: $0) }
            .sheet(item: $wishTarget) { WishlistTargetSheet(detail: $0) }
            .cardViewer(for: $viewerCard)
            .onChange(of: game) { _, newValue in filters = .none; model.searchGame = newValue }
            .onAppear { model.searchGame = game }
            .navigationDestination(for: CardSummary.self) { card in
                CardDetailView(card: card)
            }
            .searchable(text: $query, prompt: "Nombre o número de carta")
            .autocorrectionDisabled()
            .task(id: SearchKey(game: game, query: trimmedQuery, filters: filters)) {
                await runSearch()
            }
        }
    }

    @ViewBuilder
    private var overlayContent: some View {
        if isLoading {
            VStack(spacing: 12) {
                ProgressView()
                if let statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
        } else if let errorMessage {
            ContentUnavailableView("No se pudo buscar", systemImage: "wifi.exclamationmark", description: Text(errorMessage))
        } else if trimmedQuery.isEmpty && filters.isEmpty {
            EmptyStateView(
                title: "Busca una carta de \(game.title)",
                message: "Escribe el nombre o número, usa los filtros para explorar un set, o escanea con la cámara.",
                color: game.color
            )
        } else if results.isEmpty {
            EmptyStateView(
                title: "Sin resultados",
                message: trimmedQuery.isEmpty ? "Ninguna carta coincide con esos filtros." : "No encontré \"\(trimmedQuery)\" en \(game.title). Revisa la ortografía o prueba con el número.",
                color: .gray
            )
        }
    }

    private func detail(_ card: CardSummary) async throws -> CardDetail {
        try await model.provider(for: card.game).detail(providerID: card.providerID)
    }

    private func addToCollection(_ card: CardSummary) async {
        do {
            let item = CollectionStore.add(try await detail(card), in: context)
            model.showToast("\(card.name) ×\(item.quantity) en colección")
        } catch {
            model.showToast("No se pudo agregar: \(error.localizedDescription)")
        }
    }

    private func runSearch() async {
        let text = trimmedQuery
        errorMessage = nil
        guard text.count >= 2 || (text.isEmpty && !filters.isEmpty) else {
            results = []
            isLoading = false
            return
        }
        do { try await Task.sleep(for: .milliseconds(450)) } catch { return }

        isLoading = true
        statusMessage = (game == .onePiece && !model.onePiece.hasFreshCache())
            ? "Descargando el catálogo de One Piece por primera vez (unos segundos)…"
            : nil
        defer { isLoading = false; statusMessage = nil }

        do {
            let found = try await model.provider(for: game).search(text, filters: filters)
            guard !Task.isCancelled else { return }
            let index = ownership
            // TCGdex no manda la rareza en la lista; si filtraste por rareza, todas son esa.
            let withRarity = found.map { card -> CardSummary in
                guard card.rarity == nil, let rarity = filters.rarity else { return card }
                var copy = card
                copy.rarity = rarity.title
                return copy
            }
            results = withRarity.filter { card in
                switch filters.ownership {
                case .all: true
                case .owned: index.owned(card) > 0
                case .missing: index.owned(card) == 0
                }
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            errorMessage = error.localizedDescription
        }
    }
}

extension CardDetail: Identifiable {
    var id: String { summary.id }
}

struct CardRow: View {
    let card: CardSummary
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            CardThumbnail(url: card.thumbnailURL, width: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.name)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                Text(card.setLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let rarity = card.rarity {
                    Text(rarity)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            if let price = card.price, let currency = card.priceCurrency {
                Spacer()
                PriceLabel(amount: price, currency: currency, style: .compact)
            }
        }
        .padding(.vertical, 2)
    }
}

struct CardThumbnail: View {
    let url: URL?
    var width: CGFloat = 44

    var body: some View {
        AsyncImage(url: ImageQuality.best(url, size: .grid)) { phase in
            switch phase {
            case .success(let image):
                image.resizable().interpolation(.high).antialiased(true).scaledToFit()
            case .failure:
                placeholder(symbol: "photo")
            default:
                placeholder(symbol: nil)
            }
        }
        .frame(width: width, height: width * 1.4)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func placeholder(symbol: String?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(.quaternary)
            if let symbol {
                Image(systemName: symbol).foregroundStyle(.secondary)
            }
        }
    }
}
