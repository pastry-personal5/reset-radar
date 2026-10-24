import Foundation

public enum AccountWindowResolution: Hashable, Sendable {
    case window(AllowanceWindow)
    case unavailable
    case ambiguous([WindowID])
}

public enum AccountWindowResolver {
    /// Resolves a standard ring only inside its configured account row.
    public static func resolve(
        _ accountWindow: AccountWindow, in snapshot: UsageSnapshot, now: Date
    ) -> (AccountWindowResolution, DiagnosticEvent?) {
        guard let account = snapshot.accounts.first(where: { $0.id == accountWindow.accountID })
        else { return (.unavailable, nil) }
        let matches = snapshot.windows.filter {
            $0.accountID == accountWindow.accountID && $0.product == account.product
                && $0.isDefaultLimit
                && $0.durationMinutes == accountWindow.window.durationMinutes
        }
        switch matches.count {
        case 0: return (.unavailable, nil)
        case 1: return (.window(matches[0]), nil)
        default:
            return (
                .ambiguous(matches.map(\.id)),
                .ambiguousAccountWindow(accountWindow, product: account.product, at: now)
            )
        }
    }
}
