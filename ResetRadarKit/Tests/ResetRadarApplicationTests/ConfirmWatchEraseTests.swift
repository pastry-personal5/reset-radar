import Foundation
import ResetRadarDomain
import ResetRadarTestSupport
import Testing

@testable import ResetRadarApplication

@Suite struct ConfirmWatchEraseTests {
    let rig = WatchForwardRig()
    let clear = watchPayload(5, cleared: true)

    init() {
        rig.store.seed { state in
            state.watchErasePending = WatchErasure(clear: clear)
            state.watchDeliveryRevision = 5
            state.hasSentToWatch = true
            state.snapshot = snapshot(windows: [window()])
        }
    }

    func make() -> ConfirmWatchErase {
        ConfirmWatchErase(reader: rig.store, clock: rig.clock, forward: rig.makeForward())
    }

    @Test func aMatchingReceiptClearsThePendingMarkerAndRecordsConfirmation() async {
        let outcome = await make().confirm(
            WatchEraseReceipt(installationID: installation, deliveryRevision: 5))
        #expect(outcome == .confirmed)
        let state = rig.store.state
        #expect(state.watchErasePending == nil)
        #expect(
            state.confirmedWatchErasure == ConfirmedWatchErasure(revision: 5, confirmedAt: epoch))
    }

    @Test func staleDuplicateAndUnrelatedReceiptsAreIgnored() async {
        let use = make()
        let wrongInstallation = WatchEraseReceipt(
            installationID: otherInstallation, deliveryRevision: 5)
        let older = WatchEraseReceipt(installationID: installation, deliveryRevision: 4)
        let newer = WatchEraseReceipt(installationID: installation, deliveryRevision: 6)
        for receipt in [wrongInstallation, older, newer] {
            #expect(await use.confirm(receipt) == .ignored)
        }
        #expect(rig.store.state.watchErasePending != nil)
        let good = WatchEraseReceipt(installationID: installation, deliveryRevision: 5)
        #expect(await use.confirm(good) == .confirmed)
        #expect(await use.confirm(good) == .ignored)
        #expect(rig.store.state.confirmedWatchErasure?.revision == 5)
    }

    @Test func confirmationThenPermitsNewerUsageAtAHigherRevision() async {
        #expect(rig.link.contexts.isEmpty)
        _ = await make().confirm(
            WatchEraseReceipt(installationID: installation, deliveryRevision: 5))
        let sent = rig.link.contexts
        #expect(sent.count == 1)
        #expect(sent.first?.cleared == false && sent.first?.deliveryRevision == 6)
    }
}
