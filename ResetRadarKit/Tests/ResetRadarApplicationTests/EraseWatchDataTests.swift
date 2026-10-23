import Foundation
import ResetRadarDomain
import ResetRadarTestSupport
import Testing

@testable import ResetRadarApplication

@Suite struct EraseWatchDataTests {
    let cache = FakeWatchCacheStore()
    let phone = FakePhoneLink()
    let reloader = FakeSurfaceReloader()

    func commit() -> CommitWatchPayload {
        CommitWatchPayload(cache: cache, phone: phone, reloader: reloader)
    }

    @Test func eraseClearsKeepsTheTombstoneAndHoldsLaterUsage() async {
        let use = commit()
        _ = await use.commit(watchPayload(4))
        await EraseWatchData(cache: cache, reloader: reloader).erase()
        let state = cache.state
        #expect(state.snapshot == nil && state.deliveryRevision == 4 && state.localEraseHold)
        #expect(state.installationID == installation)
        #expect(reloader.complicationReloads == 2)
        #expect(await use.commit(watchPayload(5)) == .rejectedByLocalEraseHold)
        #expect(cache.state.snapshot == nil && cache.state.deliveryRevision == 4)
    }

    @Test func aNewerClearIsStillCommittedAndAcknowledgedUnderTheHold() async {
        let use = commit()
        _ = await use.commit(watchPayload(4))
        await EraseWatchData(cache: cache, reloader: reloader).erase()
        #expect(await use.commit(watchPayload(5, cleared: true)) == .cleared)
        #expect(phone.receipts.map(\.deliveryRevision) == [5])
        #expect(cache.state.localEraseHold)
    }

    @Test func resettingPairingReleasesTheHoldWithoutLoweringTheFloor() async {
        let use = commit()
        _ = await use.commit(watchPayload(4))
        await EraseWatchData(cache: cache, reloader: reloader).erase()
        await use.resetPairing()
        #expect(!cache.state.localEraseHold && cache.state.deliveryRevision == 4)
        #expect(await use.commit(watchPayload(4, percent: 99)) == .rejectedConflict)
        #expect(await use.commit(watchPayload(3)) == .ignoredOlder)
        #expect(await use.commit(watchPayload(5)) == .committed)
    }
}
