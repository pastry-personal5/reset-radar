import Foundation
import ResetRadarDomain

/// Which process committed: the full pipeline runs only in the app.
public enum ProcessKind: Sendable, Equatable {
    case app
    case widget
}

/// What the after-commit pipeline and `ForwardToWatch` are told about a committed snapshot.
public struct CommitEvent: Sendable, Equatable {
    public let snapshot: UsageSnapshot
    public let process: ProcessKind

    public init(snapshot: UsageSnapshot, process: ProcessKind) {
        self.snapshot = snapshot
        self.process = process
    }
}

public struct SealedEnvelope: Sendable, Equatable {
    public let header: EnvelopeHeader
    public let encoded: Data

    public init(header: EnvelopeHeader, encoded: Data) {
        self.header = header
        self.encoded = encoded
    }
}

public enum EnvelopeCipherError: Error, Equatable, Sendable {
    case malformed
    case authenticationFailed
    case unsupportedVersion
    case invalidSnapshot
}

public enum StorageError: Error, Equatable, Sendable {
    case unavailable
    case corrupted
    case incompatible
}

/// Result of a read of a source: lets `HandleManualRefreshRequests` decide whether the read
/// satisfies a request observed at a given instant.
public struct ReadReceipt: Sendable, Equatable {
    public let startedAt: Date
    public let finishedAt: Date
    public let succeeded: Bool
    /// The normalized result of the read, which the caller feeds to `CollectUsage`; `nil` when
    /// the read failed before producing one.
    public let report: SourceSnapshot?

    public init(
        startedAt: Date, finishedAt: Date, succeeded: Bool, report: SourceSnapshot? = nil
    ) {
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.succeeded = succeeded
        self.report = report
    }
}

public struct PendingRefreshRequest: Sendable, Equatable {
    public let id: RequestID
    public let readerID: ReaderID
    public let expiresAt: Date

    public init(id: RequestID, readerID: ReaderID, expiresAt: Date) {
        self.id = id
        self.readerID = readerID
        self.expiresAt = expiresAt
    }
}

public struct RelayReader: Sendable, Equatable {
    public let id: ReaderID
    public let activated: Bool

    public init(id: ReaderID, activated: Bool) {
        self.id = id
        self.activated = activated
    }
}

/// A relay result that carries a value on success; any other result is a `RelayOutcome`.
public enum RelayResponse<Value: Sendable & Equatable>: Sendable, Equatable {
    case value(Value)
    case outcome(RelayOutcome)
}

public enum ConfigurationState: Sendable, Equatable {
    case notConfigured
    case configured
    /// An existing command is unsafe or cannot be proven safe; it is never replaced.
    case unsafe
}

public struct ConfigurationPreview: Sendable, Equatable {
    public enum Change: Sendable, Equatable {
        case install
        case restore
        case discover
    }

    public let product: ProductID
    public let change: Change

    public init(product: ProductID, change: Change) {
        self.product = product
        self.change = change
    }
}

public enum NotificationAuthorization: Sendable, Equatable {
    case notDetermined
    case denied
    case authorized
}

/// A reset reminder. The identifier derives from the slot only; copy names the product and
/// window and carries no formatted time or percentage.
public struct ResetRequest: Sendable, Equatable {
    public let slot: HomeSlot
    public let fireAt: Date

    public var product: ProductID { slot.product }
    public var identifier: String { "reset.\(slot.rawValue)" }

    public init(slot: HomeSlot, fireAt: Date) {
        self.slot = slot
        self.fireAt = fireAt
    }
}

public struct GateClaim: Sendable, Equatable {
    public let id: UUID
    public let expiresAt: Date

    public init(id: UUID, expiresAt: Date) {
        self.id = id
        self.expiresAt = expiresAt
    }
}

/// The content of a Reset Live Activity: only enums, identifiers, numbers, and dates.
public struct ActivityContent: Sendable, Equatable {
    public let windowID: WindowID
    public let usedPercent: Double
    public let resetsAt: Date
    public let observedAt: Date

    public init(windowID: WindowID, usedPercent: Double, resetsAt: Date, observedAt: Date) {
        self.windowID = windowID
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.observedAt = observedAt
    }
}

public struct RunningActivity: Sendable, Equatable {
    public let slot: HomeSlot
    public let windowID: WindowID

    public init(slot: HomeSlot, windowID: WindowID) {
        self.slot = slot
        self.windowID = windowID
    }
}
