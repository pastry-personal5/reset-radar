import Foundation
import Testing

@testable import ResetRadarDomain

@Suite struct PresentationTests {
    typealias Win = AllowanceWindow
    typealias Derived = PresentationState

    func state(_ item: Win, _ src: AccountSource? = source(), now: TimeInterval = 0) -> Derived {
        PresentationPolicy.derive(window: item, source: src, now: at(now)).state
    }

    @Test func noObservationIsUnavailable() {
        #expect(state(window(percent: nil)) == .unavailable)
    }

    @Test func retainedWithoutResetIsUnavailable() {
        #expect(state(window(state: .retained, resetsAt: nil)) == .unavailable)
    }

    @Test func retainedPastResetBeatsAwaitingRefresh() {
        let target = window(state: .retained, resetsAt: at(-1))
        #expect(state(target) == .unavailable)
        #expect(state(window(state: .retained, resetsAt: at(0))) == .unavailable)
    }

    @Test func resetBoundary() {
        #expect(state(window(resetsAt: at(0))) == .resetAwaitingRefresh)
        #expect(state(window(resetsAt: at(-1))) == .resetAwaitingRefresh)
        #expect(state(window(resetsAt: at(1))) == .current)
    }

    @Test func sourceNotReportingIsStale() {
        for kind in [SourceState.unavailable, .signedOut, .sourceOffline, .incompatible] {
            #expect(state(window(), source(state: kind)) == .stale(reason: .sourceNotReporting))
        }
        #expect(state(window(), nil) == .stale(reason: .sourceNotReporting))
    }

    @Test func retainedBeforeResetIsStale() {
        #expect(state(window(state: .retained, resetsAt: at(60))) == .stale(reason: .retained))
    }

    @Test(arguments: [(ProductID.codex, 900.0), (.claudeCode, 3_600.0)])
    func observationAgeBoundary(product: ProductID, limit: Double) {
        let target = window(
            product: product, minutes: 300, resetsAt: at(100_000), observedAt: at(0))
        #expect(state(target, source(product), now: limit) == .current)
        #expect(state(target, source(product), now: limit + 1) == .stale(reason: .observationOld))
    }

    @Test func clockSkewBoundary() {
        let current = window(resetsAt: at(10_000), observedAt: at(300))
        #expect(state(current) == .current)
        let future = window(resetsAt: at(10_000), observedAt: at(300.001))
        #expect(state(future) == .stale(reason: .observationInFuture))
        #expect(state(window(resetsAt: at(10_000), observedAt: at(-300))) == .current)
    }

    @Test func nextChangeIsEarliestAndStateDiffers() {
        let target = window(resetsAt: at(2_000), observedAt: at(0))
        let first = PresentationPolicy.derive(window: target, source: source(), now: at(0))
        #expect(first.state == .current)
        let expiry = at(900).timeIntervalSinceReferenceDate.nextUp
        #expect(first.nextChange == Date(timeIntervalSinceReferenceDate: expiry))
        let second = PresentationPolicy.derive(
            window: target, source: source(), now: first.nextChange!)
        #expect(second.state == .stale(reason: .observationOld))
        #expect(second.nextChange == at(2_000))
        let third = PresentationPolicy.derive(
            window: target, source: source(), now: second.nextChange!)
        #expect(third.state == .resetAwaitingRefresh)
        #expect(third.nextChange == nil)
    }

    @Test func nextChangeForFutureObservation() {
        let target = window(resetsAt: at(100_000), observedAt: at(1_000))
        let first = PresentationPolicy.derive(window: target, source: source(), now: at(0))
        #expect(first.state == .stale(reason: .observationInFuture))
        #expect(first.nextChange == at(700))
        #expect(
            PresentationPolicy.derive(window: target, source: source(), now: at(700)).state
                == .current)
    }

    @Test func nextChangeSkipsInstantsThatDoNotChangeState() {
        let target = window(state: .retained, resetsAt: at(5_000), observedAt: at(0))
        let derived = PresentationPolicy.derive(window: target, source: source(), now: at(0))
        #expect(derived.state == .stale(reason: .retained))
        #expect(derived.nextChange == at(5_000))
    }

    @Test func noChangeAheadIsNil() {
        let derived = PresentationPolicy.derive(
            window: window(percent: nil), source: source(), now: at(0))
        #expect(derived.nextChange == nil)
    }

    @Test func sleepingPastNextChangeStillDerivesCorrectly() {
        let target = window(resetsAt: at(2_000), observedAt: at(0))
        #expect(state(target, now: 10_000) == .resetAwaitingRefresh)
    }

    @Test(arguments: ["UTC", "Asia/Tokyo", "America/Los_Angeles"])
    func timeZoneIndependence(identifier: String) {
        let saved = NSTimeZone.default
        defer { NSTimeZone.default = saved }
        NSTimeZone.default = TimeZone(identifier: identifier)!
        let target = window(resetsAt: at(2_000), observedAt: at(0))
        #expect(state(target, now: 100) == .current)
        #expect(state(target, now: 1_000) == .stale(reason: .observationOld))
        #expect(state(target, now: 2_000) == .resetAwaitingRefresh)
    }
}

@Suite struct MacLivenessTests {
    @Test func threeHeartbeatBoundary() {
        let live = snapshot(windows: [], heartbeat: 300, generatedAt: at(0))
        #expect(MacLiveness.isPublishing(snapshot: live, now: at(900)))
        #expect(!MacLiveness.isPublishing(snapshot: live, now: at(900.001)))
    }

    @Test func freshHeartbeatDoesNotRefreshOldObservation() {
        let target = window(resetsAt: at(100_000), observedAt: at(0))
        let live = snapshot(windows: [target], generatedAt: at(5_000))
        #expect(MacLiveness.isPublishing(snapshot: live, now: at(5_100)))
        #expect(
            PresentationPolicy.derive(
                window: live.windows[0], source: live.source(for: codexAccountID), now: at(5_100)
            ).state
                == .stale(reason: .observationOld))
    }
}
