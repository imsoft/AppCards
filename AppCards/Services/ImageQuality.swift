import Foundation

/// Elige la mejor resolución disponible de cada fuente de imágenes.
/// Se aplica también a URLs guardadas antes (colección, decks, deseos), así que lo viejo mejora solo.
enum ImageQuality {
    enum Size {
        /// Cuadrícula y filas: ~600 px de ancho.
        case grid
        /// Detalle y zoom: la más grande que haya.
        case full
    }

    static func best(_ url: URL?, size: Size) -> URL? {
        guard let url else { return nil }
        let string = url.absoluteString

        // Scryfall: small 146 px · normal 488 px · large 672 px
        if string.contains("cards.scryfall.io/") {
            let target = size == .grid ? "/normal/" : "/large/"
            for from in ["/small/", "/normal/", "/large/", "/png/", "/art_crop/", "/border_crop/"] where string.contains(from) {
                return URL(string: string.replacingOccurrences(of: from, with: target))
            }
            return url
        }

        // TCGdex: low.webp 245 px · high.webp 600 px
        if string.contains("assets.tcgdex.net/") {
            return URL(string: string.replacingOccurrences(of: "/low.webp", with: "/high.webp"))
        }

        // TCGplayer: el CDN viejo topa en 300 px; product-images da hasta 1000 px.
        if let id = tcgplayerProductID(string) {
            let box = size == .grid ? "600x600" : "1000x1000"
            return URL(string: "https://product-images.tcgplayer.com/fit-in/\(box)/\(id).jpg")
        }

        return url
    }

    static func tcgplayerProductID(_ string: String) -> String? {
        if string.contains("tcgplayer-cdn.tcgplayer.com/product/"),
           let match = string.firstMatch(pattern: #"/product/(\d+)_"#) {
            return match[1]
        }
        if string.contains("product-images.tcgplayer.com/"),
           let match = string.firstMatch(pattern: #"/(\d+)\.jpg"#) {
            return match[1]
        }
        return nil
    }
}
