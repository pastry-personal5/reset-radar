import Foundation
import Testing

@testable import ResetRadarDomain

@Suite struct HomeSlotResolutionTests {
    @Test func oneMatch() {
        let win = window()
        let (resolution, diagnostic) = HomeSlotResolver.resolve(
            .codexFiveHour, in: snapshot(windows: [win]), now: at(0))
        #expect(resolution == .window(win))
        #expect(diagnostic == nil)
    }

    @Test func noMatchAndEmptySnapshot() {
        for slot in HomeSlot.allCases {
            let (resolution, diagnostic) = HomeSlotResolver.resolve(
                slot, in: snapshot(windows: []), now: at(0))
            #expect(resolution == .unavailable && diagnostic == nil)
        }
    }

    @Test func nonDefaultWindowIsIgnored() {
        let snap = snapshot(windows: [window(limitID: "other", isDefault: false)])
        #expect(HomeSlotResolver.resolve(.codexFiveHour, in: snap, now: at(0)).0 == .unavailable)
    }

    @Test(arguments: [299, 301]) func nearbyDurationsAreIgnored(minutes: Int) {
        let snap = snapshot(windows: [window(minutes: minutes)])
        #expect(HomeSlotResolver.resolve(.codexFiveHour, in: snap, now: at(0)).0 == .unavailable)
    }

    @Test func twoDefaultWindowsWithSameDurationAreAmbiguous() {
        let first = window(limitID: "a")
        let second = window(limitID: "b")
        let (resolution, diagnostic) = HomeSlotResolver.resolve(
            .codexFiveHour, in: snapshot(windows: [first, second]), now: at(9))
        #expect(resolution == .ambiguous([first.id, second.id]))
        #expect(diagnostic == .ambiguousHomeSlot(.codexFiveHour, at: at(9)))
    }

    @Test func productsNeverCollide() {
        let snap = snapshot(windows: [
            window(product: .codex), window(product: .claudeCode, limitID: "five_hour"),
        ])
        #expect(HomeSlotResolver.resolve(.codexFiveHour, in: snap, now: at(0)).1 == nil)
        #expect(HomeSlotResolver.resolve(.claudeCodeFiveHour, in: snap, now: at(0)).1 == nil)
    }
}
