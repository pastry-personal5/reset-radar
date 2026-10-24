import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarTestSupport
import Testing

@testable import ResetRadarStorage

private let contentKey = SecretValue(bytes(32, 0x44))
private let readToken = SecretValue(bytes(32, 0x55))

private final class LoggingStep: AfterCommitStep, @unchecked Sendable {
    let name: String
    let log: FakeEventLog

    init(_ name: String, log: FakeEventLog) {
        self.name = name
        self.log = log
    }

    func afterCommit(_ event: CommitEvent) async { log.append(name) }
}

/// A stage that parks until released, to hold an app commit open while a widget commits.
private final class ParkingStep: AfterCommitStep, @unchecked Sendable {
    private let entered = AsyncStream.makeStream(of: Void.self)
    private let release = AsyncStream.makeStream(of: Void.self)

    func waitUntilEntered() async {
        for await _ in entered.stream { return }
    }

    func resume() { release.continuation.yield() }

    func afterCommit(_ event: CommitEvent) async {
        entered.continuation.yield()
        for await _ in release.stream { return }
    }
}

private final class ReaderRig: @unchecked Sendable {
    let directory = TemporaryDirectory()
    let clock = FakeAppClock(start: epoch)
    let secrets = FakeSecretStore()
    let cipher = FakeEnvelopeCipher()
    let relay = FakeRelayGateway()
    let random = FakeSecretGenerator()
    let sink = FakeDiagnosticsSink()
    let reloader = FakeSurfaceReloader()
    let log = FakeEventLog()

    init(paired: Bool = true) async throws {
        secrets.seed(.readToken, readToken)
        secrets.seed(.contentKey, contentKey)
        if paired {
            try await openStore().transact { state in
                state.pairing = ReaderPairing(
                    endpoint: endpoint, publisherID: publisher, readerID: readerA,
                    minimumSequence: 3, keyVersion: 1, registrationExpiresAt: epoch)
                state.transportStatus = .awaitingFirstPublish
            }
        }
    }

    func openStore() -> FileReaderStore {
        FileReaderStore(locations: StorageLocations(root: directory.url, flavor: .release))
    }

    func pipeline(
        _ store: FileReaderStore, liveActivities: (any AfterCommitStep)? = nil
    ) -> AfterCommitPipeline {
        AfterCommitPipeline(
            reader: store, reloader: reloader,
            notifications: LoggingStep("notifications", log: log),
            liveActivities: liveActivities ?? LoggingStep("liveActivities", log: log),
            watch: LoggingStep("watch", log: log))
    }

    func makeIngest(
        _ store: FileReaderStore, liveActivities: (any AfterCommitStep)? = nil
    ) -> IngestRelaySnapshot {
        IngestRelaySnapshot(
            reader: store, secrets: secrets, cipher: cipher, relay: relay, random: random,
            clock: clock, diagnostics: sink,
            afterCommit: pipeline(store, liveActivities: liveActivities))
    }

    func envelope(sequence: UInt64) -> RelayOutcome {
        let header = EnvelopeHeader(
            protocolVersion: 1, envelopeVersion: 1, publisherID: publisher, sequence: sequence,
            keyVersion: 1)
        let body = snapshot(percent: Double(sequence), generatedAt: clock.now)
        // swiftlint:disable:next force_try
        let sealed = try! cipher.seal(body, header: header, key: contentKey)
        return .snapshot(sealed.encoded, etag: "\"e\(sequence)\"", sequence: sequence)
    }

    func makeForget(_ store: FileReaderStore, watch: (any WatchLink)? = nil) -> ForgetMac {
        ForgetMac(
            reader: store, secrets: secrets, notifications: FakeNotificationScheduler(),
            activities: FakeLiveActivityController(), reloader: reloader, watch: watch)
    }
}

struct ReaderIntegrationTests {
    @Test func concurrentLoserIsInProgressAndExpiredClaimResultIsRejected() async throws {
        let rig = try await ReaderRig()
        let first = rig.makeIngest(rig.openStore())
        let second = rig.makeIngest(rig.openStore())
        rig.relay.queueGet(rig.envelope(sequence: 5), rig.envelope(sequence: 6))
        rig.relay.holdNext(.getSnapshot)
        let late = Task { await first.run(trigger: .manual, inAppProcess: true) }
        await rig.relay.waitForCalls(.getSnapshot)
        #expect(await second.run(trigger: .manual, inAppProcess: true) == .inProgress)
        rig.clock.advance(by: ReaderClaims.leaseDuration)
        #expect(await second.run(trigger: .manual, inAppProcess: true) == .committed)
        rig.relay.release(.getSnapshot)
        #expect(await late.value == .skipped)
        let state = try await rig.openStore().load()
        #expect(state.committedSequence == 5)
        #expect(state.snapshot == snapshot(percent: 5, generatedAt: epoch))
    }

    @Test func aCachedETagWithNoSnapshotIsNotSent() async throws {
        let rig = try await ReaderRig()
        try await rig.openStore().transact { $0.etag = "\"stale\"" }
        rig.relay.queueGet(rig.envelope(sequence: 5))
        let outcome = await rig.makeIngest(rig.openStore()).run(
            trigger: .manual, inAppProcess: true)
        #expect(outcome == .committed)
        #expect(rig.relay.calls(.getSnapshot) == [.getSnapshot(etag: nil)])
    }

    @Test func anInterruptedManualWaitResumesFromDiskWithoutReposting() async throws {
        let rig = try await ReaderRig()
        let due = rig.clock.now.addingTimeInterval(10)
        let marker = PendingManualRequest(requestID: requestID(1), target: .allCodex, deadline: due)
        try await rig.openStore().transact { $0.pendingManualRequest = marker }
        rig.relay.queueGet(rig.envelope(sequence: 5))
        let store = rig.openStore()
        let refresh = RequestMacRefresh(
            reader: store, secrets: rig.secrets, relay: rig.relay, random: rig.random,
            clock: rig.clock, ingest: rig.makeIngest(store))
        let resumed = Task { await refresh.run(scope: [.codex]) }
        await rig.clock.waitForSleepers()
        rig.clock.advance(by: 5)
        await rig.clock.waitForSleepers()
        rig.clock.advance(by: 5)
        let outcome = await resumed.value
        #expect(outcome == .timedOut || outcome == .macAsleepOrPending)
        #expect(rig.relay.calls(.postRefreshRequest).isEmpty)
        #expect(try await rig.openStore().load().pendingManualRequest == nil)
    }

    @Test func widgetCommitSetsTheFlagWithTheSnapshotAndRelaunchKeepsIt() async throws {
        let rig = try await ReaderRig()
        rig.relay.queueGet(rig.envelope(sequence: 5))
        let outcome = await rig.makeIngest(rig.openStore())
            .run(trigger: .widgetReload, inAppProcess: false)
        #expect(outcome == .committed)
        let relaunched = rig.openStore()
        let state = try await relaunched.load()
        #expect(state.snapshot != nil && state.committedSequence == 5)
        #expect(state.needsAppReconcile)
        #expect(rig.log.all == ["notifications"])
        await rig.pipeline(relaunched).reconcilePending()
        #expect(try await rig.openStore().load().needsAppReconcile == false)
        #expect(rig.log.all == ["notifications", "notifications", "liveActivities", "watch"])
    }

    @Test func anInterruptedNotificationPassKeepsTheReconcileFlagOnDisk() async throws {
        let rig = try await ReaderRig()
        rig.relay.queueGet(rig.envelope(sequence: 5))
        #expect(
            await rig.makeIngest(rig.openStore()).run(
                trigger: .widgetReload, inAppProcess: false) == .committed)
        let parking = ParkingStep()
        let pass = Task {
            await rig.pipeline(rig.openStore(), liveActivities: parking).reconcilePending()
        }
        await parking.waitUntilEntered()
        #expect(try await rig.openStore().load().needsAppReconcile)
        parking.resume()
        await pass.value
        #expect(try await rig.openStore().load().needsAppReconcile == false)
    }

    @Test func aWidgetCommitDuringAnAppRunKeepsTheFlagForTheNewerSnapshot() async throws {
        let rig = try await ReaderRig()
        rig.relay.queueGet(rig.envelope(sequence: 5))
        let parking = ParkingStep()
        let app = rig.makeIngest(rig.openStore(), liveActivities: parking)
        let appRun = Task { await app.run(trigger: .manual, inAppProcess: true) }
        await parking.waitUntilEntered()
        rig.clock.advance(by: 600)
        rig.relay.queueGet(rig.envelope(sequence: 6))
        let widget = await rig.makeIngest(rig.openStore())
            .run(trigger: .widgetReload, inAppProcess: false)
        #expect(widget == .committed)
        parking.resume()
        #expect(await appRun.value == .committed)
        let state = try await rig.openStore().load()
        #expect(state.committedSequence == 6)
        #expect(state.needsAppReconcile)
    }

    @Test func forgetMacInterruptionSurvivesRelaunchAndRetryCompletes() async throws {
        let rig = try await ReaderRig()
        try await rig.openStore().transact { state in
            state.snapshot = snapshot()
            state.committedSequence = 7
            state.etag = "\"e7\""
            state.hasSentToWatch = true
            state.watchDeliveryRevision = 4
        }
        let installationID = try await rig.openStore().load().installationID
        rig.secrets.setWriteFailure(.interactionRequired)
        #expect(
            await rig.makeForget(rig.openStore(), watch: FakeWatchLink()).forget()
                == .cleanupPending)
        let relaunched = rig.openStore()
        let state = try await relaunched.load()
        #expect(state.forgetCleanupPending)
        #expect(state.snapshot == nil && state.pairing == nil && state.etag == nil)
        #expect(state.installationID == installationID)
        #expect(state.watchErasePending?.clear.deliveryRevision == 5)
        rig.secrets.setWriteFailure(nil)
        #expect(await rig.makeForget(relaunched).retryCleanup() == .complete)
        let done = try await rig.openStore().load()
        #expect(!done.forgetCleanupPending)
        #expect(done.watchErasePending == state.watchErasePending)
        #expect(done.installationID == installationID)
    }

    @Test func aLateResultAfterForgetMacCannotRestoreTheSnapshot() async throws {
        let rig = try await ReaderRig()
        rig.relay.queueGet(rig.envelope(sequence: 9))
        rig.relay.holdNext(.getSnapshot)
        let ingest = rig.makeIngest(rig.openStore())
        let late = Task { await ingest.run(trigger: .manual, inAppProcess: true) }
        await rig.relay.waitForCalls(.getSnapshot)
        #expect(await rig.makeForget(rig.openStore()).forget() == .complete)
        rig.relay.release(.getSnapshot)
        #expect(await late.value == .skipped)
        let state = try await rig.openStore().load()
        #expect(state.snapshot == nil && state.etag == nil && state.committedSequence == nil)
        #expect(state.transportStatus == .notPaired)
    }

    @Test func aNewPairingWaitsForTheSavedWatchEraseReceipt() async throws {
        let rig = try await ReaderRig()
        let watch = FakeWatchLink()
        try await rig.openStore().transact { state in
            state.snapshot = snapshot()
            state.hasSentToWatch = true
            state.watchDeliveryRevision = 4
        }
        #expect(await rig.makeForget(rig.openStore(), watch: watch).forget() == .complete)
        let pending = try #require(await rig.openStore().load().watchErasePending)
        let codec = FakePairingCodec()
        let package = PairingPackage(
            relayEndpoint: endpoint, readerID: readerA, readToken: readToken.reveal(),
            contentKey: contentKey.reveal(), publisherID: publisher, keyVersion: 1,
            minimumSequence: 3, registrationExpiresAt: rig.clock.now.addingTimeInterval(300))
        let encoded = try codec.encode(package)
        rig.relay.queueGet(.awaitingFirstPublish)
        let store = rig.openStore()
        let accept = AcceptPairing(
            reader: store, secrets: rig.secrets, relay: rig.relay, cipher: rig.cipher,
            codec: codec, clock: rig.clock, afterCommit: rig.pipeline(store))
        #expect(await accept.accept(try accept.preview(encoded), confirmed: true) == .paired)
        try await rig.openStore().transact { state in state.snapshot = snapshot() }
        let forward = ForwardToWatch(
            reader: rig.openStore(), preferences: DefaultsPreferenceStore(defaults: UserDefaults()),
            watch: watch, clock: rig.clock)
        let event = CommitEvent(snapshot: snapshot(), process: .app)
        await forward.send(after: event)
        #expect(watch.contexts.last == pending.clear)
        #expect(try await rig.openStore().load().watchErasePending == pending)
        let receipt = WatchEraseReceipt(
            installationID: pending.clear.installationID,
            deliveryRevision: pending.revision)
        let confirm = ConfirmWatchErase(reader: rig.openStore(), clock: rig.clock, forward: forward)
        #expect(await confirm.confirm(receipt) == .confirmed)
        #expect(watch.contexts.last?.cleared == false)
        #expect(try await rig.openStore().load().watchErasePending == nil)
    }
}

/// A Mac whose relay metadata and snapshot live in files; `open…` calls are relaunches.
private final class PublisherRig: @unchecked Sendable {
    let directory = TemporaryDirectory()
    let clock = FakeAppClock(start: epoch)
    let secrets = FakeSecretStore()
    let cipher = FakeEnvelopeCipher()
    let relay = FakeRelayGateway()
    let random = FakeSecretGenerator()
    let sink = FakeDiagnosticsSink()

    var locations: StorageLocations { StorageLocations(root: directory.url, flavor: .release) }

    init(lifecycle: RelayLifecycle = .active) async throws {
        secrets.seed(.contentKey, SecretValue(bytes(32, 0x11)))
        secrets.seed(.writeToken, SecretValue(bytes(32, 0x22)))
        secrets.seed(.adminToken, SecretValue(bytes(32, 0x33)))
        try await openPublisherStore().transact { state in
            state.lifecycle = lifecycle
            state.endpoint = endpoint
            state.publisherID = publisher
            state.devices = [PairedDevice(readerID: readerA, name: "Phone", pairedAt: epoch)]
        }
    }

    func openPublisherStore() -> FilePublisherStore { FilePublisherStore(locations: locations) }
    func openSnapshotStore() -> FileSnapshotStore { FileSnapshotStore(locations: locations) }

    func makePublisher(_ store: FilePublisherStore) -> PublishSnapshot {
        PublishSnapshot(
            publisher: store, secrets: secrets, cipher: cipher, relay: relay, diagnostics: sink,
            clock: clock, random: random)
    }

    func publish(_ use: PublishSnapshot) async -> PublishOutcome {
        await use.publish(
            snapshot(generatedAt: clock.now), change: .transition, trigger: .change)
    }
}

struct PublisherIntegrationTests {
    @Test func aRestartBetweenTheSequenceWriteAndAFailedSendNeverReusesTheNumber() async throws {
        let rig = try await PublisherRig()
        rig.relay.queuePut(.offline, .accepted(sequence: nil))
        let first = rig.makePublisher(rig.openPublisherStore())
        #expect(await rig.publish(first) == .backoff(until: rig.clock.now.addingTimeInterval(15)))
        #expect(try await rig.openPublisherStore().load().sequence == 1)
        rig.clock.advance(by: 15)
        let relaunched = rig.makePublisher(rig.openPublisherStore())
        #expect(await rig.publish(relaunched) == .published(sequence: 2))
        #expect(rig.cipher.sealedHeaders.map(\.sequence) == [1, 2])
    }

    @Test func setupPendingSurvivesRelaunchAndBlocksPublication() async throws {
        let rig = try await PublisherRig(lifecycle: .notConfigured)
        let store = rig.openPublisherStore()
        let setUp = SetUpRelay(
            publisher: store, secrets: rig.secrets, random: rig.random, relay: rig.relay,
            snapshots: rig.openSnapshotStore(), publishing: rig.makePublisher(store),
            clock: rig.clock, heartbeatSeconds: 300)
        _ = try await setUp.prepare(endpoint: endpoint)
        let relaunched = rig.openPublisherStore()
        #expect(try await relaunched.load().lifecycle == .setupPending)
        #expect(await rig.publish(rig.makePublisher(relaunched)) == .paused)
        #expect(rig.relay.calls(.putSnapshot).isEmpty)
    }

    @Test func destroyPendingSurvivesRelaunchBlocksPublicationAndRetrySucceeds() async throws {
        let rig = try await PublisherRig()
        rig.relay.queueDestroy(.offline)
        let store = rig.openPublisherStore()
        let destroy = DestroyRelay(
            publisher: store, secrets: rig.secrets, relay: rig.relay,
            publishing: rig.makePublisher(store))
        #expect(await destroy.run() == .remoteFailed(.offline))
        let relaunched = rig.openPublisherStore()
        let state = try await relaunched.load()
        #expect(state.lifecycle == .destroyPending)
        #expect(state.endpoint == endpoint && state.devices.count == 1)
        #expect(await rig.publish(rig.makePublisher(relaunched)) == .paused)
        let retry = DestroyRelay(
            publisher: relaunched, secrets: rig.secrets, relay: rig.relay,
            publishing: rig.makePublisher(relaunched))
        #expect(await retry.run() == .destroyed)
    }

    @Test func aHandledManualRequestSurvivesRelaunchWithoutAnotherCodexRead() async throws {
        let rig = try await PublisherRig()
        let codex = FakeUsageSource(product: .codex, clock: rig.clock)
        let claude = FakeUsageSource(product: .claudeCode, clock: rig.clock)
        func makeHandler() -> HandleManualRefreshRequests {
            let store = rig.openPublisherStore()
            let snapshots = rig.openSnapshotStore()
            return HandleManualRefreshRequests(
                publisher: store, snapshots: snapshots,
                collector: CollectUsage(
                    snapshots: snapshots, diagnostics: rig.sink, clock: rig.clock,
                    catalogStore: FakeAccountCatalogStore(accounts: snapshot().accounts),
                    publisherID: publisher, heartbeatSeconds: 300),
                sources: [codex, claude], publishing: rig.makePublisher(store),
                secrets: rig.secrets, relay: rig.relay, clock: rig.clock)
        }
        let expiry = rig.clock.now.addingTimeInterval(60)
        let request = PendingRefreshRequest(
            id: requestID(1), readerID: readerA, target: .allCodex, expiresAt: expiry)
        _ = await makeHandler().handle(pending: [request])
        rig.clock.advance(by: 40)
        _ = await makeHandler().handle(pending: [request])
        #expect(codex.refreshCount == 1)
        #expect(try await rig.openPublisherStore().load().handledRequests[requestID(1)] != nil)
    }
}
