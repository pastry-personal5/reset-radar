import Foundation
import ResetRadarApplication
import ResetRadarDomain

/// One Window Details section: the two standard windows always come first, even without a
/// reading, followed by every other valid provider-reported window.
public struct WindowSection: Identifiable, Equatable, Sendable {
    public enum Identity: Hashable, Sendable {
        case standard(AccountWindow.StandardWindow)
        case additional(WindowID)
    }

    public let id: Identity
    public let title: String
    public let details: WindowDetails?
    public let display: AllowanceDisplay
    /// More than one default window claims this standard duration, so none is shown as it.
    public let ambiguous: Bool

    public static func ordered(_ account: AccountDetails) -> [Self] {
        var claimed: Set<WindowID> = []
        let standards = AccountWindow.StandardWindow.allCases.map { standard -> Self in
            let matches = account.windows.filter {
                $0.window.isDefaultLimit && $0.window.durationMinutes == standard.durationMinutes
            }
            let title = ReaderVocabulary.windowName(standard)
            guard matches.count == 1, let match = matches.first else {
                return Self(
                    id: .standard(standard), title: title, details: nil,
                    display: AllowanceDisplay(state: .unavailable, window: nil),
                    ambiguous: matches.count > 1)
            }
            claimed.insert(match.window.id)
            return Self(
                id: .standard(standard), title: title, details: match,
                display: AllowanceDisplay(details: match), ambiguous: false)
        }
        let additional = account.windows.filter { !claimed.contains($0.window.id) }.map {
            Self(
                id: .additional($0.window.id), title: ReaderVocabulary.windowLabel($0.window),
                details: $0, display: AllowanceDisplay(details: $0), ambiguous: false)
        }
        return standards + additional
    }
}
