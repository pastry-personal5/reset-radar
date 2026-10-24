import Foundation
import Testing

@testable import ResetRadarDomain

@Suite struct AccountWindowResolutionTests {
    @Test func oneMatch() {
        let win = window()
        let (resolution, diagnostic) = AccountWindowResolver.resolve(
            codexFiveHour, in: snapshot(windows: [win]), now: at(0))
        #expect(resolution == .window(win))
        #expect(diagnostic == nil)
    }

    @Test func noMatchAndEmptySnapshot() {
        for accountWindow in [codexFiveHour, codexWeekly, claudeFiveHour, claudeWeekly] {
            let (resolution, diagnostic) = AccountWindowResolver.resolve(
                accountWindow, in: snapshot(windows: []), now: at(0))
            #expect(resolution == .unavailable && diagnostic == nil)
        }
    }

    @Test func nonDefaultWindowIsIgnored() {
        let snap = snapshot(windows: [window(limitID: "other", isDefault: false)])
        #expect(
            AccountWindowResolver.resolve(codexFiveHour, in: snap, now: at(0)).0
                == .unavailable)
    }

    @Test(arguments: [299, 301]) func nearbyDurationsAreIgnored(minutes: Int) {
        let snap = snapshot(windows: [window(minutes: minutes)])
        #expect(
            AccountWindowResolver.resolve(codexFiveHour, in: snap, now: at(0)).0
                == .unavailable)
    }

    @Test func twoDefaultWindowsWithSameDurationAreAmbiguous() {
        let first = window(limitID: "a")
        let second = window(limitID: "b")
        let (resolution, diagnostic) = AccountWindowResolver.resolve(
            codexFiveHour, in: snapshot(windows: [first, second]), now: at(9))
        #expect(resolution == .ambiguous([first.id, second.id]))
        #expect(
            diagnostic
                == .ambiguousAccountWindow(codexFiveHour, product: .codex, at: at(9)))
    }

    @Test func productsNeverCollide() {
        let snap = snapshot(windows: [
            window(product: .codex), window(product: .claudeCode, limitID: "five_hour"),
        ])
        #expect(AccountWindowResolver.resolve(codexFiveHour, in: snap, now: at(0)).1 == nil)
        #expect(AccountWindowResolver.resolve(claudeFiveHour, in: snap, now: at(0)).1 == nil)
    }

    @Test func accountWindowsNeverCollideAcrossRows() throws {
        let secondID = AccountID(data: bytes(16, 0xC3))!
        let first = window(accountID: codexAccountID, limitID: "codex")
        let second = window(accountID: secondID, limitID: "codex")
        let catalog = [
            AccountMetadata(id: codexAccountID, product: .codex, number: 1),
            AccountMetadata(id: secondID, product: .codex, number: 2),
        ]
        let sources = [
            AccountSource(
                accountID: codexAccountID, product: .codex, kind: .codexAppServer,
                version: "1", state: .reporting),
            AccountSource(
                accountID: secondID, product: .codex, kind: .codexAppServer, version: "1",
                state: .reporting),
        ]
        let snap = try UsageSnapshot(
            publisherID: publisher, generatedAt: at(0), heartbeatSeconds: 300,
            accounts: catalog, sources: sources, windows: [first, second])
        #expect(
            AccountWindowResolver.resolve(
                AccountWindow(accountID: codexAccountID, window: .fiveHour), in: snap, now: at(0)
            ).0 == .window(first))
        #expect(
            AccountWindowResolver.resolve(
                AccountWindow(accountID: secondID, window: .fiveHour), in: snap, now: at(0)
            ).0 == .window(second))
    }
}
