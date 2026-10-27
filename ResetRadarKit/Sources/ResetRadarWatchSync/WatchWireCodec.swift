import Foundation
import ResetRadarDomain

/// The finite set of values allowed across the WatchConnectivity boundary.
///
/// Payloads and receipts are encoded as nested property lists rather than passed as arbitrary
/// dictionaries. This keeps framework input out of Application and makes the wire boundary easy
/// to fuzz without a paired device.
public enum WatchWireMessage: Sendable, Equatable {
    case payload(WatchPayload)
    case refreshRequest
    case refreshReply(WatchRefreshReply)
    case eraseReceipt(WatchEraseReceipt)
}

/// A reply to an interactive Watch refresh. `empty` means the iPhone has no displayable committed
/// payload; it is deliberately not a cleared payload and has no delivery revision.
public enum WatchRefreshReply: Sendable, Equatable {
    case payload(WatchPayload)
    case empty
}

public enum WatchWireCodecError: Error, Equatable, Sendable {
    case malformed
    case unsupportedVersion
    case oversized
    case unexpectedKeys
    case invalidBody
}

/// Strict, bounded property-list codec used by both WatchConnectivity directions.
public struct WatchWireCodec: Sendable {
    public static let currentVersion = 1
    public static let maximumBytes = 65_536
    public static let maximumNesting = 32

    private enum Key {
        static let version = "v"
        static let kind = "k"
        static let body = "b"
    }

    private enum Kind: String {
        case payload
        case refreshRequest
        case refreshReply
        case eraseReceipt
        case empty
    }

    public init() {}

    public func encode(_ message: WatchWireMessage) throws(WatchWireCodecError) -> [String: Any] {
        let kind: Kind
        let body: Data?
        switch message {
        case .payload(let payload):
            kind = .payload
            body = try encodeBody(payload)
        case .refreshRequest:
            kind = .refreshRequest
            body = nil
        case .refreshReply(.payload(let payload)):
            kind = .refreshReply
            body = try encodeBody(payload)
        case .refreshReply(.empty):
            kind = .empty
            body = nil
        case .eraseReceipt(let receipt):
            kind = .eraseReceipt
            body = try encodeBody(receipt)
        }
        var value: [String: Any] = [Key.version: Self.currentVersion, Key.kind: kind.rawValue]
        if let body { value[Key.body] = body }
        guard
            let data = try? PropertyListSerialization.data(
                fromPropertyList: value, format: .binary, options: 0),
            data.count <= Self.maximumBytes
        else { throw .oversized }
        return value
    }

    public func decode(_ value: [String: Any]) throws(WatchWireCodecError) -> WatchWireMessage {
        try validateEnvelope(value)
        let kind = try decodeKind(value)
        guard Set(value.keys) == expectedKeys(for: kind) else { throw .unexpectedKeys }
        return try decodeMessage(kind, from: value)
    }

    private func validateEnvelope(_ value: [String: Any]) throws(WatchWireCodecError) {
        guard
            let data = try? PropertyListSerialization.data(
                fromPropertyList: value, format: .binary, options: 0),
            data.count <= Self.maximumBytes
        else { throw .oversized }
        guard nesting(of: value) <= Self.maximumNesting else { throw .malformed }
    }

    private func decodeKind(_ value: [String: Any]) throws(WatchWireCodecError) -> Kind {
        guard let version = value[Key.version] as? Int else { throw .malformed }
        guard version == Self.currentVersion else { throw .unsupportedVersion }
        guard let rawKind = value[Key.kind] as? String, let kind = Kind(rawValue: rawKind) else {
            throw .malformed
        }
        return kind
    }

    private func expectedKeys(for kind: Kind) -> Set<String> {
        switch kind {
        case .payload, .refreshReply, .eraseReceipt: [Key.version, Key.kind, Key.body]
        case .refreshRequest, .empty: [Key.version, Key.kind]
        }
    }

    private func decodeMessage(
        _ kind: Kind, from value: [String: Any]
    ) throws(WatchWireCodecError) -> WatchWireMessage {
        switch kind {
        case .payload:
            return .payload(try decodeBody(value))
        case .refreshRequest:
            return .refreshRequest
        case .refreshReply:
            return .refreshReply(.payload(try decodeBody(value)))
        case .eraseReceipt:
            return .eraseReceipt(try decodeBody(value))
        case .empty:
            return .refreshReply(.empty)
        }
    }

    private func encodeBody<Value: Encodable>(_ value: Value) throws(WatchWireCodecError) -> Data {
        guard let data = try? PropertyListEncoder().encode(value), data.count <= Self.maximumBytes
        else {
            throw .oversized
        }
        return data
    }

    private func decodeBody<Value: Decodable>(
        _ value: [String: Any]
    ) throws(WatchWireCodecError) -> Value {
        guard let data = value[Key.body] as? Data,
            data.count <= Self.maximumBytes,
            validatesBody(data, as: Value.self),
            let decoded = try? PropertyListDecoder().decode(Value.self, from: data)
        else { throw .invalidBody }
        return decoded
    }

    /// Codable intentionally ignores unknown keys. Wire input must not: these two payload types
    /// are the whole cross-device contract, so reject a body that carries an unmodelled field.
    private func validatesBody<Value>(_ data: Data, as type: Value.Type) -> Bool {
        guard
            let body = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil)
                as? [String: Any]
        else { return false }
        guard nesting(of: body) <= Self.maximumNesting else { return false }
        let keys = Set(body.keys)
        if type == WatchPayload.self {
            let required: Set<String> = [
                "schemaVersion", "installationID", "deliveryRevision", "transportStatus", "cleared",
            ]
            let allowed: Set<String> = [
                "schemaVersion", "installationID", "deliveryRevision", "snapshot", "relaySequence",
                "transportStatus", "lastRelayContactAt", "lastCommitAt", "cleared",
            ]
            // PropertyListEncoder omits nil optional fields, but no unknown field may enter.
            return required.isSubset(of: keys) && keys.isSubset(of: allowed)
        }
        if type == WatchEraseReceipt.self {
            return keys == Set(["schemaVersion", "installationID", "deliveryRevision"])
        }
        return false
    }

    private func nesting(of value: Any, depth: Int = 0) -> Int {
        switch value {
        case let dictionary as [String: Any]:
            return dictionary.values.map { nesting(of: $0, depth: depth + 1) }.max() ?? depth
        case let array as [Any]:
            return array.map { nesting(of: $0, depth: depth + 1) }.max() ?? depth
        default:
            return depth
        }
    }
}
