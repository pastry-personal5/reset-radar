import Foundation

public enum FetchTrigger: Sendable, Equatable, CaseIterable {
    case foregroundActivation
    case foregroundTick
    case manual
    case backgroundTask
    case watchRequest
    case widgetReload
}

public enum SkipReason: Sendable, Equatable {
    case notPaired
    case cleanupPending
    case pairingPending
    case authorizationRequired
    case incompatible
    case backoff
    case tooSoon
    case widgetFresh
}

public enum FetchDecision: Sendable, Equatable {
    case fetch
    case skip(SkipReason)
    /// Another fetch owns a live lease.
    case inProgress
}

/// When an iPhone or iPad may read the relay. Pure: reads `ReaderState`, never mutates it.
public enum ReaderRefreshPolicy {
    public static let minimumInterval: TimeInterval = 15
    public static let tickInterval: TimeInterval = 60
    public static let widgetInterval: TimeInterval = 300
    public static let backgroundInterval: TimeInterval = 900
    public static let backgroundFloor: TimeInterval = 60
    public static let backgroundResetSlack: TimeInterval = 60

    public static func decide(
        trigger: FetchTrigger, state: ReaderState, now: Date
    ) -> FetchDecision {
        if state.forgetCleanupPending { return .skip(.cleanupPending) }
        if state.pairing == nil { return .skip(.notPaired) }
        if let lease = state.lease, lease.expiresAt > now { return .inProgress }
        if state.awaitingActivation { return .skip(.pairingPending) }
        if trigger == .manual { return .fetch }
        switch state.transportStatus {
        case .authorizationRequired: return .skip(.authorizationRequired)
        case .incompatible: return .skip(.incompatible)
        default: break
        }
        if let backoffUntil = state.backoffUntil, backoffUntil > now { return .skip(.backoff) }
        return intervalDecision(trigger: trigger, state: state, now: now)
    }

    private static func intervalDecision(
        trigger: FetchTrigger, state: ReaderState, now: Date
    ) -> FetchDecision {
        func elapsed(since date: Date?) -> TimeInterval {
            date.map { now.timeIntervalSince($0) } ?? .infinity
        }
        let sinceAttempt = elapsed(since: state.lastAttemptAt)
        if sinceAttempt <= minimumInterval { return .skip(.tooSoon) }
        switch trigger {
        case .foregroundTick where sinceAttempt < tickInterval:
            return .skip(.tooSoon)
        case .widgetReload where elapsed(since: state.lastSuccessAt) <= widgetInterval:
            return .skip(.widgetFresh)
        default:
            return .fetch
        }
    }

    /// The earliest begin date for the next background task:
    /// `max(now + 1 min, min(lastSuccess + 15 min, nextReset + 1 min))`, where an absent
    /// `lastSuccess` gives `now + 1 min` and an absent `nextReset` gives `lastSuccess + 15 min`.
    public static func nextBackgroundRequest(
        lastSuccess: Date?, nextReset: Date?, now: Date
    ) -> Date {
        let floor = now.addingTimeInterval(backgroundFloor)
        guard let lastSuccess else { return floor }
        var candidate = lastSuccess.addingTimeInterval(backgroundInterval)
        if let nextReset {
            candidate = min(candidate, nextReset.addingTimeInterval(backgroundResetSlack))
        }
        return max(floor, candidate)
    }
}
