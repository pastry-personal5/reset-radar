import Foundation
import ResetRadarDomain

public struct LoadHome: Sendable {
    private let visible: VisibleSnapshot
    private let clock: any AppClock

    public init(visible: VisibleSnapshot, clock: any AppClock) {
        self.visible = visible
        self.clock = clock
    }

    public func load() async -> HomeReadModel {
        let now = clock.now
        guard let snapshot = await visible.current() else {
            return HomeReadModel(accounts: [], nextChange: nil)
        }
        let ordered = AccountDisplayOrder.sorted(snapshot.accounts)
        let rows: [AccountRow] = ordered.compactMap { account in
            guard let source = snapshot.source(for: account.id) else { return nil }
            return AccountRow(
                account: account, source: source,
                standardWindows: AccountWindow.StandardWindow.allCases.map {
                    Self.ring(
                        for: AccountWindow(accountID: account.id, window: $0),
                        in: snapshot, now: now)
                })
        }
        return HomeReadModel(
            accounts: rows,
            nextChange: rows.flatMap(\.standardWindows).compactMap(\.nextChange).min())
    }

    static func ring(
        for accountWindow: AccountWindow, in snapshot: UsageSnapshot, now: Date
    ) -> AccountRingSummary {
        let (resolution, _) = AccountWindowResolver.resolve(accountWindow, in: snapshot, now: now)
        guard case .window(let window) = resolution else {
            return empty(accountWindow, resolution)
        }
        let presentation = PresentationPolicy.derive(
            window: window, source: snapshot.source(for: accountWindow.accountID), now: now)
        return AccountRingSummary(
            accountWindow: accountWindow, resolution: resolution,
            presentation: presentation.state,
            usedPercent: window.observation?.usedPercent, resetsAt: window.resetsAt,
            observedAt: window.observation?.observedAt, nextChange: presentation.nextChange)
    }

    private static func empty(
        _ accountWindow: AccountWindow, _ resolution: AccountWindowResolution
    ) -> AccountRingSummary {
        AccountRingSummary(
            accountWindow: accountWindow, resolution: resolution,
            presentation: .unavailable, usedPercent: nil, resetsAt: nil,
            observedAt: nil, nextChange: nil)
    }
}
