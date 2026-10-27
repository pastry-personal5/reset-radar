import Foundation
import ResetRadarDomain
import ResetRadarTestSupport
import Testing

@testable import ResetRadarApplication

@Suite struct CommitWatchPayloadTests {
    let cache = FakeWatchCacheStore()
    let phone = FakePhoneLink()
    let reloader = FakeSurfaceReloader()

    func make() -> CommitWatchPayload {
        CommitWatchPayload(cache: cache, phone: phone, reloader: reloader)
    }

    @Test func aHigherRevisionReplacesTheCacheAndReloadsTheComplication() async {
        let use = make()
        #expect(await use.commit(watchPayload(1, percent: 10)) == .committed)
        #expect(await use.commit(watchPayload(2, percent: 20)) == .committed)
        #expect(cache.state.deliveryRevision == 2)
        #expect(cache.state.snapshot?.windows.first?.observation?.usedPercent == 20)
        #expect(reloader.complicationReloads == 2)
    }

    @Test func aClearErasesToATombstoneAndQueuesOneReceipt() async {
        let use = make()
        _ = await use.commit(watchPayload(1))
        #expect(await use.commit(watchPayload(2, cleared: true)) == .cleared)
        let state = cache.state
        #expect(state.snapshot == nil && state.cleared && state.deliveryRevision == 2)
        #expect(state.installationID == installation)
        #expect(
            phone.receipts == [WatchEraseReceipt(installationID: installation, deliveryRevision: 2)]
        )
        #expect(reloader.complicationReloads == 2)
    }

    @Test func anEqualRevisionIsIdempotentOnlyForIdenticalContent() async {
        let use = make()
        _ = await use.commit(watchPayload(3, percent: 10))
        #expect(await use.commit(watchPayload(3, percent: 10)) == .idempotent)
        #expect(await use.commit(watchPayload(3, percent: 11)) == .rejectedConflict)
        #expect(cache.state.snapshot?.windows.first?.observation?.usedPercent == 10)
    }

    @Test func aLowerRevisionIsIgnoredEvenAsAClearOrFromAnotherPublisher() async {
        let use = make()
        _ = await use.commit(watchPayload(5, percent: 50))
        #expect(await use.commit(watchPayload(4, percent: 40)) == .ignoredOlder)
        #expect(await use.commit(watchPayload(4, cleared: true)) == .ignoredOlder)
        #expect(cache.state.snapshot != nil && cache.state.deliveryRevision == 5)
        #expect(phone.receipts.isEmpty)
    }

    @Test func aRepeatedIdenticalClearRequeuesTheSameReceiptAndAStaleOneQueuesNone() async {
        let use = make()
        _ = await use.commit(watchPayload(2, cleared: true))
        #expect(await use.commit(watchPayload(2, cleared: true)) == .idempotent)
        #expect(phone.receipts.count == 2 && phone.receipts[0] == phone.receipts[1])
        #expect(await use.commit(watchPayload(1, cleared: true)) == .ignoredOlder)
        #expect(phone.receipts.count == 2)
    }

    @Test func aReceiptQueueFailureIsDurableAndRetriesAfterRelaunch() async {
        let use = make()
        phone.failReceipts(true)
        let clear = watchPayload(2, cleared: true)
        #expect(await use.commit(clear) == .clearedReceiptPending)
        #expect(
            cache.state.pendingEraseReceipt
                == WatchEraseReceipt(installationID: installation, deliveryRevision: 2))
        #expect(phone.receipts.isEmpty)

        phone.failReceipts(false)
        let relaunched = make()
        #expect(await relaunched.retryPendingReceipt())
        #expect(cache.state.pendingEraseReceipt == nil)
        #expect(phone.receipts.map(\.deliveryRevision) == [2])
    }

    @Test func aDifferentInstallationIsHeldAndCommitsOnlyThePreviewedPayload() async {
        let use = make()
        _ = await use.commit(watchPayload(7, percent: 70))
        let foreign = watchPayload(1, installationID: otherInstallation, percent: 5)
        #expect(await use.commit(foreign) == .heldForOwnerConfirmation)
        #expect(cache.state.snapshot?.windows.first?.observation?.usedPercent == 70)
        #expect(cache.state.pendingInstallation == foreign)
        let other = watchPayload(1, installationID: otherInstallation, percent: 6)
        #expect(await use.resetPairing(confirming: other) == .rejectedConflict)
        #expect(await use.resetPairing(confirming: foreign) == .committed)
        let state = cache.state
        #expect(state.installationID == otherInstallation && state.deliveryRevision == 1)
        #expect(state.pendingInstallation == nil)
    }

    @Test func heldInstallationPreviewCannotBeReplacedByOlderOrAnotherInstallation() async throws {
        let use = make()
        _ = await use.commit(watchPayload(7, percent: 70))
        let held = watchPayload(3, installationID: otherInstallation, percent: 30)
        #expect(await use.commit(held) == .heldForOwnerConfirmation)
        #expect(
            await use.commit(watchPayload(2, installationID: otherInstallation, percent: 20))
                == .ignoredOlder)
        let third = try #require(
            InstallationID(data: Data(repeating: 0x33, count: InstallationID.byteCount)))
        #expect(
            await use.commit(watchPayload(4, installationID: third, percent: 40))
                == .rejectedConflict)
        #expect(cache.state.pendingInstallation == held)
    }

    @Test func resetPairingReportsAStorageFailureAndKeepsTheEraseHold() async {
        let use = make()
        _ = await use.commit(watchPayload(4))
        _ = await EraseWatchData(cache: cache, reloader: reloader).erase()
        cache.failNextTransactions(1)
        #expect(!(await use.resetPairing()))
        #expect(cache.state.localEraseHold)
    }

    @Test func everyDeliveryOrderEndsAtTheHighestRevision() async {
        let payloads = [
            watchPayload(1, percent: 1), watchPayload(2, percent: 2), watchPayload(3, percent: 3),
        ]
        let orders = [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
        for order in orders {
            let fresh = FakeWatchCacheStore()
            let use = CommitWatchPayload(cache: fresh, phone: phone, reloader: reloader)
            for index in order { _ = await use.commit(payloads[index]) }
            #expect(fresh.state.deliveryRevision == 3, "order \(order)")
            #expect(fresh.state.snapshot?.windows.first?.observation?.usedPercent == 3)
        }
    }
}
