import Foundation
import ResetRadarDomain

/// The pairing a reader holds: which Mac it follows and the lowest sequence it accepts.
public struct ReaderPairing: Codable, Sendable, Equatable {
    public var endpoint: URL
    public var publisherID: PublisherID
    public var readerID: ReaderID
    public var minimumSequence: UInt64
    public var keyVersion: Int
    /// Relay-assigned registration deadline, kept for display and recovery only.
    public var registrationExpiresAt: Date

    public init(
        endpoint: URL, publisherID: PublisherID, readerID: ReaderID, minimumSequence: UInt64,
        keyVersion: Int, registrationExpiresAt: Date
    ) {
        self.endpoint = endpoint
        self.publisherID = publisherID
        self.readerID = readerID
        self.minimumSequence = minimumSequence
        self.keyVersion = keyVersion
        self.registrationExpiresAt = registrationExpiresAt
    }
}

/// An in-flight fetch lease. A result applies only while its claim ID still owns the lease.
public struct FetchClaim: Codable, Sendable, Equatable {
    public let id: UUID
    public let expiresAt: Date

    public init(id: UUID, expiresAt: Date) {
        self.id = id
        self.expiresAt = expiresAt
    }
}

public struct PendingManualRequest: Codable, Sendable, Equatable {
    public let requestID: RequestID
    public let target: ManualRefreshTarget
    public let deadline: Date

    public init(requestID: RequestID, target: ManualRefreshTarget, deadline: Date) {
        self.requestID = requestID
        self.target = target
        self.deadline = deadline
    }
}

/// A Watch payload waiting for its erase receipt.
public struct WatchErasure: Codable, Sendable, Equatable {
    public let clear: WatchPayload
    public var revision: UInt64 { clear.deliveryRevision }

    public init(clear: WatchPayload) {
        self.clear = clear
    }
}

public struct ConfirmedWatchErasure: Codable, Sendable, Equatable {
    public let revision: UInt64
    public let confirmedAt: Date

    public init(revision: UInt64, confirmedAt: Date) {
        self.revision = revision
        self.confirmedAt = confirmedAt
    }
}

/// What the last complication transfer carried, to detect a change since.
public struct ComplicationValues: Codable, Sendable, Equatable {
    public struct Cell: Codable, Sendable, Equatable {
        public let accountWindow: AccountWindow
        public let usedPercent: Double?
        public let resetsAt: Date?
        public let sourceState: SourceState?

        public init(
            accountWindow: AccountWindow, usedPercent: Double?, resetsAt: Date?,
            sourceState: SourceState?
        ) {
            self.accountWindow = accountWindow
            self.usedPercent = usedPercent
            self.resetsAt = resetsAt
            self.sourceState = sourceState
        }
    }

    public var cells: [Cell]

    public init(cells: [Cell]) {
        self.cells = cells
    }
}

/// Everything an iPhone or iPad persists about its pairing, ingestion, and Watch hand-off, held
/// as one value so the store replaces snapshot and state atomically (the `ReaderBundle`).
public struct ReaderState: Codable, Sendable, Equatable {
    public var installationID: InstallationID
    public var snapshot: UsageSnapshot?
    public var pairing: ReaderPairing?
    public var committedSequence: UInt64?
    public var etag: String?
    public var lastAttemptAt: Date?
    public var lastSuccessAt: Date?
    public var lastContactAt: Date?
    public var lastCommitAt: Date?
    public var transportStatus: TransportStatus = .notPaired
    public var failureCount = 0
    public var backoffUntil: Date?
    public var needsAppReconcile = false
    public var lease: FetchClaim?
    /// Set before Keychain writes; cleared by a successful pairing commit or by recovery.
    public var stagingReaderID: ReaderID?
    public var awaitingActivation = false
    public var pendingManualRequest: PendingManualRequest?
    public var forgetCleanupPending = false
    public var watchDeliveryRevision: UInt64 = 0
    public var hasSentToWatch = false
    public var lastWatchPayload: WatchPayload?
    public var watchErasePending: WatchErasure?
    public var confirmedWatchErasure: ConfirmedWatchErasure?
    public var complicationTransfers: [Date] = []
    public var lastComplicationValues: ComplicationValues?

    public init(installationID: InstallationID) {
        self.installationID = installationID
    }
}

/// The Watch cache and its ordering state (the `WatchCacheBundle`).
public struct WatchCacheState: Codable, Sendable, Equatable {
    public var snapshot: UsageSnapshot?
    public var relaySequence: UInt64?
    public var transportStatus: TransportStatus = .notPaired
    public var lastRelayContactAt: Date?
    public var lastCommitAt: Date?
    public var installationID: InstallationID?
    public var deliveryRevision: UInt64 = 0
    /// True when the last committed payload was a clear: a tombstone with no usage.
    public var cleared = false
    public var localEraseHold = false
    /// A clear was durably committed but its acknowledgement has not yet been accepted by the
    /// WatchConnectivity queue. It survives relaunch so the Watch never claims remote erasure.
    public var pendingEraseReceipt: WatchEraseReceipt?
    /// A payload from a different installation, held until the owner confirms.
    public var pendingInstallation: WatchPayload?

    public init() {}
}
