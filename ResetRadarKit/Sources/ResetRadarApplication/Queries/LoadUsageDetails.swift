import Foundation
import ResetRadarDomain

public struct LoadUsageDetails: Sendable {
    private let visible: VisibleSnapshot
    private let clock: any AppClock

    public init(visible: VisibleSnapshot, clock: any AppClock) {
        self.visible = visible
        self.clock = clock
    }

    public func load() async -> UsageDetailsReadModel {
        let now = clock.now
        let snapshot = await visible.current()
        let accounts: [AccountDetails] = AccountDisplayOrder.sorted(
            snapshot?.accounts ?? []
        ).compactMap { account in
            guard let source = snapshot?.source(for: account.id) else { return nil }
            let windows = (snapshot?.windows ?? []).filter { $0.accountID == account.id }
                .sorted(by: Self.windowOrder).map {
                    let presentation = PresentationPolicy.derive(
                        window: $0, source: source, now: now)
                    return WindowDetails(
                        window: $0, presentation: presentation.state,
                        nextChange: presentation.nextChange)
                }
            return AccountDetails(account: account, source: source, windows: windows)
        }
        return UsageDetailsReadModel(
            accounts: accounts,
            macLive: snapshot.map { MacLiveness.isPublishing(snapshot: $0, now: now) },
            transport: await visible.transportStatus(),
            lastSyncedAt: snapshot == nil ? nil : await visible.lastSyncedAt())
    }

    private static func windowOrder(_ left: AllowanceWindow, _ right: AllowanceWindow) -> Bool {
        func rank(_ window: AllowanceWindow) -> Int {
            guard window.isDefaultLimit else { return 2 }
            if window.durationMinutes == AccountWindow.StandardWindow.fiveHour.durationMinutes {
                return 0
            }
            if window.durationMinutes == AccountWindow.StandardWindow.weekly.durationMinutes {
                return 1
            }
            return 2
        }
        let leftRank = rank(left)
        let rightRank = rank(right)
        if leftRank != rightRank { return leftRank < rightRank }
        let label = (left.label ?? left.limitID).localizedStandardCompare(
            right.label ?? right.limitID)
        if label != .orderedSame { return label == .orderedAscending }
        if left.limitID != right.limitID { return left.limitID < right.limitID }
        return (left.durationMinutes ?? Int.max) < (right.durationMinutes ?? Int.max)
    }
}
