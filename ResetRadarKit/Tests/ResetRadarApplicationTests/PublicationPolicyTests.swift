import Foundation
import Testing

@testable import ResetRadarApplication

@Suite struct PublicationPolicyTests {
    static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func state(sinceLast seconds: TimeInterval?, backoff: TimeInterval? = nil) -> PublicationState {
        PublicationState(
            lastPublishedAt: seconds.map { Self.now.addingTimeInterval(-$0) },
            backoffUntil: backoff.map { Self.now.addingTimeInterval($0) })
    }

    func decide(
        _ change: ChangeClass, _ trigger: PublishTrigger = .change, since: TimeInterval?,
        backoff: TimeInterval? = nil
    ) -> PublicationDecision {
        PublicationPolicy.decide(
            change: change, trigger: trigger, state: state(sinceLast: since, backoff: backoff),
            now: Self.now)
    }

    /// True when the decision waits until `seconds` from now, within floating-point error.
    func waits(_ decision: PublicationDecision, _ seconds: TimeInterval) -> Bool {
        guard case .wait(let until) = decision else { return false }
        return abs(until.timeIntervalSince(Self.now) - seconds) < 1e-6
    }

    @Test func transitionPublishesRegardlessOfAge() {
        #expect(decide(.transition, since: 0) == .publishNow)
        #expect(decide(.transition, since: 4_000) == .publishNow)
    }

    @Test func materialWaitsForTheCoalescingWindow() {
        #expect(waits(decide(.material, since: 29.999), 0.001))
        #expect(decide(.material, since: 30) == .publishNow)
        #expect(decide(.material, since: 31) == .publishNow)
    }

    @Test func observationOnlyWaitsForTheHeartbeat() {
        #expect(waits(decide(.observationOnly, since: 30), 270))
        #expect(waits(decide(.observationOnly, since: 299.999), 0.001))
        #expect(decide(.observationOnly, since: 300) == .publishNow)
        #expect(waits(decide(.none, since: 10), 290))
    }

    @Test func heartbeatTriggerPublishesAtFiveMinutes() {
        #expect(waits(decide(.none, .heartbeat, since: 299.999), 0.001))
        #expect(decide(.none, .heartbeat, since: 300) == .publishNow)
        #expect(decide(.material, .heartbeat, since: 30) == .publishNow)
    }

    @Test(arguments: [PublishTrigger.wake, .networkRestored]) func wakeAndNetworkPublishNow(
        trigger: PublishTrigger
    ) {
        #expect(decide(.none, trigger, since: 1) == .publishNow)
    }

    @Test func aFirstPublicationPublishes() {
        #expect(decide(.none, since: nil) == .publishNow)
        #expect(decide(.observationOnly, .heartbeat, since: nil) == .publishNow)
    }

    @Test(arguments: [PublishTrigger.change, .heartbeat, .wake, .networkRestored])
    func activeBackoffWaitsForEveryTriggerAndChange(trigger: PublishTrigger) {
        for change in [ChangeClass.none, .observationOnly, .material, .transition] {
            #expect(waits(decide(change, trigger, since: 9_999, backoff: 42), 42))
        }
    }

    @Test func anExpiredBackoffNoLongerBlocks() {
        #expect(decide(.transition, since: 0, backoff: 0) == .publishNow)
        #expect(decide(.transition, since: 0, backoff: -5) == .publishNow)
    }
}
