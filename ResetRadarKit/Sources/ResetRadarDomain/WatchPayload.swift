import Foundation

public enum WatchPayloadError: Error, Equatable, Sendable {
    case clearedPayloadHasSnapshot
}

public struct WatchPayload: Codable, Hashable, Sendable {
    public static let supportedSchemaVersions = 1...1
    public static let currentSchemaVersion = SchemaVersion(rawValue: 1)

    public let schemaVersion: SchemaVersion
    public let installationID: InstallationID
    public let deliveryRevision: UInt64
    public let snapshot: UsageSnapshot?
    public let relaySequence: UInt64?
    public let transportStatus: TransportStatus
    public let lastRelayContactAt: Date?
    public let lastCommitAt: Date?
    public let cleared: Bool

    public init(
        installationID: InstallationID, deliveryRevision: UInt64, snapshot: UsageSnapshot?,
        relaySequence: UInt64?, transportStatus: TransportStatus, lastRelayContactAt: Date?,
        lastCommitAt: Date?, cleared: Bool
    ) throws(WatchPayloadError) {
        if cleared && snapshot != nil { throw .clearedPayloadHasSnapshot }
        self.schemaVersion = Self.currentSchemaVersion
        self.installationID = installationID
        self.deliveryRevision = deliveryRevision
        self.snapshot = snapshot
        self.relaySequence = relaySequence
        self.transportStatus = transportStatus
        self.lastRelayContactAt = lastRelayContactAt
        self.lastCommitAt = lastCommitAt
        self.cleared = cleared
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, installationID, deliveryRevision, snapshot, relaySequence
        case transportStatus, lastRelayContactAt, lastCommitAt, cleared
    }

    /// An unknown `transportStatus` decodes to `incompatible` so an older Watch shows a safe
    /// state instead of rejecting the payload.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try SchemaVersion.decodeRequired(
            from: container, forKey: .schemaVersion, supported: Self.supportedSchemaVersions)
        installationID = try container.decode(InstallationID.self, forKey: .installationID)
        deliveryRevision = try container.decode(UInt64.self, forKey: .deliveryRevision)
        snapshot = try container.decodeIfPresent(UsageSnapshot.self, forKey: .snapshot)
        relaySequence = try container.decodeIfPresent(UInt64.self, forKey: .relaySequence)
        let status = try container.decode(String.self, forKey: .transportStatus)
        transportStatus = TransportStatus(rawValue: status) ?? .incompatible
        lastRelayContactAt = try container.decodeIfPresent(Date.self, forKey: .lastRelayContactAt)
        lastCommitAt = try container.decodeIfPresent(Date.self, forKey: .lastCommitAt)
        cleared = try container.decode(Bool.self, forKey: .cleared)
        if cleared && snapshot != nil { throw WatchPayloadError.clearedPayloadHasSnapshot }
    }
}

/// Confirms cache erasure on the Watch; carries no usage or relay secret.
public struct WatchEraseReceipt: Codable, Hashable, Sendable {
    public static let supportedSchemaVersions = 1...1
    public static let currentSchemaVersion = SchemaVersion(rawValue: 1)

    public let schemaVersion: SchemaVersion
    public let installationID: InstallationID
    public let deliveryRevision: UInt64

    public init(installationID: InstallationID, deliveryRevision: UInt64) {
        self.schemaVersion = Self.currentSchemaVersion
        self.installationID = installationID
        self.deliveryRevision = deliveryRevision
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, installationID, deliveryRevision
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try SchemaVersion.decodeRequired(
            from: container, forKey: .schemaVersion, supported: Self.supportedSchemaVersions)
        installationID = try container.decode(InstallationID.self, forKey: .installationID)
        deliveryRevision = try container.decode(UInt64.self, forKey: .deliveryRevision)
    }
}
