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
    public let publisherID: PublisherID
    public let relaySequence: UInt64

    public init(
        snapshot: UsageSnapshot, process: ProcessKind, relaySequence: UInt64 = 0,
        publisherID: PublisherID? = nil
    ) {
        self.snapshot = snapshot
        self.process = process
        self.publisherID = publisherID ?? snapshot.publisherID
        self.relaySequence = relaySequence
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

/// Result of an explicit source request. A deferred backoff has no fabricated read timestamps,
/// success, or report and therefore cannot satisfy a relay request.
public enum ReadReceipt: Sendable, Equatable {
    case performed(
        startedAt: Date, finishedAt: Date, succeeded: Bool, report: SourceSnapshot?)
    case deferred(retryAt: Date, sourceState: SourceState)
    case unavailable(sourceState: SourceState)

    public init(
        startedAt: Date, finishedAt: Date, succeeded: Bool, report: SourceSnapshot? = nil
    ) {
        self = .performed(
            startedAt: startedAt, finishedAt: finishedAt, succeeded: succeeded, report: report)
    }

    public var report: SourceSnapshot? {
        guard case .performed(_, _, _, let report) = self else { return nil }
        return report
    }

    public func performedAfter(_ date: Date) -> Bool {
        guard case .performed(_, let finishedAt, _, _) = self else { return false }
        return finishedAt >= date
    }

    public var performedSuccessfully: Bool {
        guard case .performed(_, _, let succeeded, _) = self else { return false }
        return succeeded
    }
}

public struct PendingRefreshRequest: Sendable, Equatable {
    public let id: RequestID
    public let readerID: ReaderID
    public let target: ManualRefreshTarget
    public let expiresAt: Date

    public init(
        id: RequestID, readerID: ReaderID, target: ManualRefreshTarget,
        expiresAt: Date
    ) {
        self.id = id
        self.readerID = readerID
        self.target = target
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
    case incompatible
    /// An existing command is unsafe or cannot be proven safe; it is never replaced.
    case unsafe
}

public struct ConfigurationOptionID: Codable, Hashable, Sendable {
    public let value: UUID

    public init(value: UUID = UUID()) {
        self.value = value
    }
}

public struct ConfigurationPreviewRevision: Codable, Hashable, Sendable {
    public let value: UUID

    public init(value: UUID = UUID()) {
        self.value = value
    }
}

public enum ConfigurationIntent: Sendable, Equatable {
    case add
    case replace(AccountID)

    public var accountID: AccountID? {
        switch self {
        case .add: nil
        case .replace(let accountID): accountID
        }
    }
}

public enum ConfigurationEnvironmentKey: String, Codable, CaseIterable, Sendable {
    case home = "HOME"
    case user = "USER"
    case language = "LANG"
    case path = "PATH"
    case codexHome = "CODEX_HOME"
}

public struct ConfigurationEnvironmentValue: Sendable, Equatable {
    public let key: ConfigurationEnvironmentKey
    public let value: String

    public init(key: ConfigurationEnvironmentKey, value: String) {
        self.key = key
        self.value = value
    }
}

/// Transient owner-visible launch material. It is never a diagnostic or snapshot field.
public struct ConfigurationLaunchPreview: Sendable, Equatable {
    public let executablePath: String
    public let interpreterPath: String?
    public let environment: [ConfigurationEnvironmentValue]

    public init(
        executablePath: String, interpreterPath: String? = nil,
        environment: [ConfigurationEnvironmentValue]
    ) {
        self.executablePath = executablePath
        self.interpreterPath = interpreterPath
        self.environment = environment
    }
}

public struct ConfigurationOption: Sendable, Equatable {
    public let id: ConfigurationOptionID
    public let product: ProductID
    public let launch: ConfigurationLaunchPreview

    public init(
        id: ConfigurationOptionID, product: ProductID, launch: ConfigurationLaunchPreview
    ) {
        self.id = id
        self.product = product
        self.launch = launch
    }
}

public enum StatusLineChangeKind: Sendable, Equatable {
    /// No `statusLine` setting exists; a minimal command object is created.
    case add
    /// An accepted `statusLine` object keeps its siblings; only `command` is replaced.
    case replaceCommand
}

/// Transient owner-visible description of the exact Claude Code status-line change. Like
/// `ConfigurationLaunchPreview`, it is display-only: never a diagnostic, snapshot, or relay field.
public struct ConfigurationStatusLinePreview: Sendable, Equatable {
    public let settingsPath: String
    public let helperPath: String
    public let existingExecutablePath: String?
    public let changeKind: StatusLineChangeKind

    public init(
        settingsPath: String, helperPath: String, existingExecutablePath: String? = nil,
        changeKind: StatusLineChangeKind
    ) {
        self.settingsPath = settingsPath
        self.helperPath = helperPath
        self.existingExecutablePath = existingExecutablePath
        self.changeKind = changeKind
    }
}

public struct ConfigurationPreview: Sendable, Equatable {
    public let product: ProductID
    public let optionID: ConfigurationOptionID
    public let revision: ConfigurationPreviewRevision
    public let intent: ConfigurationIntent
    public let launch: ConfigurationLaunchPreview
    /// Present only for a status-line source.
    public let statusLine: ConfigurationStatusLinePreview?

    public init(
        product: ProductID, optionID: ConfigurationOptionID,
        revision: ConfigurationPreviewRevision, intent: ConfigurationIntent,
        launch: ConfigurationLaunchPreview, statusLine: ConfigurationStatusLinePreview? = nil
    ) {
        self.product = product
        self.optionID = optionID
        self.revision = revision
        self.intent = intent
        self.launch = launch
        self.statusLine = statusLine
    }
}

public enum NotificationAuthorization: Sendable, Equatable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case failed
    case unknown
}

/// Typed, bounded window copy chosen by Application and localized by a framework adapter.
public enum WindowDisplayDescriptor: Codable, Hashable, Sendable {
    case standard(AccountWindow.StandardWindow)
    case additional(label: String?, durationMinutes: Int?)
}

/// A reset reminder. Standard identifiers retain their legacy form; additional-window
/// identifiers derive from the complete versioned selection so they cannot inherit an old opt-in.
public struct ResetRequest: Sendable, Equatable {
    public let selection: WindowSelection
    public let fireAt: Date
    public let accountLabel: String
    public let product: ProductID
    public let window: WindowDisplayDescriptor
    public let sourceState: SourceState
    public let fractionDigits: Int?

    public var accountWindow: AccountWindow? {
        guard case .standard(let accountWindow) = selection else { return nil }
        return accountWindow
    }

    public var identifier: String {
        switch selection {
        case .standard(let accountWindow):
            "reset.\(accountWindow.accountID.hex).\(accountWindow.window.rawValue)"
        case .additional:
            "reset.v1.\(selection.stableDigest)"
        }
    }

    public init(accountWindow: AccountWindow, fireAt: Date) {
        self.init(
            selection: .standard(accountWindow), fireAt: fireAt, accountLabel: "Account",
            product: .codex, window: .standard(accountWindow.window), sourceState: .reporting,
            fractionDigits: nil)
    }

    public init(
        selection: WindowSelection, fireAt: Date, accountLabel: String = "Account",
        product: ProductID = .codex,
        window: WindowDisplayDescriptor = .additional(label: nil, durationMinutes: nil),
        sourceState: SourceState = .reporting, fractionDigits: Int? = nil
    ) {
        self.selection = selection
        self.fireAt = fireAt
        self.accountLabel = accountLabel
        self.product = product
        self.window = window
        self.sourceState = sourceState
        self.fractionDigits = fractionDigits
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
    /// Immutable ActivityKit lifetime anchor retained by the static attributes in production.
    public let startedAt: Date
    public let usedPercent: Double
    public let resetsAt: Date
    public let observedAt: Date
    public let accountLabel: String
    public let product: ProductID
    public let window: WindowDisplayDescriptor
    public let sourceState: SourceState
    public let fractionDigits: Int?
    public let relevanceScore: Double

    public init(
        windowID: WindowID, usedPercent: Double, resetsAt: Date, observedAt: Date,
        startedAt: Date = .distantPast, accountLabel: String = "Account",
        product: ProductID? = nil,
        window: WindowDisplayDescriptor = .additional(label: nil, durationMinutes: nil),
        sourceState: SourceState = .reporting, fractionDigits: Int? = nil,
        relevanceScore: Double = 0
    ) {
        self.windowID = windowID
        self.startedAt = startedAt
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.observedAt = observedAt
        self.accountLabel = accountLabel
        self.product = product ?? windowID.product
        self.window = window
        self.sourceState = sourceState
        self.fractionDigits = fractionDigits
        self.relevanceScore = relevanceScore
    }
}

public struct RunningActivity: Sendable, Equatable {
    public let accountWindow: AccountWindow
    public let windowID: WindowID
    public let startedAt: Date

    public init(
        accountWindow: AccountWindow, windowID: WindowID, startedAt: Date = .distantPast
    ) {
        self.accountWindow = accountWindow
        self.windowID = windowID
        self.startedAt = startedAt
    }
}
