import Foundation
import ResetRadarDomain
import ResetRadarTestSupport
import Testing

@testable import ResetRadarApplication

@Suite struct SetUpRelayTests {
    let rig = PublishRig(lifecycle: .notConfigured, configured: false, seedSecrets: false)
    let local = FakeSnapshotStore()

    func make(_ publishing: PublishSnapshot) -> SetUpRelay {
        SetUpRelay(
            publisher: rig.store, secrets: rig.secrets, random: rig.random, relay: rig.relay,
            snapshots: local, publishing: publishing, clock: rig.clock, heartbeatSeconds: 300)
    }

    @Test func prepareIsPersistedBeforeAnyRelayCallAndGivesDigestsNotSecrets() async throws {
        let digests = try await make(rig.makePublisher()).prepare(endpoint: endpoint)
        let state = rig.store.state
        #expect(state.lifecycle == .setupPending)
        #expect(state.endpoint == endpoint)
        #expect(state.publisherID != nil)
        #expect(rig.secrets.names == [.contentKey, .writeToken, .adminToken])
        #expect(rig.relay.calls.isEmpty)
        let write = try await rig.secrets.read(.writeToken)
        #expect(digests.writeToken == rig.random.digest(of: write))
        #expect(digests.writeToken != write.reveal())
        let admin = try await rig.secrets.read(.adminToken)
        #expect(digests.adminToken == rig.random.digest(of: admin))
    }

    @Test func publicationIsPausedUntilBindingSucceeds() async throws {
        let publishing = rig.makePublisher()
        let setup = make(publishing)
        _ = try await setup.prepare(endpoint: endpoint)
        let paused = await publishing.publish(
            snapshot(windows: []), change: .transition, trigger: .change)
        #expect(paused == .paused)
        #expect(await setup.activate() == .active)
        #expect(rig.store.state.lifecycle == .active)
        let published = await publishing.publish(
            snapshot(windows: []), change: .transition, trigger: .change)
        #expect(published == .published(sequence: 2))
    }

    @Test func activationWipesThenBinds() async throws {
        let setup = make(rig.makePublisher())
        _ = try await setup.prepare(endpoint: endpoint)
        #expect(await setup.activate() == .active)
        #expect(rig.relay.calls.count == 2)
        #expect(rig.relay.calls.first == .destroyRelay)
        #expect(rig.relay.calls(.putSnapshot).count == 1)
    }

    @Test func aFailedBindLeavesSetupPending() async throws {
        let setup = make(rig.makePublisher())
        _ = try await setup.prepare(endpoint: endpoint)
        rig.relay.queuePut(.offline)
        let outcome = await setup.activate()
        guard case .bindFailed(.backoff) = outcome else {
            Issue.record("expected a failed bind, got \(outcome)")
            return
        }
        #expect(rig.store.state.lifecycle == .setupPending)
    }

    @Test func aFailedWipeNeverBinds() async throws {
        let setup = make(rig.makePublisher())
        _ = try await setup.prepare(endpoint: endpoint)
        rig.relay.queueDestroy(.unauthorized)
        #expect(await setup.activate() == .wipeFailed(.unauthorized))
        #expect(rig.relay.calls(.putSnapshot).isEmpty)
        #expect(rig.store.state.lifecycle == .setupPending)
    }

    @Test func aRelaunchMidSetupResumesWithoutRegeneratingSecrets() async throws {
        _ = try await make(rig.makePublisher()).prepare(endpoint: endpoint)
        let content = try await rig.secrets.read(.contentKey)
        let publisherID = rig.store.state.publisherID
        let relaunched = make(rig.makePublisher())
        _ = try await relaunched.prepare(endpoint: endpoint)
        #expect(try await rig.secrets.read(.contentKey) == content)
        #expect(rig.store.state.publisherID == publisherID)
        #expect(rig.relay.calls.isEmpty)
    }

    @Test func activatingBeforePreparingIsRejected() async {
        #expect(await make(rig.makePublisher()).activate() == .notPrepared)
        #expect(rig.relay.calls.isEmpty)
    }

    @Test func settingUpAgainDropsOldReadersAndTheirTokens() async throws {
        rig.store.seed {
            $0.lifecycle = .active
            $0.endpoint = endpoint
            $0.publisherID = publisher
            $0.sequence = 9
            $0.devices = [PairedDevice(readerID: readerA, name: "Old", pairedAt: at(0))]
        }
        rig.secrets.seed(.readerToken(readerA), SecretValue(bytes(32, 5)))
        _ = try await make(rig.makePublisher()).prepare(endpoint: endpoint)
        #expect(rig.store.state.devices.isEmpty)
        #expect(rig.store.state.sequence == 0)
        #expect(!rig.secrets.names.contains(.readerToken(readerA)))
    }
}
