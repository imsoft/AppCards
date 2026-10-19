import Foundation
import SwiftData
import UserNotifications

/// Refresco diario: precios de colección y lista de deseos, historial, foto del valor de la colección y avisos.
@MainActor
final class PriceRefreshService {
    static let backgroundTaskID = "com.imsoft.appcards.refresh"
    private static let staleAfter: TimeInterval = 20 * 60 * 60

    let model: AppModel
    let context: ModelContext

    init(model: AppModel, context: ModelContext) {
        self.model = model
        self.context = context
    }

    struct Report: Equatable {
        var collectionUpdated = 0
        var wishlistUpdated = 0
        var notifications = 0
        var failures = 0
    }

    @discardableResult
    func runDaily(force: Bool = false) async -> Report {
        var report = Report()
        await refreshCollection(force: force, report: &report)
        await refreshWishlist(force: force, report: &report)
        snapshotCollection()
        try? context.save()
        model.lastRefreshAt = .now
        return report
    }

    // MARK: Colección

    private func refreshCollection(force: Bool, report: inout Report) async {
        let items = (try? context.fetch(FetchDescriptor<CollectionItem>())) ?? []
        for item in items where force || isStale(item.priceUpdatedAt) {
            do {
                let detail = try await model.provider(for: item.game).detail(providerID: item.providerID)
                if let quote = detail.quote(id: item.referenceQuoteID) ?? detail.cheapestQuote() {
                    item.apply(quote: quote)
                    recordPoint(cardID: item.cardID, game: item.game, quote: quote)
                    report.collectionUpdated += 1
                }
            } catch {
                report.failures += 1
            }
        }
    }

    // MARK: Lista de deseos

    private func refreshWishlist(force: Bool, report: inout Report) async {
        let items = (try? context.fetch(FetchDescriptor<WishlistItem>())) ?? []
        for item in items where force || isStale(item.lastCheckedAt) {
            do {
                let detail = try await model.provider(for: item.game).detail(providerID: item.providerID)
                guard let quote = detail.quote(id: item.quoteID) ?? detail.cheapestQuote() else { continue }
                item.record(quote: quote)
                recordPoint(cardID: item.cardID, game: item.game, quote: quote)
                report.wishlistUpdated += 1

                let status = self.status(of: item)
                if WishlistRule.shouldNotify(status: status, lastNotified: item.notifiedAt) {
                    await notify(item, status: status)
                    item.notifiedAt = .now
                    report.notifications += 1
                }
            } catch {
                report.failures += 1
            }
        }
    }

    func status(of item: WishlistItem) -> WishlistRule.Status {
        Self.status(of: item, converter: model.converter)
    }

    static func status(of item: WishlistItem, converter: CurrencyConverter) -> WishlistRule.Status {
        let current = item.lastPrice.flatMap { converter.convert($0, from: item.lastCurrency, to: item.targetCurrency) }
        let previous = item.previousPrice.flatMap { converter.convert($0, from: item.lastCurrency, to: item.targetCurrency) }
        return WishlistRule.status(current: current, target: item.targetPrice, previous: previous)
    }

    private func notify(_ item: WishlistItem, status: WishlistRule.Status) async {
        let content = UNMutableNotificationContent()
        content.title = item.name
        let price = item.lastPrice.map { model.display($0, currency: item.lastCurrency) } ?? ""
        switch status {
        case .reached:
            content.body = "Ya está en \(price), dentro de tu precio objetivo."
        case .dropped(let change):
            content.body = "Bajó \(Int((-change * 100).rounded()))%: ahora \(price)."
        default:
            return
        }
        content.sound = .default
        let request = UNNotificationRequest(identifier: "wishlist-\(item.cardID)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func requestNotificationPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    // MARK: Historial y snapshots

    func recordPoint(cardID: String, game: Game, quote: PriceQuote) {
        guard let price = quote.reference else { return }
        let quoteID = quote.id
        let descriptor = FetchDescriptor<PricePoint>(predicate: #Predicate { $0.cardID == cardID && $0.quoteID == quoteID })
        let existing = (try? context.fetch(descriptor)) ?? []
        if let today = existing.first(where: { Calendar.current.isDateInToday($0.date) }) {
            today.price = price
            return
        }
        context.insert(PricePoint(cardID: cardID, game: game, quote: quote, price: price))
    }

    func snapshotCollection() {
        let snapshots = (try? context.fetch(FetchDescriptor<CollectionSnapshot>())) ?? []
        let items = (try? context.fetch(FetchDescriptor<CollectionItem>())) ?? []
        let total = CollectionMath.total(lines: items.map(\.line), in: model.displayCurrency, converter: model.converter)
        if let today = snapshots.first(where: { Calendar.current.isDateInToday($0.date) }) {
            today.currency = total.currency
            today.referenceValue = total.referenceValue
            today.localValue = total.localValue
            today.cardCount = total.totalCards
        } else {
            context.insert(CollectionSnapshot(currency: total.currency, referenceValue: total.referenceValue, localValue: total.localValue, cardCount: total.totalCards))
        }
    }

    private func isStale(_ date: Date?) -> Bool {
        guard let date else { return true }
        return Date().timeIntervalSince(date) > Self.staleAfter
    }
}
