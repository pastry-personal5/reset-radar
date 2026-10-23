import Foundation
import ResetRadarDomain
import ResetRadarTestSupport
import Testing

@testable import ResetRadarApplication

/// Advances a fake clock in five-second steps whenever the code under test is sleeping.
private func drive(_ clock: FakeAppClock, until finished: Locked<Bool>) async {
    for _ in 0..<20_000 where !finished.snapshot {
        if clock.sleeperCount > 0 {
            clock.advance(by: 5)
        } else {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }
}

@Suite struct RequestMacRefreshTests {
    let rig = ReaderRig()

    func make() -> RequestMacRefresh {
        RequestMacRefresh(
            reader: rig.store, secrets: rig.secrets, relay: rig.relay, random: rig.random,
            clock: rig.clock, ingest: rig.makeIngest())
    }

    /// Starts a refresh and the deterministic clock driver; returns once both are done.
    func complete(_ use: RequestMacRefresh) async -> MacRefreshOutcome {
        let finished = Locked(false)
        let task = Task {
            let outcome = await use.run(scope: [.codex])
            finished.withLock { $0 = true }
            return outcome
        }
        await drive(rig.clock, until: finished)
        return await task.value
    }

    func postedID() -> RequestID? {
        if case .postRefreshRequest(let id) = rig.relay.calls(.postRefreshRequest).first {
            return id
        }
        return nil
    }

    func resultFor(
        _ id: RequestID, reader: ReaderID = readerA,
        outcome: ManualRefreshResult.Outcome = .codexRead
    ) -> ManualRefreshResult {
        ManualRefreshResult(
            readerID: reader, requestID: id, completedAt: rig.clock.now, outcome: outcome)
    }

    @Test func aClaudeCodeOnlyActionReadsOrdinarilyAndNeverPosts() async {
        rig.relay.queueGet(rig.envelope(sequence: 5))
        let outcome = await make().run(scope: [.claudeCode])
        #expect(outcome == .notRequested)
        #expect(rig.relay.calls(.getSnapshot).count == 1)
        #expect(rig.relay.calls(.postRefreshRequest).isEmpty)
    }

    @Test func aMatchingAuthenticatedResultCompletesTheRequest() async {
        rig.relay.queueGet(rig.envelope(sequence: 5))
        let use = make()
        let finished = Locked(false)
        let task = Task {
            let outcome = await use.run(scope: [.codex])
            finished.withLock { $0 = true }
            return outcome
        }
        await rig.clock.waitForSleepers()
        let id = postedID()
        #expect(id != nil)
        #expect(rig.relay.calls(.postRefreshRequest).count == 1)
        rig.relay.queueGet(
            .notModified,
            rig.envelope(sequence: 6, results: [resultFor(id ?? requestID(0))]))
        await drive(rig.clock, until: finished)
        #expect(await task.value == .completed(.codexRead))
        #expect(rig.relay.calls(.getSnapshot).count == 3)
        #expect(rig.store.state.pendingManualRequest == nil)
    }

    @Test func aFailedCodexReadIsReportedSeparately() async {
        rig.relay.queueGet(rig.envelope(sequence: 5))
        let use = make()
        let finished = Locked(false)
        let task = Task {
            let outcome = await use.run(scope: [.codex])
            finished.withLock { $0 = true }
            return outcome
        }
        await rig.clock.waitForSleepers()
        let id = postedID() ?? requestID(0)
        rig.relay.queueGet(
            rig.envelope(sequence: 6, results: [resultFor(id, outcome: .sourceUnavailable)]))
        await drive(rig.clock, until: finished)
        #expect(await task.value == .completed(.sourceUnavailable))
    }

    enum Signal: CaseIterable {
        case notModified, unrelatedPublication, otherReader, otherRequest
    }

    @Test(arguments: Signal.allCases) func nonCompletingSignalsTimeOut(signal: Signal) async {
        rig.relay.queueGet(rig.envelope(sequence: 5))
        let use = make()
        let finished = Locked(false)
        let task = Task {
            let outcome = await use.run(scope: [.codex])
            finished.withLock { $0 = true }
            return outcome
        }
        await rig.clock.waitForSleepers()
        let id = postedID() ?? requestID(0)
        switch signal {
        case .notModified:
            break
        case .unrelatedPublication:
            rig.relay.queueGet(rig.envelope(sequence: 6))
        case .otherReader:
            rig.relay.queueGet(rig.envelope(sequence: 6, results: [resultFor(id, reader: readerB)]))
        case .otherRequest:
            rig.relay.queueGet(rig.envelope(sequence: 6, results: [resultFor(requestID(0x77))]))
        }
        await drive(rig.clock, until: finished)
        #expect(await task.value == .timedOut)
        #expect(rig.relay.calls(.postRefreshRequest).count == 1)
        #expect(rig.store.state.pendingManualRequest == nil)
    }

    @Test func theWaitEndsExactlyAtFortyFiveSeconds() async {
        rig.relay.queueGet(rig.envelope(sequence: 5))
        let use = make()
        let finished = Locked(false)
        let task = Task {
            let outcome = await use.run(scope: [.codex])
            finished.withLock { $0 = true }
            return outcome
        }
        for _ in 0..<8 {
            await rig.clock.waitForSleepers()
            rig.clock.advance(by: 5)
            await Task.yield()
        }
        await rig.clock.waitForSleepers()
        rig.clock.advance(by: 4.999)
        try? await Task.sleep(for: .milliseconds(30))
        #expect(!finished.snapshot)
        rig.clock.advance(by: 0.001)
        #expect(await task.value == .timedOut)
    }

    @Test(arguments: [
        (RelayOutcome.requestRateLimited, MacRefreshOutcome.rateLimited),
        (.requestAlreadyCompleted, .alreadyCompleted),
        (.unauthorized, .failed(.authorizationRequired)),
        (.offline, .relayUnavailable),
    ])
    func refusalsDoNotRepost(refusal: RelayOutcome, expected: MacRefreshOutcome) async {
        rig.relay.queueGet(rig.envelope(sequence: 5))
        rig.relay.queuePost(refusal)
        #expect(await make().run(scope: [.codex]) == expected)
        #expect(rig.relay.calls(.postRefreshRequest).count == 1)
        #expect(rig.store.state.pendingManualRequest == nil)
    }

    @Test func anAwaitingActivationReaderReportsPairingPending() async {
        rig.store.seed { $0.awaitingActivation = true }
        #expect(await make().run(scope: [.codex]) == .pairingPending)
        #expect(rig.relay.calls.isEmpty)
    }

    @Test func theMarkerIsWrittenBeforeThePostAndSurvivesARelaunchWithoutReplay() async {
        rig.relay.queueGet(rig.envelope(sequence: 5))
        rig.relay.hold(.postRefreshRequest)
        let first = Task { await make().run(scope: [.codex]) }
        await rig.relay.waitForCalls(.postRefreshRequest)
        #expect(rig.store.state.pendingManualRequest != nil)
        rig.relay.release(.postRefreshRequest)
        await rig.clock.waitForSleepers()
        first.cancel()
        _ = await first.value
        #expect(rig.store.state.pendingManualRequest != nil)
        rig.clock.advance(by: 10)
        let outcome = await complete(make())
        #expect(outcome == .timedOut)
        #expect(rig.relay.calls(.postRefreshRequest).count == 1)
    }

    @Test func pollingSharesTheFetchClaimWithConcurrentIngests() async {
        rig.relay.queueGet(rig.envelope(sequence: 5))
        let use = make()
        let task = Task { await use.run(scope: [.codex]) }
        await rig.clock.waitForSleepers()
        rig.relay.holdNext(.getSnapshot)
        rig.clock.advance(by: 5)
        await rig.relay.waitForCalls(.getSnapshot, count: 2)
        #expect(await rig.makeIngest().run(trigger: .manual, inAppProcess: true) == .inProgress)
        rig.relay.release(.getSnapshot)
        task.cancel()
        _ = await task.value
    }
}
