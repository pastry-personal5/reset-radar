import Foundation
import ResetRadarDomain

/// Cache-only lookup for a saved widget or App Intent selection. An absent additional ID stays
/// unavailable rather than resolving to a new provider window.
public struct LoadWindowSelection: Sendable {
    public enum Result: Sendable, Equatable {
        case window(account: AccountMetadata, source: AccountSource, details: WindowDetails)
        case unavailable(WindowSelection)
    }

    private let visible: VisibleSnapshot
    private let clock: any AppClock

    public init(visible: VisibleSnapshot, clock: any AppClock) {
        self.visible = visible
        self.clock = clock
    }

    public func load(_ selection: WindowSelection) async -> Result {
        guard let snapshot = await visible.current(),
            let account = snapshot.accounts.first(where: { $0.id == selection.accountID }),
            let source = snapshot.source(for: selection.accountID)
        else { return .unavailable(selection) }
        let (resolution, _) = WindowSelectionResolver.resolve(
            selection, in: snapshot, now: clock.now)
        guard case .window(let window) = resolution else { return .unavailable(selection) }
        let presentation = PresentationPolicy.derive(window: window, source: source, now: clock.now)
        return .window(
            account: account, source: source,
            details: WindowDetails(
                window: window, presentation: presentation.state,
                nextChange: presentation.nextChange))
    }
}
