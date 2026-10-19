import Testing
import Foundation
@testable import AppCards

struct PriceTrackingTests {
    @Test func onePointPerDay() {
        let cal = Calendar.current
        let today = Date()
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        #expect(PriceTracking.hasPoint(on: today, in: [yesterday, today]))
        #expect(!PriceTracking.hasPoint(on: today, in: [yesterday]))
        #expect(!PriceTracking.hasPoint(on: today, in: []))
    }

    @Test func downsampleKeepsEnds() {
        let points = Array(0..<1000)
        let sampled = PriceTracking.downsample(points, limit: 10)
        #expect(sampled.count == 10)
        #expect(sampled.first == 0)
        #expect(sampled.last == 999)
        #expect(PriceTracking.downsample([1, 2, 3], limit: 10) == [1, 2, 3])
    }

    @Test func change() {
        #expect(PriceTracking.change(from: 10, to: 5) == -0.5)
        #expect(PriceTracking.change(from: 0, to: 5) == nil)
        #expect(PriceTracking.change(from: nil, to: 5) == nil)
    }
}

struct WishlistRuleTests {
    @Test func targetReached() {
        #expect(WishlistRule.status(current: 90, target: 100, previous: nil) == .reached)
        #expect(WishlistRule.status(current: 100, target: 100, previous: nil) == .reached)
        #expect(WishlistRule.status(current: 101, target: 100, previous: nil) == .waiting)
        #expect(WishlistRule.status(current: nil, target: 100, previous: nil) == .unknown)
    }

    @Test func dropWithoutTarget() {
        #expect(WishlistRule.status(current: 90, target: nil, previous: 100) == .dropped(-0.1))
        #expect(WishlistRule.status(current: 97, target: nil, previous: 100) == .waiting)
        #expect(WishlistRule.status(current: 90, target: nil, previous: nil) == .waiting)
    }

    @Test func notifiesOncePerDay() {
        let now = Date()
        let earlierToday = now.addingTimeInterval(-60)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        #expect(WishlistRule.shouldNotify(status: .reached, lastNotified: nil, now: now))
        #expect(!WishlistRule.shouldNotify(status: .reached, lastNotified: earlierToday, now: now))
        #expect(WishlistRule.shouldNotify(status: .reached, lastNotified: yesterday, now: now))
        #expect(!WishlistRule.shouldNotify(status: .waiting, lastNotified: nil, now: now))
        #expect(WishlistRule.shouldNotify(status: .dropped(-0.2), lastNotified: nil, now: now))
    }
}
