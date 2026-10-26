import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarTestSupport
import ResetRadarUI
import Testing

@testable import ResetRadar

@MainActor
@Suite struct ReaderDeliveryTests {
    let harness = ReaderHarness()

    @Test func aLaunchKeepsAnIntactPairingAndCommitsOnlyStrictlyNewerSnapshots() async throws {
        try await harness.seedPaired(committed: 5)
        let environment = harness.environment()
        try harness.relay.queueGet(harness.envelope(sequence: 6, percent: 50))
        await environment.sceneBecameActive()
        environment.sceneBecameInactive()
        #expect(environment.pairing?.state == .paired)
        #expect(try await harness.state.committedSequence == 6)
        #expect(environment.home.accounts.first?.standardWindows.first?.usedPercent == 50)

        harness.clock.advance(by: 61)
        try harness.relay.queueGet(harness.envelope(sequence: 4, percent: 99))
        await environment.foregroundTick()
        #expect(try await harness.state.committedSequence == 6)
        #expect(environment.home.accounts.first?.standardWindows.first?.usedPercent == 50)
    }

    @Test func offlineOrUnverifiableEnvelopesKeepTheRowsBesideASyncProblem() async throws {
        try await harness.seedPaired(committed: 5)
        let environment = harness.environment()
        harness.relay.queueGet(.offline)
        await environment.reload()
        await environment.foregroundIngestForTesting(.foregroundActivation)
        #expect(environment.home.accounts.count == 3)
        #expect(environment.setupStep == .syncProblem(.offline))

        try harness.relay.queueGet(
            harness.envelope(sequence: 9, key: SecretValue(Data(repeating: 0x99, count: 32))))
        await environment.foregroundIngestForTesting(.manual)
        #expect(environment.details.transport == .invalidSnapshot)
        try harness.relay.queueGet(harness.envelope(sequence: 9, publisher: publisherB))
        await environment.foregroundIngestForTesting(.manual)
        #expect(environment.setupStep == .syncProblem(.invalidSnapshot))
        #expect(try await harness.state.committedSequence == 5)
        #expect(environment.home.accounts.count == 3)
    }

    @Test func anUnexpectedNotModifiedWithoutACacheReadsOnceUnconditionally() async throws {
        try await harness.seedPaired(committed: nil)
        let environment = harness.environment()
        try harness.relay.queueGet(.notModified, harness.envelope(sequence: 3))
        await environment.foregroundIngestForTesting(.manual)
        #expect(
            harness.relay.calls(.getSnapshot) == [.getSnapshot(etag: nil), .getSnapshot(etag: nil)])
        #expect(try await harness.state.committedSequence == 3)
        #expect(environment.home.accounts.count == 3)
    }

    @Test func lockedSecretsBeforeFirstUnlockKeepTheCacheAndExplainTheBlocker() async throws {
        try await harness.seedPaired(committed: 5)
        harness.secrets.setReadFailure(.interactionRequired)
        let environment = harness.environment()
        await environment.foregroundIngestForTesting(.foregroundActivation)
        #expect(environment.setupStep == .secretsUnavailable)
        #expect(environment.home.accounts.count == 3)
        #expect(harness.relay.calls(.getSnapshot).isEmpty)
    }

    @Test func anIndependentStoreInstanceSeesTheLiveLeaseAndDoesNotFetch() async throws {
        try await harness.seedPaired(committed: 5)
        let widget = ReaderHarness(sharing: harness)
        widget.secrets.seed(.readToken, readToken)
        widget.secrets.seed(.contentKey, contentKey)
        harness.relay.hold(.getSnapshot)
        try harness.relay.queueGet(harness.envelope(sequence: 6))
        let app = harness.environment()
        let other = widget.environment()
        let first = Task { await app.foregroundIngestForTesting(.manual) }
        await harness.relay.waitForCalls(.getSnapshot)
        await other.foregroundIngestForTesting(.manual)
        #expect(widget.relay.calls(.getSnapshot).isEmpty)
        harness.relay.release(.getSnapshot)
        await first.value
        await other.reload()
        #expect(try await widget.state.committedSequence == 6)
        #expect(other.home.accounts.count == 3)
    }

    @Test func aResultArrivingAfterForgetMacNeverRestoresTheFormerCache() async throws {
        try await harness.seedPaired(committed: 5)
        let environment = harness.environment()
        await environment.reload()
        harness.relay.hold(.getSnapshot)
        try harness.relay.queueGet(harness.envelope(sequence: 9))
        let late = Task { await environment.foregroundIngestForTesting(.manual) }
        await harness.relay.waitForCalls(.getSnapshot)
        await environment.forget()
        harness.relay.release(.getSnapshot)
        await late.value
        let state = try await harness.state
        #expect(state.snapshot == nil)
        #expect(state.pairing == nil)
        #expect(state.committedSequence == nil)
        #expect(environment.home.accounts.isEmpty)
        #expect(environment.setupStep == .pairMac)
    }

    @Test func forgetMacErasesLocallyAndReportsPendingWatchErasureWithoutAReceipt() async throws {
        try await harness.seedPaired(committed: 5, hasSentToWatch: true)
        let environment = harness.environment()
        await environment.reload()
        await environment.forget()
        #expect(environment.forgetMessage == PairingSyncText.forgetOutcome(.complete))
        #expect(environment.pairing?.state == .notPaired)
        guard case .pending = environment.pairing?.watchErase else {
            Issue.record("the Watch clear must stay pending without a receipt")
            return
        }
        #expect(harness.secrets.names.isEmpty)
        #expect(environment.home.accounts.isEmpty)
    }

    @Test func iPadHasNoWatchErasureState() async throws {
        try await harness.seedPaired(committed: 5, hasSentToWatch: true)
        let environment = harness.environment(watch: false)
        await environment.forget()
        #expect(environment.pairing?.watchErase == nil)
        #expect(!environment.hasWatchStage)
    }

    @Test func interruptedCleanupIsRetryableHidesUsageAndBlocksANewPairing() async throws {
        try await harness.seedPaired(committed: 5)
        let environment = harness.environment()
        harness.secrets.setWriteFailure(.interactionRequired)
        await environment.forget()
        #expect(environment.forgetMessage == PairingSyncText.forgetOutcome(.cleanupPending))
        #expect(environment.setupStep == .cleanupPending)
        #expect(!PairingSyncText.acceptsPairingPackage(environment.pairing))
        #expect(environment.home.accounts.isEmpty)

        await environment.sceneBecameActive()
        environment.sceneBecameInactive()
        #expect(environment.pairing?.cleanupPending == true)
        harness.secrets.setWriteFailure(nil)
        await environment.retryCleanup()
        #expect(environment.forgetMessage == PairingSyncText.forgetOutcome(.complete))
        #expect(environment.setupStep == .pairMac)
        #expect(harness.secrets.names.isEmpty)
    }

    @Test func iPadSelectionRestoresAStoredAccountAndFallsBackWhenItDisappears() async throws {
        try await harness.seedPaired(committed: 5)
        harness.selection.save(claude)
        let environment = harness.environment(watch: false)
        await environment.reload()
        #expect(environment.selectedAccountID == claude)
        environment.select(codexB)
        #expect(harness.selection.value == codexB)

        let reduced = ReaderHarness.snapshot(at: harness.clock.now, accounts: [codexA, claude])
        try await harness.store.transact {
            $0.snapshot = reduced
            $0.committedSequence = 6
        }
        await environment.reload()
        #expect(environment.selectedAccountID == codexA)
        try await harness.store.transact { $0.snapshot = nil }
        await environment.reload()
        #expect(environment.selectedAccountID == nil)
    }
}

extension ReaderEnvironment {
    /// Runs one ingest for `trigger` and reloads, as the scene and ticker drivers do.
    func foregroundIngestForTesting(_ trigger: FetchTrigger) async {
        _ = await ingest.run(trigger: trigger, inAppProcess: true)
        await reload()
    }
}
