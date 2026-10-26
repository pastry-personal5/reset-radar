import Foundation
import ResetRadarDomain
import ResetRadarTestSupport
import Testing

@testable import ResetRadarApplication

/// Records what the reader store held at the moment the Watch was sent a clear.
final class ProbeWatchLink: WatchLink, @unchecked Sendable {
    struct Probe: Equatable {
        let erasePending: Bool
        let cleanupPending: Bool
        let snapshotCleared: Bool
        let payload: WatchPayload
    }

    private let store: FakeReaderStore
    private let probes = Locked<[Probe]>([])

    init(store: FakeReaderStore) {
        self.store = store
    }

    var all: [Probe] { probes.snapshot }

    func sendContext(_ payload: WatchPayload) async throws {
        let state = store.state
        probes.withLock {
            $0.append(
                Probe(
                    erasePending: state.watchErasePending != nil,
                    cleanupPending: state.forgetCleanupPending,
                    snapshotCleared: state.snapshot == nil, payload: payload))
        }
    }

    func transferComplication(_ payload: WatchPayload) async throws {}
}

@Suite struct ForgetMacTests {
    let rig = ReaderRig()
    let scheduler = FakeNotificationScheduler()
    let activities = FakeLiveActivityController()

    init() {
        rig.store.seed { state in
            state.snapshot = snapshot(windows: [window()])
            state.committedSequence = 7
            state.etag = "\"e7\""
            state.hasSentToWatch = true
            state.watchDeliveryRevision = 4
            state.failureCount = 2
            state.transportStatus = .current
        }
    }

    func make(watch: (any WatchLink)?) -> ForgetMac {
        ForgetMac(
            reader: rig.store, secrets: rig.secrets, notifications: scheduler,
            activities: activities, reloader: rig.reloader, watch: watch)
    }

    @Test func oneTransactionPrecedesTheWatchSendAndAnyKeychainDeletion() async {
        let probe = ProbeWatchLink(store: rig.store)
        rig.secrets.setWriteFailure(.interactionRequired)
        #expect(await make(watch: probe).forget() == .cleanupPending)
        let sent = probe.all
        #expect(sent.count == 1)
        #expect(sent.first?.erasePending == true && sent.first?.cleanupPending == true)
        #expect(sent.first?.snapshotCleared == true)
        let state = rig.store.state
        #expect(state.snapshot == nil && state.etag == nil && state.pairing == nil)
        #expect(state.committedSequence == nil && state.lease == nil)
        #expect(state.installationID == installation)
        #expect(state.watchDeliveryRevision == 5)
        let clear = state.watchErasePending?.clear
        #expect(clear?.cleared == true && clear?.deliveryRevision == 5)
        #expect(clear?.installationID == installation && clear?.snapshot == nil)
        #expect(state.forgetCleanupPending)
    }

    @Test func aLateResultFromTheOldClaimCannotRestoreTheSnapshot() async {
        rig.relay.queueGet(rig.envelope(sequence: 9))
        rig.relay.holdNext(.getSnapshot)
        let ingest = rig.makeIngest()
        let late = Task { await ingest.run(trigger: .manual, inAppProcess: true) }
        await rig.relay.waitForCalls(.getSnapshot)
        #expect(await make(watch: nil).forget() == .complete)
        rig.relay.release(.getSnapshot)
        #expect(await late.value == .skipped)
        let state = rig.store.state
        #expect(state.snapshot == nil && state.etag == nil && state.committedSequence == nil)
        #expect(state.transportStatus == .notPaired)
    }

    @Test func successCancelsRemindersEndsActivitiesAndClearsTheMarker() async throws {
        let accountWindows = [codexFiveHour, codexWeekly, claudeFiveHour, claudeWeekly]
        for accountWindow in accountWindows {
            try await scheduler.schedule(
                ResetRequest(accountWindow: accountWindow, fireAt: at(10)))
            activities.seed(
                accountWindow,
                content: ActivityContent(
                    windowID: window().id, usedPercent: 1, resetsAt: at(10), observedAt: at(0)),
                staleDate: at(10))
        }
        #expect(await make(watch: FakeWatchLink()).forget() == .complete)
        #expect(Set(scheduler.cancelled) == Set(accountWindows))
        #expect(Set(activities.ends) == Set(accountWindows))
        #expect(activities.running.isEmpty)
        #expect(rig.secrets.names.isEmpty)
        #expect(!rig.store.state.forgetCleanupPending)
        #expect(rig.reloader.widgetReloads >= 1)
    }

    @Test func forgetMacAlsoRemovesMalformedOwnedRequests() async {
        scheduler.seedMalformedOwned(identifier: "reset.malformed")
        #expect(await make(watch: nil).forget() == .complete)
        #expect(!(await scheduler.ownedPendingIdentifiers()).contains("reset.malformed"))
    }

    @Test func aCleanupFailureHidesUsageBlocksPairingAndFetchAndRetryCompletes() async {
        let use = make(watch: nil)
        rig.secrets.setWriteFailure(.interactionRequired)
        #expect(await use.forget() == .cleanupPending)
        #expect(rig.store.state.forgetCleanupPending && rig.store.state.snapshot == nil)
        for trigger in FetchTrigger.allCases {
            #expect(await rig.makeIngest().run(trigger: trigger, inAppProcess: true) == .skipped)
        }
        let pairing = PairingRig()
        let accept = AcceptPairing(
            reader: rig.store, secrets: rig.secrets, relay: rig.relay, cipher: rig.cipher,
            codec: pairing.codec, clock: rig.clock, afterCommit: rig.pipeline())
        let preview = try? accept.preview(pairing.text())
        #expect(await accept.accept(preview!, confirmed: true) == .failed(.cleanupPending))
        rig.secrets.setWriteFailure(nil)
        #expect(await use.retryCleanup() == .complete)
        #expect(!rig.store.state.forgetCleanupPending)
        #expect(await use.retryCleanup() == .complete)
    }

    @Test func theIPadHasNoWatchStage() async {
        rig.store.seed { $0.hasSentToWatch = false }
        #expect(await make(watch: nil).forget() == .complete)
        let state = rig.store.state
        #expect(state.watchErasePending == nil)
        #expect(state.watchDeliveryRevision == 5)
    }

    @Test func aNewPairingIsAllowedWhileWatchErasureRemainsPending() async throws {
        let link = FakeWatchLink()
        #expect(await make(watch: link).forget() == .complete)
        let queued = rig.store.state.watchErasePending
        #expect(queued != nil)
        let pairing = PairingRig()
        let accept = AcceptPairing(
            reader: rig.store, secrets: rig.secrets, relay: rig.relay, cipher: rig.cipher,
            codec: pairing.codec, clock: rig.clock, afterCommit: rig.pipeline())
        rig.relay.queueGet(.awaitingFirstPublish)
        let outcome = await accept.accept(try accept.preview(pairing.text()), confirmed: true)
        #expect(outcome == .paired)
        #expect(rig.store.state.watchErasePending == queued)
        #expect(link.contexts.count == 1)
    }

    @Test func aFailedTransactionIsNeverReportedAsForgotten() async {
        rig.store.seed { state in
            state.pairing = ReaderPairing(
                endpoint: endpoint, publisherID: publisher, readerID: readerA, minimumSequence: 0,
                keyVersion: 1, registrationExpiresAt: epoch)
        }
        let use = make(watch: nil)
        rig.store.failNextTransactions(1)
        #expect(await use.forget() == .failed)
        #expect(rig.store.state.pairing != nil && rig.store.state.snapshot != nil)
        #expect(!rig.store.state.forgetCleanupPending)
        #expect(await use.retryCleanup() == .complete)
        #expect(rig.store.state.pairing == nil && rig.store.state.snapshot == nil)
    }

    @Test func retryingWithNothingLeftToForgetIsComplete() async {
        let use = make(watch: nil)
        #expect(await use.forget() == .complete)
        #expect(await use.retryCleanup() == .complete)
    }
}
