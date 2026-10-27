import Foundation

public enum PublishTrigger: Sendable, Equatable, CaseIterable {
    case change
    case heartbeat
    case wake
    case networkRestored
}

public struct PublicationState: Sendable, Equatable {
    public var lastPublishedAt: Date?
    public var backoffUntil: Date?

    public init(lastPublishedAt: Date? = nil, backoffUntil: Date? = nil) {
        self.lastPublishedAt = lastPublishedAt
        self.backoffUntil = backoffUntil
    }
}

public enum PublicationDecision: Sendable, Equatable {
    case publishNow
    case wait(until: Date)
}

/// When the Mac publishes. Pure: the caller supplies `now`.
public enum PublicationPolicy {
    public static let coalescing: TimeInterval = 30
    public static let heartbeat: TimeInterval = 300

    public static func decide(
        change: ChangeClass, trigger: PublishTrigger, state: PublicationState, now: Date
    ) -> PublicationDecision {
        if let backoffUntil = state.backoffUntil, backoffUntil > now {
            return .wait(until: backoffUntil)
        }
        guard let last = state.lastPublishedAt else { return .publishNow }
        let immediate =
            trigger == .wake || trigger == .networkRestored || change == .transition
            || change == .metadataOnly
        if immediate {
            return .publishNow
        }
        var due = last.addingTimeInterval(change == .material ? coalescing : heartbeat)
        if trigger == .heartbeat { due = min(due, last.addingTimeInterval(heartbeat)) }
        return now >= due ? .publishNow : .wait(until: due)
    }
}
