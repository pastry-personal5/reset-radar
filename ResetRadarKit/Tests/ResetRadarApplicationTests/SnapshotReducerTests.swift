import Foundation
import ResetRadarDomain
import Testing

@testable import ResetRadarApplication

@Suite struct SnapshotReducerTests {
    func reduce(
        _ previous: UsageSnapshot?, _ reports: [SourceSnapshot], now: TimeInterval = 0
    ) throws -> (snapshot: UsageSnapshot, change: ChangeClass) {
        try SnapshotReducer.reduce(
            previous: previous, reports: reports,
            context: SnapshotAssemblyContext(
                accounts: [
                    AccountMetadata(id: codexAccountID, product: .codex, number: 1),
                    AccountMetadata(id: claudeAccountID, product: .claudeCode, number: 2),
                ], publisherID: publisher, heartbeatSeconds: 300, now: at(now)))
    }

    // MARK: change classification

    @Test func identicalReportIsNone() throws {
        let first = try reduce(nil, [report(windows: [window()])])
        let again = try reduce(first.snapshot, [report(windows: [window()])], now: 10)
        #expect(again.change == .none)
    }

    @Test func advancingOnlyObservedAtIsObservationOnly() throws {
        let first = try reduce(nil, [report(windows: [window()])])
        let later = report(windows: [window(observedAt: at(60))])
        #expect(try reduce(first.snapshot, [later], now: 60).change == .observationOnly)
    }

    @Test func aPercentageOrResetChangeIsMaterial() throws {
        let first = try reduce(nil, [report(windows: [window()])])
        let percent = report(windows: [window(percent: 43, observedAt: at(60))])
        #expect(try reduce(first.snapshot, [percent], now: 60).change == .material)
        let reset = report(windows: [window(resetsAt: at(7_300), observedAt: at(60))])
        #expect(try reduce(first.snapshot, [reset], now: 60).change == .material)
    }

    @Test func sourceStateWindowSetAndReportStateChangesAreTransitions() throws {
        let first = try reduce(
            nil, [report(windows: [window()]), report(.claudeCode, windows: [])])
        let down = report(state: .sourceOffline, windows: [window()])
        #expect(try reduce(first.snapshot, [down]).change == .transition)
        let added = report(windows: [window(), window(limitID: "extra", isDefault: false)])
        #expect(try reduce(first.snapshot, [added]).change == .transition)
        let removedFromView = try reduce(first.snapshot, [report(windows: [])])
        #expect(removedFromView.change == .transition)  // reported -> retained
        #expect(try reduce(nil, [report(windows: [window()])]).change == .transition)
    }

    @Test func aChangedDefaultBucketLeavesOneDefaultWindowPerDuration() throws {
        let first = try reduce(nil, [report(windows: [window(limitID: "old")])])
        let changed = report(windows: [window(limitID: "new", observedAt: at(60))])
        let result = try reduce(first.snapshot, [changed], now: 60)
        let defaults = result.snapshot.windows.filter {
            $0.isDefaultLimit && $0.durationMinutes == 300
        }
        #expect(defaults.map(\.limitID) == ["new"])
    }

    @Test func aStateOnlyReportWithANewScopeEvictsPriorScopeWindows() throws {
        let first = try reduce(nil, [report(windows: [window(scope: scopeA)])])
        let failure = SourceSnapshot(
            source: AccountSource(
                accountID: codexAccountID, product: .codex, kind: .codexAppServer, version: "1.0",
                state: .sourceOffline, providerScope: scopeB),
            windows: [], isCompleteReport: false)
        let result = try reduce(first.snapshot, [failure], now: 30)
        #expect(result.snapshot.windows.isEmpty)
    }

    @Test func aCodexAccountScopeChangeIsATransitionAndDropsPriorWindows() throws {
        let first = try reduce(nil, [report(windows: [window(scope: scopeA)])])
        let switched = report(windows: [window(scope: scopeB)])
        let result = try reduce(first.snapshot, [switched], now: 30)
        #expect(result.change == .transition)
        #expect(result.snapshot.windows.map(\.scope) == [scopeB])
    }

    @Test func aScopeChangeClearsOnlyItsLocalAccountRow() throws {
        let accounts = [
            AccountMetadata(id: codexAccountID, product: .codex, number: 1),
            AccountMetadata(id: otherCodexAccountID, product: .codex, number: 2),
        ]
        let context = SnapshotAssemblyContext(
            accounts: accounts, publisherID: publisher, heartbeatSeconds: 300, now: at(0))
        let first = try SnapshotReducer.reduce(
            previous: nil,
            reports: [
                report(windows: [window(scope: scopeA)]),
                report(
                    accountID: otherCodexAccountID,
                    windows: [window(accountID: otherCodexAccountID, scope: scopeA)]),
            ], context: context
        ).snapshot
        let switched = try SnapshotReducer.reduce(
            previous: first,
            reports: [report(windows: [window(scope: scopeB)])],
            context: SnapshotAssemblyContext(
                accounts: accounts, publisherID: publisher, heartbeatSeconds: 300, now: at(30))
        )
        .snapshot
        #expect(switched.windows.count == 2)
        #expect(
            switched.windows.first(where: { $0.accountID == codexAccountID })?.scope == scopeB)
        #expect(
            switched.windows.first(where: { $0.accountID == otherCodexAccountID })?.scope
                == scopeA)
    }

    // MARK: retention

    @Test func anAbsentWindowIsRetainedWithItsLastObservation() throws {
        let first = try reduce(nil, [report(windows: [window(observedAt: at(5))])])
        let result = try reduce(first.snapshot, [report(windows: [])], now: 100)
        let kept = try #require(result.snapshot.windows.first)
        #expect(kept.reportState == .retained)
        #expect(kept.observation?.observedAt == at(5))
        #expect(kept.observation?.usedPercent == 42)
    }

    @Test func aNewerReportReplacesARetainedWindow() throws {
        let first = try reduce(nil, [report(windows: [window()])])
        let retained = try reduce(first.snapshot, [report(windows: [])], now: 100)
        let renewed = report(windows: [window(percent: 50, observedAt: at(200))])
        let result = try reduce(retained.snapshot, [renewed], now: 200)
        let only = try #require(result.snapshot.windows.first)
        #expect(result.snapshot.windows.count == 1)
        #expect(only.reportState == .reported && only.observation?.usedPercent == 50)
    }

    @Test func aRetainedNonHomeWindowIsDroppedAtItsReset() throws {
        let extra = window(limitID: "extra", minutes: 60, isDefault: false, resetsAt: at(1_000))
        let first = try reduce(nil, [report(windows: [extra])])
        let before = try reduce(first.snapshot, [report(windows: [])], now: 999)
        #expect(before.snapshot.windows.count == 1)
        let boundary = try reduce(first.snapshot, [report(windows: [])], now: 1_000)
        #expect(boundary.snapshot.windows.isEmpty)
    }

    @Test func aRetainedNonStandardWindowWithoutAResetIsDroppedImmediately() throws {
        let extra = window(limitID: "extra", minutes: 60, isDefault: false, resetsAt: nil)
        let first = try reduce(nil, [report(windows: [extra])])
        #expect(try reduce(first.snapshot, [report(windows: [])], now: 1).snapshot.windows.isEmpty)
    }

    @Test func aRetainedStandardWindowPastItsResetStaysButResolvesUnavailable() throws {
        let first = try reduce(nil, [report(windows: [window(resetsAt: at(1_000))])])
        let result = try reduce(first.snapshot, [report(windows: [])], now: 5_000)
        #expect(result.snapshot.windows.count == 1)
        let (resolution, _) = AccountWindowResolver.resolve(
            codexFiveHour, in: result.snapshot, now: at(5_000))
        guard case .window(let resolved) = resolution else {
            Issue.record("expected a window")
            return
        }
        let presentation = PresentationPolicy.derive(
            window: resolved, source: result.snapshot.source(for: codexAccountID), now: at(5_000))
        #expect(presentation.state == .unavailable)
    }

    @Test func aRetainedStandardWindowWithNoResetStays() throws {
        let first = try reduce(nil, [report(windows: [window(resetsAt: nil)])])
        let result = try reduce(first.snapshot, [report(windows: [])], now: 9_000)
        #expect(result.snapshot.windows.count == 1)
    }

    @Test func twoProductsMergeIndependently() throws {
        let both = try reduce(
            nil,
            [
                report(windows: [window()]),
                report(.claudeCode, windows: [window(product: .claudeCode, percent: 10)]),
            ])
        let codexOnly = try reduce(
            both.snapshot, [report(windows: [window(percent: 60, observedAt: at(30))])], now: 30)
        let claude = codexOnly.snapshot.windows.first { $0.product == .claudeCode }
        #expect(claude?.reportState == .reported)
        #expect(claude?.observation?.usedPercent == 10)
        #expect(codexOnly.snapshot.windows.count == 2)
    }

    // MARK: state-only and invalid input

    @Test func aStateOnlyReportChangesSourceStateButNotWindowsOrObservations() throws {
        let first = try reduce(nil, [report(windows: [window(observedAt: at(5))])])
        let stateOnly = report(state: .signedOut, windows: [], complete: false)
        let result = try reduce(first.snapshot, [stateOnly], now: 50)
        #expect(result.snapshot.source(for: codexAccountID)?.state == .signedOut)
        #expect(result.snapshot.windows == first.snapshot.windows)
        #expect(result.snapshot.windows.first?.observation?.observedAt == at(5))
        #expect(result.change == .transition)
    }

    @Test func aProvenIdentityEvictionClearsOnlyThatAccountRowsWindows() throws {
        let first = try reduce(
            nil,
            [
                report(windows: [window(scope: scopeA)]),
                report(.claudeCode, windows: [window(product: .claudeCode)]),
            ])
        let eviction = SourceSnapshot(
            source: AccountSource(
                accountID: codexAccountID, product: .codex, kind: .codexAppServer,
                version: "1", state: .incompatible, providerScope: scopeA),
            windows: [], isCompleteReport: false, clearsWindows: true)
        let result = try reduce(first.snapshot, [eviction])
        #expect(result.snapshot.windows.map(\.product) == [.claudeCode])
        #expect(result.snapshot.source(for: codexAccountID)?.state == .incompatible)
    }

    @Test func aWindowOfTheWrongProductIsDroppedWithADiagnosticAndItsSiblingSurvives() throws {
        let stray = window(product: .claudeCode)
        let result = try reduce(nil, [report(windows: [window(), stray])])
        #expect(result.snapshot.windows.map(\.product) == [.codex])
        #expect(result.snapshot.diagnostics.map(\.category) == [.unknownProduct])
    }

    @Test func aDuplicateWindowIsDroppedWithADiagnostic() throws {
        let result = try reduce(nil, [report(windows: [window(), window(percent: 99)])])
        #expect(result.snapshot.windows.count == 1)
        #expect(result.snapshot.windows.first?.observation?.usedPercent == 42)
        #expect(result.snapshot.diagnostics.map(\.category) == [.duplicateWindow])
    }

    @Test func resultsAreCarriedAndExpire() throws {
        let result = try ManualRefreshResult(
            readerID: readerA, requestID: requestID(1), completedAt: at(0),
            target: .allCodex,
            accountResults: [
                ManualRefreshAccountResult(accountID: codexAccountID, outcome: .codexRead)
            ])
        let first = snapshot(windows: [window()], results: [result])
        let kept = try reduce(first, [report(windows: [window()])], now: 120)
        #expect(kept.snapshot.manualRefreshResults == [result])
        let gone = try reduce(first, [report(windows: [window()])], now: 121)
        #expect(gone.snapshot.manualRefreshResults.isEmpty)
    }

    @Test func anInvalidHeartbeatThrows() {
        #expect(throws: UsageSnapshotError.invalidHeartbeat) {
            try SnapshotReducer.reduce(
                previous: nil, reports: [],
                context: SnapshotAssemblyContext(
                    accounts: [], publisherID: publisher, heartbeatSeconds: 0, now: at(0)))
        }
    }
}
