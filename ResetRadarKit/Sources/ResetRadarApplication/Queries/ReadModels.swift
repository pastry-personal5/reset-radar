import Foundation
import ResetRadarDomain

/// Plain values of Domain types and dates: no strings, no formatting. The UI turns them into text.
public struct HomeCell: Sendable, Equatable {
    public let slot: HomeSlot
    public let resolution: HomeSlotResolution
    public let presentation: PresentationState
    public let usedPercent: Double?
    public let resetsAt: Date?
    public let observedAt: Date?
    /// The earliest instant after `now` at which this cell's presentation differs.
    public let nextChange: Date?
}

public struct HomeReadModel: Sendable, Equatable {
    /// Always four cells, in `HomeSlot.allCases` order.
    public let cells: [HomeCell]
    /// The earliest `nextChange` of any cell: when the UI must load again.
    public let nextChange: Date?
}

public struct WindowDetails: Sendable, Equatable {
    public let window: AllowanceWindow
    public let presentation: PresentationState
    public let nextChange: Date?
}

public struct ProductDetails: Sendable, Equatable {
    public let product: ProductID
    public let source: ProductSource?
    public let windows: [WindowDetails]
}

public struct UsageDetailsReadModel: Sendable, Equatable {
    public let products: [ProductDetails]
    /// `nil` when there is no snapshot to judge.
    public let macLive: Bool?
    public let transport: TransportStatus
}

public enum PairingState: Sendable, Equatable {
    case notPaired
    case awaitingActivation
    case paired
}

/// What the iPhone knows about erasing its Watch cache. It claims nothing about complication
/// frames or another paired Watch.
public enum WatchEraseState: Sendable, Equatable {
    case pending(revision: UInt64)
    case confirmed(revision: UInt64, confirmedAt: Date)
}

public struct PairingStatusReadModel: Sendable, Equatable {
    public let state: PairingState
    public let cleanupPending: Bool
    /// `nil` on iPad, which has no Watch stage, and when no erasure was ever involved.
    public let watchErase: WatchEraseState?
}

public struct DiagnosticsExport: Sendable, Equatable {
    public let events: [DiagnosticEvent]
    public let exportedAt: Date

    /// The export as wire JSON; events carry only enums, numbers, and dates.
    public func encoded() throws -> Data {
        try WireCoding.encoder().encode(events)
    }
}
