import Foundation
import ResetRadarDomain
import Testing

@testable import ResetRadarMac

@Suite("Mac Home allowance rings")
struct MacAllowanceRingTests {
    private let observedAt = Date(timeIntervalSince1970: 1_800_000_000)

    private func account() throws -> AccountMetadata {
        let id = try #require(AccountID(data: Data(repeating: 0x21, count: AccountID.byteCount)))
        return AccountMetadata(id: id, product: .codex, number: 1)
    }

    private func window(
        for account: AccountMetadata, minutes: Int, percent: Double?,
        isDefault: Bool = true, resetsAt: Date? = nil
    ) throws -> AllowanceWindow {
        try AllowanceWindow(
            validating: RawWindow(
                accountID: account.id.hex, product: account.product.rawValue,
                limitID: "limit-\(minutes)-\(isDefault)", durationMinutes: minutes,
                isDefaultLimit: isDefault, reportState: .reported,
                resetsAt: resetsAt ?? observedAt.addingTimeInterval(86_400),
                observation: percent.map {
                    RawObservation(
                        usedPercent: $0, observedAt: observedAt, sourceVersion: "synthetic",
                        fractionDigits: minutes == 300 ? 0 : 1)
                }))
    }

    private func snapshot(
        account: AccountMetadata, windows: [AllowanceWindow],
        sourceState: SourceState = .reporting
    ) throws -> UsageSnapshot {
        let publisher = try #require(
            PublisherID(data: Data(repeating: 0x42, count: PublisherID.byteCount)))
        return try UsageSnapshot(
            publisherID: publisher, generatedAt: observedAt, heartbeatSeconds: 300,
            accounts: [account],
            sources: [
                AccountSource(
                    accountID: account.id, product: .codex, kind: .codexAppServer,
                    version: "synthetic", state: sourceState)
            ], windows: windows)
    }

    @Test func resolvesFiveHourAndWeeklyUsageByDefaultWindow() throws {
        let account = try account()
        let weekly = try window(for: account, minutes: 10_080, percent: 61.5)
        let extra = try window(
            for: account, minutes: 300, percent: 99, isDefault: false)
        let fiveHour = try window(for: account, minutes: 300, percent: 25)
        let snapshot = try snapshot(account: account, windows: [weekly, extra, fiveHour])

        let short = MacAllowanceDisplay.resolve(
            account: account, window: .fiveHour, snapshot: snapshot, now: observedAt)
        let long = MacAllowanceDisplay.resolve(
            account: account, window: .weekly, snapshot: snapshot, now: observedAt)

        #expect(short.state == .current)
        #expect(short.usedPercent == 25)
        #expect(short.fractionDigits == 0)
        #expect(long.state == .current)
        #expect(long.usedPercent == 61.5)
        #expect(long.fractionDigits == 1)
    }

    @Test func missingFiveHourDoesNotHideAvailableWeeklyUsage() throws {
        let account = try account()
        let weekly = try window(for: account, minutes: 10_080, percent: 42.5)
        let snapshot = try snapshot(account: account, windows: [weekly])

        let short = MacAllowanceDisplay.resolve(
            account: account, window: .fiveHour, snapshot: snapshot, now: observedAt)
        let long = MacAllowanceDisplay.resolve(
            account: account, window: .weekly, snapshot: snapshot, now: observedAt)

        #expect(short.state == .unavailable)
        #expect(short.usedPercent == nil)
        #expect(short.percentageText == nil)
        #expect(long.usedPercent == 42.5)
    }

    @Test func staleReadingRemainsVisibleButPostResetReadingDoesNot() throws {
        let account = try account()
        let fiveHour = try window(
            for: account, minutes: 300, percent: 37,
            resetsAt: observedAt.addingTimeInterval(1_800))
        let snapshot = try snapshot(
            account: account, windows: [fiveHour], sourceState: .sourceOffline)

        let stale = MacAllowanceDisplay.resolve(
            account: account, window: .fiveHour, snapshot: snapshot, now: observedAt)
        let waiting = MacAllowanceDisplay.resolve(
            account: account, window: .fiveHour, snapshot: snapshot,
            now: observedAt.addingTimeInterval(1_800))

        #expect(stale.state == .stale(reason: .sourceNotReporting))
        #expect(stale.usedPercent == 37)
        #expect(waiting.state == .resetAwaitingRefresh)
        #expect(waiting.usedPercent == nil)
        #expect(waiting.percentageText == nil)
    }

    @Test func menuSummaryShowsCurrentStaleAndMissingWindowsWithoutInventingUsage() throws {
        let account = try account()
        let fiveHour = try window(for: account, minutes: 300, percent: 37)
        let current = try snapshot(account: account, windows: [fiveHour])
        let stale = try snapshot(
            account: account, windows: [fiveHour], sourceState: .sourceOffline)

        #expect(
            MacMenuAccountSummary.line(account: account, snapshot: current, now: observedAt)
                == "Account #1 · 5h: 37% · Weekly: Unavailable")
        #expect(
            MacMenuAccountSummary.line(account: account, snapshot: stale, now: observedAt)
                == "Account #1 · 5h: 37% (Stale) · Weekly: Unavailable")
        #expect(
            MacMenuAccountSummary.line(account: account, snapshot: nil, now: observedAt)
                == "Account #1 · 5h: Unavailable · Weekly: Unavailable")
    }
}
