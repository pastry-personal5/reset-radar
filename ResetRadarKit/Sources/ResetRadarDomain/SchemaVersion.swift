import Foundation

/// Explicit version of a persisted or transmitted record's shape.
public struct SchemaVersion: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(Int.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// Returns `self` when it lies in `supported`; otherwise throws `SchemaError.unsupported`.
    @discardableResult
    public func require(in supported: ClosedRange<Int>) throws -> SchemaVersion {
        guard supported.contains(rawValue) else {
            throw SchemaError.unsupported(found: rawValue, supported: supported)
        }
        return self
    }

    /// Decodes the `schemaVersion` key and checks it before any other field is read, so a
    /// future shape is rejected as unsupported rather than as malformed.
    static func decodeRequired<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>, forKey key: Key, supported: ClosedRange<Int>
    ) throws -> SchemaVersion {
        try container.decode(SchemaVersion.self, forKey: key).require(in: supported)
    }
}

/// An unknown mandatory schema version; the whole record is rejected.
public enum SchemaError: Error, Equatable, Sendable {
    case unsupported(found: Int, supported: ClosedRange<Int>)
}
