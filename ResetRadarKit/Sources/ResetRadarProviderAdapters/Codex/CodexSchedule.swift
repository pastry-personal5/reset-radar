import Foundation
import ResetRadarDomain

public enum CodexReadPermission: Equatable, Sendable {
    case perform
    case deferred(retryAt: Date, sourceState: SourceState)
    case unavailable(sourceState: SourceState)
}

public struct CodexSchedule: Equatable, Sendable {
    public static let pollInterval: TimeInterval = 5 * 60
    public static let notificationInterval: TimeInterval = 60
    public static let resetDelay: TimeInterval = 30
    public static let restartDelays: [TimeInterval] = [60, 120, 300, 900]

    public private(set) var sourceState: SourceState = .unavailable
    public private(set) var pollDeadline: Date?
    public private(set) var notificationDeadline: Date?
    public private(set) var resetDeadlines: Set<Date> = []
    public private(set) var retryDeadline: Date?
    public private(set) var lastNotificationRefetchAt: Date?
    public private(set) var started = false
    public private(set) var stopped = false
    private var transientFailureCount = 0
    private var blocked = false

    public init() {}

    public mutating func start(at now: Date) -> Bool {
        guard !stopped else { return false }
        guard !started else { return true }
        started = true
        sourceState = .unavailable
        pollDeadline = now
        return true
    }

    public mutating func stop() {
        stopped = true
        started = false
        pollDeadline = nil
        notificationDeadline = nil
        resetDeadlines.removeAll()
        retryDeadline = nil
    }

    public mutating func configurationChanged(at now: Date) {
        guard started, !stopped else { return }
        blocked = false
        transientFailureCount = 0
        retryDeadline = nil
        pollDeadline = now
    }

    public mutating func recordCompleteReport(at completedAt: Date, resetsAt: [Date]) {
        guard started, !stopped else { return }
        sourceState = .reporting
        blocked = false
        transientFailureCount = 0
        retryDeadline = nil
        pollDeadline = completedAt.addingTimeInterval(Self.pollInterval)
        resetDeadlines = Set(
            resetsAt.lazy
                .filter { $0 > completedAt }
                .map { $0.addingTimeInterval(Self.resetDelay) })
    }

    public mutating func recordSignedOut(at completedAt: Date) {
        guard started, !stopped else { return }
        sourceState = .signedOut
        blocked = false
        retryDeadline = nil
        pollDeadline = completedAt.addingTimeInterval(Self.pollInterval)
    }

    public mutating func recordTransientFailure(at failedAt: Date) -> Date? {
        guard started, !stopped else { return nil }
        sourceState = .sourceOffline
        blocked = false
        let index = min(transientFailureCount, Self.restartDelays.count - 1)
        transientFailureCount += 1
        let deadline = failedAt.addingTimeInterval(Self.restartDelays[index])
        retryDeadline = deadline
        pollDeadline = nil
        return deadline
    }

    public mutating func recordUnavailable() {
        recordBlocked(state: .unavailable)
    }

    public mutating func recordIncompatible() {
        recordBlocked(state: .incompatible)
    }

    public mutating func notificationReceived(
        at receivedAt: Date, activeRequestSentAt: Date?
    ) {
        guard started, !stopped, !blocked else { return }
        if let activeRequestSentAt, receivedAt < activeRequestSentAt { return }
        let earliest =
            lastNotificationRefetchAt?.addingTimeInterval(Self.notificationInterval)
            ?? receivedAt
        let deadline = max(receivedAt, earliest)
        notificationDeadline = notificationDeadline.map { min($0, deadline) } ?? deadline
    }

    public mutating func notificationRefetchStarted(at startedAt: Date) {
        guard started, !stopped else { return }
        lastNotificationRefetchAt = startedAt
        notificationDeadline = nil
    }

    public mutating func consumeAutomaticDeadline(_ deadline: Date) {
        if pollDeadline == deadline { pollDeadline = nil }
        if notificationDeadline == deadline { notificationDeadline = nil }
        resetDeadlines.remove(deadline)
        if retryDeadline == deadline { retryDeadline = nil }
    }

    public func readPermission(at now: Date) -> CodexReadPermission {
        guard started, !stopped else { return .unavailable(sourceState: .unavailable) }
        if blocked { return .unavailable(sourceState: sourceState) }
        if let retryDeadline, retryDeadline > now {
            return .deferred(retryAt: retryDeadline, sourceState: sourceState)
        }
        return .perform
    }

    public var nextAutomaticDeadline: Date? {
        guard started, !stopped, !blocked else { return nil }
        if let retryDeadline { return retryDeadline }
        return ([pollDeadline, notificationDeadline] + resetDeadlines.map(Optional.some))
            .compactMap { $0 }
            .min()
    }

    private mutating func recordBlocked(state: SourceState) {
        guard started, !stopped else { return }
        sourceState = state
        blocked = true
        retryDeadline = nil
        pollDeadline = nil
        notificationDeadline = nil
        resetDeadlines.removeAll()
    }
}
