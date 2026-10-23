import Foundation
import ResetRadarDomain
import ResetRadarTestSupport
import Testing

@testable import ResetRadarApplication

@Suite struct RequestPhoneRefreshTests {
    let cache = FakeWatchCacheStore()
    let phone = FakePhoneLink()
    let reloader = FakeSurfaceReloader()

    func make() -> RequestPhoneRefresh {
        RequestPhoneRefresh(
            phone: phone,
            commit: CommitWatchPayload(cache: cache, phone: phone, reloader: reloader))
    }

    @Test func aReplyGoesThroughTheOrdinaryCommit() async {
        phone.setReply(watchPayload(3, percent: 33))
        await make().request()
        #expect(phone.requestCount == 1)
        #expect(cache.state.deliveryRevision == 3)
    }

    @Test func anUnreachablePhoneIsNotAnError() async {
        await make().request()
        #expect(phone.requestCount == 1)
        #expect(cache.state.snapshot == nil && cache.state.installationID == nil)
        #expect(reloader.complicationReloads == 0)
    }
}
