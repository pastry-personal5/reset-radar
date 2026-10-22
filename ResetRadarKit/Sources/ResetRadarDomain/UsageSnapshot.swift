import Foundation

public enum UsageSnapshotError: Error, Equatable, Sendable {
    case invalidHeartbeat
}

/// The unit the Mac publishes.
public struct UsageSnapshot: Codable, Hashable, Sendable {
    public static let supportedSchemaVersions = 1...1
    public static let currentSchemaVersion = SchemaVersion(rawValue: 1)
    /// Heartbeats outside `1...maximumHeartbeatSeconds` are rejected: zero would mark the Mac
    /// never publishing, and an absurd value would hide an outage.
    public static let maximumHeartbeatSeconds = 3_600

    public let schemaVersion: SchemaVersion
    public let publisherID: PublisherID
    public let generatedAt: Date
    public let heartbeatSeconds: Int
    public let sources: [ProductSource]
    public let windows: [AllowanceWindow]
    public let diagnostics: [DiagnosticEvent]
    public let manualRefreshResults: [ManualRefreshResult]

    public init(
        publisherID: PublisherID, generatedAt: Date, heartbeatSeconds: Int,
        sources: [ProductSource], windows: [AllowanceWindow],
        diagnostics: [DiagnosticEvent] = [], manualRefreshResults: [ManualRefreshResult] = []
    ) throws(UsageSnapshotError) {
        guard (1...Self.maximumHeartbeatSeconds).contains(heartbeatSeconds) else {
            throw .invalidHeartbeat
        }
        self.schemaVersion = Self.currentSchemaVersion
        self.publisherID = publisherID
        self.generatedAt = generatedAt
        self.heartbeatSeconds = heartbeatSeconds
        self.sources = sources
        self.windows = windows
        self.diagnostics = diagnostics
        self.manualRefreshResults = manualRefreshResults
    }

    public func source(for product: ProductID) -> ProductSource? {
        sources.first { $0.product == product }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, publisherID, generatedAt, heartbeatSeconds, sources, windows
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
        sources = try container.decode([ProductSource].self, forKey: .sources)
        let rawWindows = try container.decode([RawWindow].self, forKey: .windows)
        let validation = WindowValidation.validate(rawWindows, now: generatedAt)
        windows = validation.valid
        let wireDiagnostics =
            try container.decodeIfPresent([DiagnosticEvent].self, forKey: .diagnostics) ?? []
        diagnostics = wireDiagnostics + validation.diagnostics
        manualRefreshResults =
            try container.decodeIfPresent([ManualRefreshResult].self, forKey: .manualRefreshResults)
            ?? []
    }
}
