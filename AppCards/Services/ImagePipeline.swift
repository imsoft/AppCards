import SwiftUI
import UIKit

/// Descarga y guarda imágenes de cartas. Las descargas no se cancelan al hacer scroll:
/// si la carta vuelve a aparecer, se usa la que ya se bajó. Reintenta una vez si falla.
actor ImagePipeline {
    static let shared = ImagePipeline()

    private let cache = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]
    private var failed: Set<URL> = []

    init() {
        cache.countLimit = 400
    }

    func image(for url: URL) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        if failed.contains(url) { return nil }
        if let task = inFlight[url] { return await task.value }

        let task = Task.detached(priority: .userInitiated) { () -> UIImage? in
            for attempt in 0..<2 {
                var request = URLRequest(url: url)
                request.setValue(HTTPClient.userAgent, forHTTPHeaderField: "User-Agent")
                request.timeoutInterval = 20
                if let (data, response) = try? await URLSession.shared.data(for: request),
                   let http = response as? HTTPURLResponse {
                    if (200..<300).contains(http.statusCode), let image = UIImage(data: data) {
                        return image.preparingForDisplay() ?? image
                    }
                    if http.statusCode == 404 || http.statusCode == 403 { return nil } // no existe: no reintentar
                }
                if attempt == 0 { try? await Task.sleep(for: .milliseconds(600)) }
            }
            return nil
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image {
            cache.setObject(image, forKey: url as NSURL)
        } else {
            failed.insert(url)
        }
        return image
    }
}

/// Datos de una carta para buscar su imagen en otra fuente si la principal no la tiene.
struct ArtworkFallback: Hashable, Sendable {
    let game: Game
    let providerID: String
    let number: String
    let name: String

    init(game: Game, providerID: String, number: String, name: String) {
        self.game = game
        self.providerID = providerID
        self.number = number
        self.name = name
    }

    init(_ card: CardSummary) {
        self.init(game: card.game, providerID: card.providerID, number: card.number, name: card.name)
    }
}

/// Respaldos de imagen: Pokémon → TCGplayer (por productId de TCGdex); One Piece → sitio oficial por número.
actor ArtworkFallbackResolver {
    static let shared = ArtworkFallbackResolver()
    private var resolved: [ArtworkFallback: URL?] = [:]

    func url(for card: ArtworkFallback) async -> URL? {
        if let known = resolved[card] { return known }
        let url = await find(card)
        resolved[card] = url
        return url
    }

    private func find(_ card: ArtworkFallback) async -> URL? {
        switch card.game {
        case .pokemon:
            guard let detailURL = URL(string: "https://api.tcgdex.net/v2/en/cards/\(card.providerID)"),
                  let (data, _) = try? await URLSession.shared.data(from: detailURL),
                  let pid = TCGdexImageFallback.productID(from: data) else { return nil }
            return URL(string: "https://product-images.tcgplayer.com/fit-in/600x600/\(pid).jpg")
        case .onePiece:
            // Solo para la impresión normal: el sitio oficial usa otra numeración para artes alternos.
            guard PrintingStyle.label(for: card.name) == nil, !card.number.isEmpty else { return nil }
            return URL(string: "https://en.onepiece-cardgame.com/images/cardlist/card/\(card.number.uppercased()).png")
        case .magic:
            return nil
        }
    }
}

enum TCGdexImageFallback {
    /// El primer productId de TCGplayer en el detalle de TCGdex.
    static func productID(from data: Data) -> Int? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pricing = json["pricing"] as? [String: Any],
              let tcgplayer = pricing["tcgplayer"] as? [String: Any] else { return nil }
        for value in tcgplayer.values {
            if let variant = value as? [String: Any], let pid = variant["productId"] as? Int { return pid }
        }
        return nil
    }
}

/// Como `AsyncImage`, pero con caché propia, reintento y respaldo en otra fuente.
struct CachedAsyncImage<Content: View>: View {
    let url: URL?
    var fallback: ArtworkFallback?
    @ViewBuilder let content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase = .empty

    init(url: URL?, fallback: ArtworkFallback? = nil, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.fallback = fallback
        self.content = content
    }

    private struct Key: Hashable { let url: URL?; let fallback: ArtworkFallback? }

    var body: some View {
        content(phase)
            .task(id: Key(url: url, fallback: fallback)) { await load() }
    }

    private struct NotFound: Error {}

    private func load() async {
        if let url, let image = await ImagePipeline.shared.image(for: url) {
            phase = .success(Image(uiImage: image))
            return
        }
        if let fallback, let alternate = await ArtworkFallbackResolver.shared.url(for: fallback),
           let image = await ImagePipeline.shared.image(for: alternate) {
            phase = .success(Image(uiImage: image))
            return
        }
        phase = .failure(NotFound())
    }
}

/// Lo que se ve cuando una carta no tiene imagen en ninguna fuente.
struct MissingArtwork: View {
    var name: String?
    var number: String?
    var color: Color = .gray
    var compact = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [color.opacity(0.35), color.opacity(0.15)], startPoint: .top, endPoint: .bottom)
            VStack(spacing: compact ? 2 : 6) {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(compact ? .caption : .title3)
                    .foregroundStyle(color)
                if !compact {
                    if let name { Text(name).font(.caption.weight(.semibold)).multilineTextAlignment(.center).lineLimit(3) }
                    if let number, !number.isEmpty { Text(number).font(.caption2).foregroundStyle(.secondary) }
                    Text("Sin imagen aún").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(compact ? 2 : 8)
        }
    }
}
