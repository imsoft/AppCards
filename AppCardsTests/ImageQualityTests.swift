import Testing
import Foundation
@testable import AppCards

struct ImageQualityTests {
    private func best(_ s: String, _ size: ImageQuality.Size) -> String? {
        ImageQuality.best(URL(string: s), size: size)?.absoluteString
    }

    @Test func scryfallUpgradesSmallImages() {
        let small = "https://cards.scryfall.io/small/front/7/6/abc.jpg?1"
        #expect(best(small, .grid) == "https://cards.scryfall.io/normal/front/7/6/abc.jpg?1")
        #expect(best(small, .full) == "https://cards.scryfall.io/large/front/7/6/abc.jpg?1")
    }

    @Test func tcgdexUsesHighWebp() {
        #expect(best("https://assets.tcgdex.net/en/swsh/swsh3/136/low.webp", .grid) == "https://assets.tcgdex.net/en/swsh/swsh3/136/high.webp")
    }

    @Test func tcgplayerMovesToProductImages() {
        #expect(best("https://tcgplayer-cdn.tcgplayer.com/product/453506_200w.jpg", .grid) == "https://product-images.tcgplayer.com/fit-in/600x600/453506.jpg")
        #expect(best("https://tcgplayer-cdn.tcgplayer.com/product/453506_400w.jpg", .full) == "https://product-images.tcgplayer.com/fit-in/1000x1000/453506.jpg")
        #expect(best("https://product-images.tcgplayer.com/fit-in/600x600/453506.jpg", .full) == "https://product-images.tcgplayer.com/fit-in/1000x1000/453506.jpg")
    }

    @Test func unknownURLsAndNilPassThrough() {
        #expect(best("https://example.com/card.png", .full) == "https://example.com/card.png")
        #expect(ImageQuality.best(nil, size: .grid) == nil)
    }
}
