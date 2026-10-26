import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarTestSupport
import Testing

@testable import ResetRadarStorage

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
