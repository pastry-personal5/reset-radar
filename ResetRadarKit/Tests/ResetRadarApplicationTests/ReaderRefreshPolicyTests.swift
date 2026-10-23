import Foundation
import ResetRadarDomain
import Testing

@testable import ResetRadarApplication

@Suite struct ReaderRefreshPolicyTests {
    static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    static let installation = InstallationID(data: Data(repeating: 1, count: 16))!

    func pairing() -> ReaderPairing {
        ReaderPairing(
            endpoint: URL(string: "https://a.workers.dev")!,
            publisherID: PublisherID(data: Data(repeating: 2, count: 32))!,
            readerID: ReaderID(data: Data(repeating: 3, count: 16))!, minimumSequence: 0,
            keyVersion: 1, registrationExpiresAt: Self.now)
    }

    func state(
        attempt: TimeInterval? = nil, success: TimeInterval? = nil,
        status: TransportStatus = .current, backoff: TimeInterval? = nil,
        lease: TimeInterval? = nil, awaiting: Bool = false, paired: Bool = true
    ) -> ReaderState {
        var state = ReaderState(installationID: Self.installation)
        state.pairing = paired ? pairing() : nil
        state.lastAttemptAt = attempt.map { Self.now.addingTimeInterval(-$0) }
        state.lastSuccessAt = success.map { Self.now.addingTimeInterval(-$0) }
        state.transportStatus = status
        state.backoffUntil = backoff.map { Self.now.addingTimeInterval($0) }
        state.lease = lease.map {
            FetchClaim(id: UUID(), expiresAt: Self.now.addingTimeInterval($0))
        }
        state.awaitingActivation = awaiting
        return state
    }

    func decide(_ trigger: FetchTrigger, _ state: ReaderState) -> FetchDecision {
        ReaderRefreshPolicy.decide(trigger: trigger, state: state, now: Self.now)
    }

    @Test(arguments: [FetchTrigger.foregroundActivation, .watchRequest, .backgroundTask])
    func fifteenSecondMinimumIntervalHasAnEdge(trigger: FetchTrigger) {
        #expect(decide(trigger, state(attempt: 14.999)) == .skip(.tooSoon))
        #expect(decide(trigger, state(attempt: 15)) == .fetch)
        #expect(decide(trigger, state()) == .fetch)
    }

    @Test func theForegroundTickAlsoNeedsSixtySeconds() {
        #expect(decide(.foregroundTick, state(attempt: 14.999)) == .skip(.tooSoon))
        #expect(decide(.foregroundTick, state(attempt: 59.999)) == .skip(.tooSoon))
        #expect(decide(.foregroundTick, state(attempt: 60)) == .fetch)
    }

    @Test func widgetReloadNeedsFiveMinutesSinceTheLastSuccess() {
        #expect(decide(.widgetReload, state(attempt: 100, success: 299)) == .skip(.widgetFresh))
        #expect(decide(.widgetReload, state(attempt: 100, success: 300)) == .fetch)
        #expect(decide(.widgetReload, state(attempt: 100)) == .fetch)
        #expect(decide(.widgetReload, state(attempt: 14.999, success: 900)) == .skip(.tooSoon))
    }

    @Test func manualIgnoresTheIntervalAndBackoff() {
        #expect(decide(.manual, state(attempt: 0)) == .fetch)
        #expect(decide(.manual, state(attempt: 1, backoff: 600)) == .fetch)
        #expect(decide(.manual, state(attempt: 1, success: 1)) == .fetch)
    }

    @Test func aLiveLeaseIsInProgressAndExpiryIsFree() {
        for trigger in [FetchTrigger.manual, .foregroundActivation, .widgetReload] {
            #expect(decide(trigger, state(attempt: 100, success: 900, lease: 1)) == .inProgress)
            #expect(decide(trigger, state(attempt: 100, success: 900, lease: 0)) == .fetch)
            #expect(decide(trigger, state(attempt: 100, success: 900, lease: -1)) == .fetch)
        }
    }

    @Test func blockedStatesStopEveryAutomaticTrigger() {
        let automatic: [FetchTrigger] = [
            .foregroundActivation, .foregroundTick, .backgroundTask, .watchRequest, .widgetReload,
        ]
        for trigger in automatic {
            let old = state(attempt: 9_999, success: 9_999, status: .authorizationRequired)
            #expect(decide(trigger, old) == .skip(.authorizationRequired))
            let incompatible = state(attempt: 9_999, success: 9_999, status: .incompatible)
            #expect(decide(trigger, incompatible) == .skip(.incompatible))
            let backoff = state(attempt: 9_999, success: 9_999, backoff: 1)
            #expect(decide(trigger, backoff) == .skip(.backoff))
            #expect(decide(trigger, state(attempt: 9_999, success: 9_999, backoff: 0)) == .fetch)
        }
        #expect(decide(.manual, state(status: .authorizationRequired)) == .fetch)
        #expect(decide(.manual, state(status: .incompatible)) == .fetch)
    }

    @Test func awaitingActivationSuppressesEveryTrigger() {
        for trigger in FetchTrigger.allCases {
            #expect(decide(trigger, state(awaiting: true)) == .skip(.pairingPending))
        }
    }

    @Test func unpairedAndCleanupStatesNeverFetch() {
        for trigger in FetchTrigger.allCases {
            #expect(decide(trigger, state(paired: false)) == .skip(.notPaired))
            var cleanup = state()
            cleanup.forgetCleanupPending = true
            #expect(decide(trigger, cleanup) == .skip(.cleanupPending))
        }
    }

    @Test func nextBackgroundRequestIsFlooredAndTakesTheEarlierBound() {
        let now = Self.now
        func next(_ success: TimeInterval?, _ reset: TimeInterval?) -> TimeInterval {
            ReaderRefreshPolicy.nextBackgroundRequest(
                lastSuccess: success.map { now.addingTimeInterval($0) },
                nextReset: reset.map { now.addingTimeInterval($0) }, now: now
            ).timeIntervalSince(now)
        }
        #expect(next(-60, 100_000) == 840)  // lastSuccess + 15 min binds
        #expect(next(-60, 600) == 660)  // nextReset + 1 min binds
        #expect(next(-2_000, 100_000) == 60)  // floored at now + 1 min
        #expect(next(-60, -9_000) == 60)  // a reset in the past still floors
        #expect(next(nil, 100_000) == 60)  // no success yet
        #expect(next(nil, nil) == 60)
        #expect(next(-60, nil) == 840)  // no reset: lastSuccess + 15 min
        #expect(next(-899, nil) == 60)
        #expect(next(-840, nil) == 60)
    }
}
