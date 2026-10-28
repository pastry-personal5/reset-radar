import Foundation

public enum UsageSnapshotError: Error, Equatable, Sendable {
    case invalidHeartbeat
    case invalidAccountReferences
}

/// The unit the Mac publishes.
public struct UsageSnapshot: Codable, Hashable, Sendable {
    public static let supportedSchemaVersions = 2...2
    public static let currentSchemaVersion = SchemaVersion(rawValue: 2)
    /// Heartbeats outside `1...maximumHeartbeatSeconds` are rejected: zero would mark the Mac
    /// never publishing, and an absurd value would hide an outage.
    public static let maximumHeartbeatSeconds = 3_600

    public let schemaVersion: SchemaVersion
    public let publisherID: PublisherID
    public let generatedAt: Date
    public let heartbeatSeconds: Int
    public let accounts: [AccountMetadata]
    public let sources: [AccountSource]
    public let windows: [AllowanceWindow]
    public let diagnostics: [DiagnosticEvent]
    public let manualRefreshResults: [ManualRefreshResult]

    public init(
        publisherID: PublisherID, generatedAt: Date, heartbeatSeconds: Int,
        accounts: [AccountMetadata], sources: [AccountSource], windows: [AllowanceWindow],
        diagnostics: [DiagnosticEvent] = [], manualRefreshResults: [ManualRefreshResult] = []
    ) throws(UsageSnapshotError) {
        guard (1...Self.maximumHeartbeatSeconds).contains(heartbeatSeconds) else {
            throw .invalidHeartbeat
        }
        guard Self.referencesAreValid(accounts: accounts, sources: sources, windows: windows) else {
            throw .invalidAccountReferences
        }
        self.schemaVersion = Self.currentSchemaVersion
        self.publisherID = publisherID
        self.generatedAt = generatedAt
        self.heartbeatSeconds = heartbeatSeconds
        self.accounts = accounts
        self.sources = sources
        self.windows = windows
        self.diagnostics = diagnostics
        self.manualRefreshResults = manualRefreshResults
    }

    public func source(for accountID: AccountID) -> AccountSource? {
        sources.first { $0.accountID == accountID }
    }

    /// Copies only one account alias, preserving the collected observation and every other
    /// account's metadata. `nil` means this snapshot does not yet contain the account.
    public func replacingAlias(
        for accountID: AccountID, with alias: AccountAlias?
    ) throws(UsageSnapshotError) -> UsageSnapshot? {
        guard accounts.contains(where: { $0.id == accountID }) else { return nil }
        return try UsageSnapshot(
            publisherID: publisherID, generatedAt: generatedAt,
            heartbeatSeconds: heartbeatSeconds,
            accounts: accounts.map { account in
                account.id == accountID ? account.replacingAlias(alias) : account
            },
            sources: sources, windows: windows, diagnostics: diagnostics,
            manualRefreshResults: manualRefreshResults)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, publisherID, generatedAt, heartbeatSeconds, accounts, sources, windows
        case diagnostics, manualRefreshResults
    }

    /// Decodes through per-window validation: invalid windows are dropped and described by a
    /// redacted diagnostic stamped with `generatedAt`; a bad schema version or heartbeat
    /// rejects the whole snapshot.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try SchemaVersion.decodeRequired(
            from: container, forKey: .schemaVersion, supported: Self.supportedSchemaVersions)
        publisherID = try container.decode(PublisherID.self, forKey: .publisherID)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        heartbeatSeconds = try container.decode(Int.self, forKey: .heartbeatSeconds)
        guard (1...Self.maximumHeartbeatSeconds).contains(heartbeatSeconds) else {
            throw UsageSnapshotError.invalidHeartbeat
        }
        let catalog = try AccountCatalog(
            validating: container.decode([AccountMetadata].self, forKey: .accounts))
        accounts = catalog.accounts
        sources = try container.decode([AccountSource].self, forKey: .sources)
        let rawWindows = try container.decode([RawWindow].self, forKey: .windows)
        guard
            rawWindows.allSatisfy({ raw in
                guard let accountID = AccountID(hex: raw.accountID),
                    let account = catalog.account(id: accountID),
                    account.product.rawValue == raw.product
                else { return false }
                return true
            })
        else { throw UsageSnapshotError.invalidAccountReferences }
        let validation = WindowValidation.validate(rawWindows, now: generatedAt)
        windows = validation.valid
        guard Self.referencesAreValid(accounts: accounts, sources: sources, windows: windows) else {
            throw UsageSnapshotError.invalidAccountReferences
        }
        let wireDiagnostics =
            try container.decodeIfPresent([DiagnosticEvent].self, forKey: .diagnostics) ?? []
        diagnostics = wireDiagnostics + validation.diagnostics
        manualRefreshResults =
            try container.decodeIfPresent([ManualRefreshResult].self, forKey: .manualRefreshResults)
            ?? []
    }

    private static func referencesAreValid(
        accounts: [AccountMetadata], sources: [AccountSource], windows: [AllowanceWindow]
    ) -> Bool {
        guard let catalog = try? AccountCatalog(validating: accounts) else { return false }
        guard Set(sources.map(\.accountID)).count == sources.count,
            Set(sources.map(\.accountID)) == Set(accounts.map(\.id))
        else { return false }
        guard
            sources.allSatisfy({ source in
                catalog.account(id: source.accountID)?.product == source.product
            })
        else { return false }
        return windows.allSatisfy { window in
            catalog.account(id: window.accountID)?.product == window.product
        }
    }
}
