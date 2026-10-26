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

public enum WindowSelectionResolver {
    /// Resolves a saved exact selection without retargeting an unavailable additional window.
    public static func resolve(
        _ selection: WindowSelection, in snapshot: UsageSnapshot, now: Date
    ) -> (AccountWindowResolution, DiagnosticEvent?) {
        switch selection {
        case .standard(let accountWindow):
            return AccountWindowResolver.resolve(accountWindow, in: snapshot, now: now)
        case .additional(let windowID):
            guard let window = snapshot.windows.first(where: { $0.id == windowID }) else {
                return (.unavailable, nil)
            }
            return (.window(window), nil)
        }
    }
}
