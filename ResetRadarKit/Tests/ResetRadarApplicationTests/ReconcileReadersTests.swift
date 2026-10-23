import Foundation
import ResetRadarDomain
import ResetRadarTestSupport
import Testing

@testable import ResetRadarApplication

@Suite struct ReconcileReadersTests {
    let rig = PublishRig()
    let readerC = ReaderID(data: bytes(16, 0x0C))!
    let readerD = ReaderID(data: bytes(16, 0x0D))!
    let readerX = ReaderID(data: bytes(16, 0x0E))!

    func make() -> ReconcileReaders {
        ReconcileReaders(
            publisher: rig.store, secrets: rig.secrets, relay: rig.relay, clock: rig.clock)
    }

    @Test func mergesNamesRevokesExpiredPendingAndKeepsActivatedOnes() async {
        let past = rig.clock.now.addingTimeInterval(-10)
        rig.store.seed {
            $0.pendingRegistrations = [
                PendingRegistration(readerID: readerA, name: "Expired", expiresAt: past),
                PendingRegistration(readerID: readerB, name: "Late", expiresAt: past),
            ]
            $0.devices = [
                PairedDevice(readerID: readerC, name: "Kept", pairedAt: at(0)),
                PairedDevice(readerID: readerD, name: "Gone", pairedAt: at(0)),
            ]
        }
        rig.relay.queueListReaders(
            .value([
                RelayReader(id: readerB, activated: true),
                RelayReader(id: readerC, activated: true),
                RelayReader(id: readerX, activated: true),
            ]))
        let outcome = await make().run()
        guard case .reconciled(let roster) = outcome else {
            Issue.record("expected reconciled, got \(outcome)")
            return
        }
        #expect(rig.relay.calls(.revokeReader) == [.revokeReader(readerA)])
        let byID = Dictionary(uniqueKeysWithValues: roster.map { ($0.readerID, $0) })
        #expect(byID[readerA] == nil)
        #expect(byID[readerB]?.name == "Late" && byID[readerB]?.status == .activated)
        #expect(byID[readerC]?.name == "Kept")
        #expect(byID[readerX]?.name == nil)
        #expect(byID[readerD]?.status == .missingOnRelay)
        #expect(Set(rig.store.state.devices.map(\.readerID)) == [readerB, readerC, readerD])
    }

    @Test func aRelayFailureChangesNothing() async {
        rig.store.seed {
            $0.devices = [PairedDevice(readerID: readerC, name: "Kept", pairedAt: at(0))]
        }
        rig.relay.queueListReaders(.outcome(.offline))
        #expect(await make().run() == .failed(.offline))
        #expect(rig.store.state.devices.count == 1)
    }

    @Test func aNonActiveRelayIsNotReconciled() async {
        let inactive = PublishRig(lifecycle: .destroyPending)
        let use = ReconcileReaders(
            publisher: inactive.store, secrets: inactive.secrets, relay: inactive.relay,
            clock: inactive.clock)
        #expect(await use.run() == .notActive)
    }
}
