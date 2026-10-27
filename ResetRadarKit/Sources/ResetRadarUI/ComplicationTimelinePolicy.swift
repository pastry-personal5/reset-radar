import Foundation
import ResetRadarApplication
import ResetRadarDomain

public struct ComplicationSelection: Sendable, Equatable {
    public let accountID: AccountID
    public let window: AccountWindow.StandardWindow

    public init(accountID: AccountID, window: AccountWindow.StandardWindow) {
        self.accountID = accountID
        self.window = window
    }
}

public enum ComplicationTimelinePolicy {
    public static let maximumReloadInterval: TimeInterval = 15 * 60

    /// Resolves only the exact saved identity. A removed account/window remains unavailable and is
    /// never silently retargeted to the first current account.
    public static func ring(
        selection: ComplicationSelection, in home: HomeReadModel
    ) -> AccountRingSummary? {
        home.accounts.first(where: { $0.account.id == selection.accountID })?
            .standardWindows.first(where: { $0.accountWindow.window == selection.window })
    }

    public static func reloadDate(now: Date, nextChange: Date?) -> Date {
        min(nextChange ?? .distantFuture, now.addingTimeInterval(maximumReloadInterval))
    }
}
