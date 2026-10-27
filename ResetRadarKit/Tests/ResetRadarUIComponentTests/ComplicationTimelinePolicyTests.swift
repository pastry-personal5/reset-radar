import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarUI
import Testing

@Suite struct ComplicationTimelinePolicyTests {
    @Test func removedSelectionStaysUnavailableRatherThanRetargeting() async {
        let home = await loadHome(standardSnapshot())
        #expect(
            ComplicationTimelinePolicy.ring(
                selection: ComplicationSelection(accountID: codexB, window: .fiveHour),
                in: home) == nil)
    }

    @Test func reloadUsesEarlierPresentationChangeOrFifteenMinutes() {
        let now = Date(timeIntervalSince1970: 1_000)
        #expect(
            ComplicationTimelinePolicy.reloadDate(
                now: now, nextChange: now.addingTimeInterval(60))
                == now.addingTimeInterval(60))
        #expect(
            ComplicationTimelinePolicy.reloadDate(
                now: now, nextChange: now.addingTimeInterval(3_600))
                == now.addingTimeInterval(900))
    }
}
