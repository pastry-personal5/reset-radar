import Foundation

public struct ComplicationBudgetState: Sendable, Equatable {
    public var enabled: Bool
    /// Instants of past complication transfers; older than a day may be omitted.
    public var transfers: [Date]

    public init(enabled: Bool, transfers: [Date]) {
        self.enabled = enabled
        self.transfers = transfers
    }
}

/// Keeps complication transfers inside the system's 50 a day with margin.
public enum ComplicationBudgetPolicy {
    public static let minimumInterval: TimeInterval = 1_800
    public static let dailyLimit = 48
    /// The budget is a rolling 24 hours, independent of the time zone.
    public static let window: TimeInterval = 86_400

    public static func allows(
        state: ComplicationBudgetState, changedSince: Bool, now: Date
    ) -> Bool {
        guard state.enabled, changedSince else { return false }
        if let last = state.transfers.max(), now.timeIntervalSince(last) < minimumInterval {
            return false
        }
        let inWindow = state.transfers.filter { now.timeIntervalSince($0) < window }
        return inWindow.count < dailyLimit
    }
}
