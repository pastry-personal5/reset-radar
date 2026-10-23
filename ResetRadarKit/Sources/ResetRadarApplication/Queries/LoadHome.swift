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
        let snapshot = await visible.current()
        let cells = HomeSlot.allCases.map { Self.cell(for: $0, in: snapshot, now: now) }
        return HomeReadModel(cells: cells, nextChange: cells.compactMap(\.nextChange).min())
    }

    static func cell(for slot: HomeSlot, in snapshot: UsageSnapshot?, now: Date) -> HomeCell {
        guard let snapshot else { return empty(slot, .unavailable) }
        let (resolution, _) = HomeSlotResolver.resolve(slot, in: snapshot, now: now)
        guard case .window(let window) = resolution else {
            return empty(slot, resolution)
        }
        let presentation = PresentationPolicy.derive(
            window: window, source: snapshot.source(for: slot.product), now: now)
        return HomeCell(
            slot: slot, resolution: resolution, presentation: presentation.state,
            usedPercent: window.observation?.usedPercent, resetsAt: window.resetsAt,
            observedAt: window.observation?.observedAt, nextChange: presentation.nextChange)
    }

    private static func empty(_ slot: HomeSlot, _ resolution: HomeSlotResolution) -> HomeCell {
        HomeCell(
            slot: slot, resolution: resolution, presentation: .unavailable, usedPercent: nil,
            resetsAt: nil, observedAt: nil, nextChange: nil)
    }
}
