import Foundation
import ResetRadarDomain
import ResetRadarTestSupport
import Testing

@testable import ResetRadarApplication

@Suite struct RevokeReaderTests {
    let rig = PublishRig()

    init() {
        rig.store.seed {
            $0.devices = [PairedDevice(readerID: readerA, name: "Phone", pairedAt: at(0))]
        }
        rig.secrets.seed(.readerToken(readerA), SecretValue(bytes(32, 6)))
    }

    func make() -> RevokeReader {
        RevokeReader(publisher: rig.store, secrets: rig.secrets, relay: rig.relay)
    }

    @Test func revokesAtTheRelayThenRemovesTheLocalEntryAndToken() async {
        #expect(await make().revoke(readerA) == .revoked)
        #expect(rig.relay.calls == [.revokeReader(readerA)])
        #expect(rig.store.state.devices.isEmpty)
        #expect(!rig.secrets.names.contains(.readerToken(readerA)))
    }

    @Test func aRelayFailureKeepsTheLocalEntry() async {
        rig.relay.queueRevoke(.offline)
        #expect(await make().revoke(readerA) == .failed(.offline))
        #expect(rig.store.state.devices.count == 1)
        #expect(rig.secrets.names.contains(.readerToken(readerA)))
    }
}
