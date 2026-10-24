import Foundation
import ResetRadarDomain

/// Plain values of Domain types and dates: no localized copy or formatting.
public struct AccountRingSummary: Sendable, Equatable {
    public let accountWindow: AccountWindow
    public let resolution: AccountWindowResolution
    public let presentation: PresentationState
    public let usedPercent: Double?
    public let resetsAt: Date?
    public let observedAt: Date?
    /// The earliest instant after `now` at which this cell's presentation differs.
    public let nextChange: Date?
}

public struct HomeReadModel: Sendable, Equatable {
    public let accounts: [AccountRow]
    /// The earliest ring change: when the UI must load again.
    public let nextChange: Date?
}

public struct AccountRow: Sendable, Equatable {
    public let account: AccountMetadata
    public let source: AccountSource
    /// Five-hour then weekly, including unavailable resolutions.
    public let standardWindows: [AccountRingSummary]
}

public struct WindowDetails: Sendable, Equatable {
    public let window: AllowanceWindow
    public let presentation: PresentationState
    public let nextChange: Date?
}

public struct AccountDetails: Sendable, Equatable {
    public let account: AccountMetadata
    public let source: AccountSource
    public let windows: [WindowDetails]
}

public struct UsageDetailsReadModel: Sendable, Equatable {
    public let accounts: [AccountDetails]
    /// `nil` when there is no snapshot to judge.
    public let macLive: Bool?
    public let transport: TransportStatus
}

public enum AccountDisplayOrder {
    public static func sorted(_ accounts: [AccountMetadata]) -> [AccountMetadata] {
        accounts.sorted { left, right in
            let comparison = left.effectiveDisplayLabel.localizedStandardCompare(
                right.effectiveDisplayLabel)
            return comparison == .orderedSame
                ? left.number < right.number : comparison == .orderedAscending
        }
    }
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
