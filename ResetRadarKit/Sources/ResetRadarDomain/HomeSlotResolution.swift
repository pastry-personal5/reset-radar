import Foundation

public enum HomeSlotResolution: Hashable, Sendable {
    case window(AllowanceWindow)
    case unavailable
    case ambiguous([WindowID])
}

public enum HomeSlotResolver {
    /// Matches product, `isDefaultLimit`, and the slot's exact duration only. More than one
    /// match is `ambiguous`, with a diagnostic; no match is `unavailable`.
    public static func resolve(
        _ slot: HomeSlot, in snapshot: UsageSnapshot, now: Date
    ) -> (HomeSlotResolution, DiagnosticEvent?) {
        let matches = snapshot.windows.filter {
            $0.product == slot.product && $0.isDefaultLimit
                && $0.durationMinutes == slot.durationMinutes
        }
        switch matches.count {
        case 0: return (.unavailable, nil)
        case 1: return (.window(matches[0]), nil)
        default: return (.ambiguous(matches.map(\.id)), .ambiguousHomeSlot(slot, at: now))
        }
    }
}
