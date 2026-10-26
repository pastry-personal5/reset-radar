import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarTestSupport
import ResetRadarUI
import Testing

@testable import ResetRadar

@MainActor
@Suite struct ReaderRefreshTests {
    let harness = ReaderHarness()

    func pairedEnvironment(
        accounts: [AccountID] = [codexA, codexB, claude]
    ) async throws -> ReaderEnvironment {
        try await harness.seedPaired(committed: 5)
        let snapshot = ReaderHarness.snapshot(at: harness.clock.now, accounts: accounts)
        try await harness.store.transact { $0.snapshot = snapshot }
        let environment = harness.environment()
        await environment.reload()
        return environment
    }

    func line(_ environment: ReaderEnvironment, _ id: AccountID, _ product: ProductID) -> String? {
        environment.refresh.flatMap { RefreshFeedback.line(for: product, accountID: id, in: $0) }
    }

    @Test func homeRefreshPostsOneAllCodexRequestAndReportsEachAccountSeparately() async throws {
        let environment = try await pairedEnvironment()
        let task = Task { await environment.refreshHome() }
        await harness.clock.waitForSleepers()
        #expect(
            environment.refresh?.phase
                == .waitingForMac(deadline: harness.clock.now.addingTimeInterval(45)))
        let (id, target) = try #require(harness.posted())
        #expect(target == .allCodex)
        let result = try harness.result(
            id, target: .allCodex, [(codexA, .codexRead), (codexB, .sourceUnavailable)])
        try harness.relay.queueGet(harness.envelope(sequence: 6, results: [result]))
        harness.clock.advance(by: 5)
        await task.value
        #expect(environment.refresh?.phase == .finished(.completed(result.accountResults)))
        #expect(line(environment, codexA, .codex) == "The Collector Mac read this account.")
        #expect(
            line(environment, codexB, .codex)
                == "The Collector Mac could not read Codex for this account.")
        #expect(line(environment, claude, .claudeCode)?.contains("Relay read completed") == true)
        #expect(harness.relay.calls(.postRefreshRequest).count == 1)
        #expect(try await harness.state.committedSequence == 6)
    }

    @Test func aCodexAccountRefreshTargetsOnlyItsOpaqueAccountID() async throws {
        let environment = try await pairedEnvironment()
        let task = Task { await environment.refreshAccount(codexB) }
        await harness.clock.waitForSleepers()
        let (id, target) = try #require(harness.posted())
        #expect(target == .account(codexB))
        let result = try harness.result(id, target: target, [(codexB, .codexRead)])
        try harness.relay.queueGet(harness.envelope(sequence: 6, results: [result]))
        harness.clock.advance(by: 5)
        await task.value
        #expect(line(environment, codexB, .codex) == "The Collector Mac read this account.")
        #expect(line(environment, codexA, .codex) == nil)
    }

    @Test func claudeCodeRefreshesReadTheRelayAndNeverPost() async throws {
        let environment = try await pairedEnvironment(accounts: [claude])
        await environment.refreshAccount(claude)
        #expect(environment.refresh?.phase == .finished(.notRequested))
        await environment.refreshHome()
        #expect(environment.refresh?.phase == .finished(.notRequested))
        #expect(harness.relay.calls(.postRefreshRequest).isEmpty)
        #expect(harness.relay.calls(.getSnapshot).count == 2)
        #expect(line(environment, claude, .claudeCode)?.contains("cannot request") == true)
    }

    @Test func anUnansweredRequestTimesOutAtFortyFiveSecondsAndKeepsTheRows() async throws {
        let environment = try await pairedEnvironment()
        let task = Task { await environment.refreshHome() }
        await drive(harness.clock) { environment.refresh?.isRunning == false }
        await task.value
        #expect(environment.refresh?.phase == .finished(.timedOut))
        #expect(line(environment, codexA, .codex)?.contains("within 45 seconds") == true)
        #expect(environment.home.accounts.count == 3)
        #expect(harness.relay.calls(.postRefreshRequest).count == 1)
    }

    @Test func leavingTheForegroundEndsTheWaitWithoutRepostingOrAFalseOfflineStatus() async throws {
        let environment = try await pairedEnvironment()
        let first = Task { await environment.refreshHome() }
        await harness.clock.waitForSleepers()
        environment.sceneBecameInactive()
        await first.value
        #expect(environment.refresh?.phase == .cancelled)
        #expect(environment.details.transport == .current)
        #expect(try await harness.state.pendingManualRequest != nil)

        let (id, target) = try #require(harness.posted())
        let result = try harness.result(id, target: target, [(codexA, .codexRead)])
        try harness.relay.queueGet(.notModified, harness.envelope(sequence: 6, results: [result]))
        let resumed = Task { await environment.refreshHome() }
        await harness.clock.waitForSleepers()
        harness.clock.advance(by: 5)
        await resumed.value
        #expect(environment.refresh?.phase == .finished(.completed(result.accountResults)))
        #expect(harness.relay.calls(.postRefreshRequest).count == 1)
    }

    @Test func pullToRefreshReturnsOnceAcceptedWhileTheMacWaitContinues() async throws {
        let environment = try await pairedEnvironment()
        await environment.pullToRefresh()
        #expect(
            environment.refresh?.phase
                == .waitingForMac(deadline: harness.clock.now.addingTimeInterval(45)))
        await environment.pullToRefresh()
        #expect(harness.relay.calls(.postRefreshRequest).count == 1)
        await drive(harness.clock) { environment.refresh?.isRunning == false }
        try #require(environment.refresh?.phase == .finished(.timedOut))
        await environment.pullToRefresh(account: claude)
        #expect(environment.refresh?.phase == .finished(.notRequested))
    }

    @Test func forgetMacDiscardsARefreshThatIsStillWaiting() async throws {
        let environment = try await pairedEnvironment()
        let task = Task { await environment.refreshHome() }
        await harness.clock.waitForSleepers()
        await environment.forget()
        await task.value
        #expect(environment.refresh == nil)
        #expect(environment.home.accounts.isEmpty)
    }
}

@Suite struct ForegroundWaitClockTests {
    @Test func cancellingWaitsEndsASleepAndBeginRestoresOrdinarySleeping() async throws {
        let base = FakeAppClock(start: epoch)
        let clock = ForegroundWaitClock(base: base)
        let cancelled = Task { try await clock.sleep(for: .seconds(5)) }
        await base.waitForSleepers()
        clock.cancelWaits()
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        #expect(base.sleeperCount == 0)
        await #expect(throws: CancellationError.self) { try await clock.sleep(for: .seconds(1)) }

        clock.begin()
        #expect(!clock.waitsCancelled)
        let ordinary = Task { try await clock.sleep(for: .seconds(5)) }
        await base.waitForSleepers()
        base.advance(by: 5)
        try await ordinary.value
        #expect(clock.now == base.now)
    }
}
