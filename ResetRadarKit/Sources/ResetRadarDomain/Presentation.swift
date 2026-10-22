import Foundation

public enum StaleReason: Hashable, Sendable {
    case sourceNotReporting
    case retained
    case observationOld
    case observationInFuture
}

/// Derived per window and never serialized.
public enum PresentationState: Hashable, Sendable {
    case unavailable
    case resetAwaitingRefresh
    case stale(reason: StaleReason)
    case current
}

public struct Presentation: Hashable, Sendable {
    public let state: PresentationState
    /// The earliest instant after `now` at which `state` differs; nil when it never will.
    public let nextChange: Date?
}

public enum PresentationPolicy {
    /// Observations further ahead of `now` than this are stale.
    public static let clockSkewTolerance: TimeInterval = 300

    public static func derive(
        window: AllowanceWindow, source: ProductSource?, now: Date
    ) -> Presentation {
        let state = state(window: window, source: source, now: now)
        var candidates: [Date] = []
        if let resetsAt = window.resetsAt { candidates.append(resetsAt) }
        if let observedAt = window.observation?.observedAt {
            let expiry = observedAt.addingTimeInterval(
                CurrentDataWindow.seconds(for: window.product))
            // Stale begins strictly after the window, i.e. at the next representable instant.
            candidates.append(
                Date(timeIntervalSinceReferenceDate: expiry.timeIntervalSinceReferenceDate.nextUp))
            candidates.append(observedAt.addingTimeInterval(-clockSkewTolerance))
        }
        let next =
            candidates
            .filter { $0 > now && Self.state(window: window, source: source, now: $0) != state }
            .min()
        return Presentation(state: state, nextChange: next)
    }

    private static func state(
        window: AllowanceWindow, source: ProductSource?, now: Date
    ) -> PresentationState {
        guard let observation = window.observation else { return .unavailable }
        let resetPassed = window.resetsAt.map { $0 <= now } ?? false
        if window.reportState == .retained && (window.resetsAt == nil || resetPassed) {
            return .unavailable
        }
        if resetPassed { return .resetAwaitingRefresh }
        if source?.state != .reporting { return .stale(reason: .sourceNotReporting) }
        if window.reportState == .retained { return .stale(reason: .retained) }
        let age = now.timeIntervalSince(observation.observedAt)
        if age > CurrentDataWindow.seconds(for: window.product) {
            return .stale(reason: .observationOld)
        }
        if observation.observedAt.timeIntervalSince(now) > clockSkewTolerance {
            return .stale(reason: .observationInFuture)
        }
        return .current
    }
}
