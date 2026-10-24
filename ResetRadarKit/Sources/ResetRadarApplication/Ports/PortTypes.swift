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
}

/// A reset reminder. The identifier derives from the local account and standard window only;
/// copy names the displayed alias and carries no formatted time or percentage.
public struct ResetRequest: Sendable, Equatable {
    public let accountWindow: AccountWindow
    public let fireAt: Date

    public var identifier: String {
        "reset.\(accountWindow.accountID.hex).\(accountWindow.window.rawValue)"
    }

    public init(accountWindow: AccountWindow, fireAt: Date) {
        self.accountWindow = accountWindow
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
    public let accountWindow: AccountWindow
    public let windowID: WindowID

    public init(accountWindow: AccountWindow, windowID: WindowID) {
        self.accountWindow = accountWindow
        self.windowID = windowID
    }
}
