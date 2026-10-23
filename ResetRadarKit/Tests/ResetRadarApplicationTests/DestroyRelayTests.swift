import Foundation
import ResetRadarDomain
import ResetRadarTestSupport
import Testing

@testable import ResetRadarApplication

@Suite struct DestroyRelayTests {
    let rig = PublishRig()
    let publishing: PublishSnapshot

    init() {
        publishing = rig.makePublisher()
        rig.store.seed {
            $0.devices = [PairedDevice(readerID: readerA, name: "Phone", pairedAt: at(0))]
            $0.sequence = 4
        }
        rig.secrets.seed(.readerToken(readerA), SecretValue(bytes(32, 6)))
    }

    func make() -> DestroyRelay {
        DestroyRelay(
            publisher: rig.store, secrets: rig.secrets, relay: rig.relay, publishing: publishing)
    }

    @Test func destroyPendingIsPersistedAndPublicationPausedBeforeTheRemoteDelete() async {
        rig.relay.hold(.destroyRelay)
        let use = make()
        let task = Task { await use.run() }
        await rig.relay.waitForCalls(.destroyRelay)
        #expect(rig.store.state.lifecycle == .destroyPending)
        let during = await publishing.publish(
            snapshot(windows: []), change: .transition, trigger: .change)
        #expect(during == .paused)
        rig.relay.release(.destroyRelay)
        #expect(await task.value == .destroyed)
    }

    @Test func successDeletesSecretsThenLocalState() async {
        #expect(await make().run() == .destroyed)
        #expect(rig.secrets.names.isEmpty)
        #expect(rig.store.state == PublisherState())
        #expect(rig.secrets.invalidations == 1)
    }

    @Test func aRemoteFailureRetainsLocalStateAndStaysPaused() async {
        rig.relay.queueDestroy(.offline)
        #expect(await make().run() == .remoteFailed(.offline))
        let state = rig.store.state
        #expect(state.lifecycle == .destroyPending)
        #expect(state.endpoint == endpoint && state.devices.count == 1)
        #expect(rig.secrets.names.contains(.adminToken))
        let paused = await rig.makePublisher().publish(
            snapshot(windows: []), change: .transition, trigger: .change)
        #expect(paused == .paused)
        #expect(await make().run() == .destroyed)
    }

    @Test func repeatingAnInterruptedRunSucceeds() async {
        rig.store.seed { $0.lifecycle = .destroyPending }
        rig.secrets.setReadFailure(nil)
        for name in [SecretName.contentKey, .writeToken, .adminToken] {
            try? await rig.secrets.delete(name)
        }
        #expect(await make().run() == .destroyed)
        #expect(rig.relay.calls.isEmpty)
        #expect(rig.store.state == PublisherState())
    }

    @Test func lockedSecretsPauseTheDestroyWithoutDeletingAnything() async {
        rig.secrets.setReadFailure(.interactionRequired)
        #expect(await make().run() == .secretsUnavailable)
        #expect(rig.relay.calls.isEmpty)
        #expect(rig.store.state.lifecycle == .destroyPending)
    }

    @Test func theAccountScopeKeyIsNotARelaySecretAndSurvives() async {
        rig.secrets.seed(.accountScopeKey, SecretValue(bytes(32, 8)))
        #expect(await make().run() == .destroyed)
        #expect(rig.secrets.names == [.accountScopeKey])
    }
}
