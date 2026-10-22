import Foundation

/// Fields only; the codec lives in Transport. Holds secrets, so it never prints them.
public struct PairingPackage: Codable, Hashable, Sendable, CustomStringConvertible {
    public static let supportedSchemaVersions = 1...1
    public static let currentSchemaVersion = SchemaVersion(rawValue: 1)

    public let schemaVersion: SchemaVersion
    public let relayEndpoint: URL
    public let readerID: ReaderID
    public let readToken: Data
    public let contentKey: Data
    public let publisherID: PublisherID
    public let keyVersion: Int
    public let minimumSequence: UInt64
    public let registrationExpiresAt: Date

    public init(
        relayEndpoint: URL, readerID: ReaderID, readToken: Data, contentKey: Data,
        publisherID: PublisherID, keyVersion: Int, minimumSequence: UInt64,
        registrationExpiresAt: Date
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.relayEndpoint = relayEndpoint
        self.readerID = readerID
        self.readToken = readToken
        self.contentKey = contentKey
        self.publisherID = publisherID
        self.keyVersion = keyVersion
        self.minimumSequence = minimumSequence
        self.registrationExpiresAt = registrationExpiresAt
    }

    public var description: String { "PairingPackage(redacted)" }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, relayEndpoint, readerID, readToken, contentKey, publisherID
        case keyVersion, minimumSequence, registrationExpiresAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try SchemaVersion.decodeRequired(
            from: container, forKey: .schemaVersion, supported: Self.supportedSchemaVersions)
        relayEndpoint = try container.decode(URL.self, forKey: .relayEndpoint)
        readerID = try container.decode(ReaderID.self, forKey: .readerID)
        readToken = try container.decode(Data.self, forKey: .readToken)
        contentKey = try container.decode(Data.self, forKey: .contentKey)
        publisherID = try container.decode(PublisherID.self, forKey: .publisherID)
        keyVersion = try container.decode(Int.self, forKey: .keyVersion)
        minimumSequence = try container.decode(UInt64.self, forKey: .minimumSequence)
        registrationExpiresAt = try container.decode(Date.self, forKey: .registrationExpiresAt)
    }
}

/// The authenticated outer metadata of a relay envelope. It carries its own protocol and
/// envelope versions; Transport owns the acceptance policy for them.
public struct EnvelopeHeader: Codable, Hashable, Sendable {
    public let protocolVersion: Int
    public let envelopeVersion: Int
    public let publisherID: PublisherID
    public let sequence: UInt64
    public let keyVersion: Int

    public init(
        protocolVersion: Int, envelopeVersion: Int, publisherID: PublisherID, sequence: UInt64,
        keyVersion: Int
    ) {
        self.protocolVersion = protocolVersion
        self.envelopeVersion = envelopeVersion
        self.publisherID = publisherID
        self.sequence = sequence
        self.keyVersion = keyVersion
    }
}
