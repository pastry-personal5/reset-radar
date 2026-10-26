import Foundation

public enum ProductID: String, Codable, CaseIterable, Hashable, Sendable {
    case codex
    case claudeCode
}

public enum SourceKind: String, Codable, CaseIterable, Hashable, Sendable {
    case codexAppServer
    case claudeCodeStatusLine
}

/// Fixed-length opaque bytes, written on the wire as lowercase hexadecimal.
public protocol ByteIdentifier: Codable, Hashable, Sendable {
    static var byteCount: Int { get }
    var data: Data { get }
    init?(data: Data)
}

extension ByteIdentifier {
    public init?(hex: String) {
        // Work on UTF-8 bytes: a multi-byte character must not shift Character-based indexing,
        // and only lowercase ASCII hexadecimal is valid.
        let digits = Array(hex.utf8)
        guard digits.count == 2 * Self.byteCount else { return nil }
        func nibble(_ digit: UInt8) -> UInt8? {
            switch digit {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): digit - UInt8(ascii: "0")
            case UInt8(ascii: "a")...UInt8(ascii: "f"): digit - UInt8(ascii: "a") + 10
            default: nil
            }
        }
        var bytes = Data()
        for pair in stride(from: 0, to: digits.count, by: 2) {
            guard let high = nibble(digits[pair]), let low = nibble(digits[pair + 1]) else {
                return nil
            }
            bytes.append(high << 4 | low)
        }
        self.init(data: bytes)
    }

    public var hex: String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let value = Self(hex: text) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected \(Self.byteCount) bytes as lowercase hexadecimal.")
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
}

/// Codex only: an opaque 128-bit value that the domain only compares.
public struct AccountScope: ByteIdentifier {
    public static let byteCount = 16
    public let data: Data
    public init?(data: Data) {
        guard data.count == Self.byteCount else { return nil }
        self.data = data
    }
}

/// Random opaque 128-bit Reset Radar identifier for one configured account row.
public struct AccountID: ByteIdentifier {
    public static let byteCount = 16
    public let data: Data
    public init?(data: Data) {
        guard data.count == Self.byteCount else { return nil }
        self.data = data
    }
}

/// Stable key for one standard window within a configured account.
public struct AccountWindow: Codable, Hashable, Sendable {
    public enum StandardWindow: String, Codable, CaseIterable, Hashable, Sendable {
        case fiveHour
        case weekly

        public var durationMinutes: Int {
            switch self {
            case .fiveHour: 300
            case .weekly: 10_080
            }
        }
    }

    public let accountID: AccountID
    public let window: StandardWindow

    public init(accountID: AccountID, window: StandardWindow) {
        self.accountID = accountID
        self.window = window
    }
}

/// A saved surface choice. Standard windows retain their stable account-local identity, while an
/// additional provider window is tied to its exact concrete ID and therefore cannot silently move
/// to a sibling when a provider changes its scope or limits.
public enum WindowSelection: Codable, Hashable, Sendable {
    case standard(AccountWindow)
    case additional(WindowID)

    public var accountID: AccountID {
        switch self {
        case .standard(let accountWindow): accountWindow.accountID
        case .additional(let windowID): windowID.accountID
        }
    }

    /// The versioned, length-delimited canonical identity used by persistence and App Intents.
    /// It contains no secret, and it can reconstruct an exact additional `WindowID`.
    public var canonicalIdentity: Data {
        var bytes = Data([1])
        switch self {
        case .standard(let accountWindow):
            bytes.append(0)
            bytes.append(accountWindow.accountID.data)
            bytes.append(accountWindow.window == .fiveHour ? 0 : 1)
        case .additional(let windowID):
            bytes.append(1)
            bytes.append(windowID.accountID.data)
            bytes.append(windowID.product == .codex ? 0 : 1)
            if let scope = windowID.scope {
                bytes.append(1)
                bytes.append(scope.data)
            } else {
                bytes.append(0)
            }
            if let duration = windowID.durationMinutes {
                bytes.append(1)
                bytes.appendBigEndian(UInt64(duration))
            } else {
                bytes.append(0)
            }
            bytes.appendLengthPrefixed(Data(windowID.limitID.utf8))
        }
        return bytes
    }

    /// A bounded deterministic digest for system identifiers and preference keys. The complete
    /// reversible identity remains in notification metadata and App Intent entity identifiers.
    public var stableDigest: String {
        StableSHA256.digest(canonicalIdentity).map { String(format: "%02x", $0) }.joined()
    }

    /// A versioned, non-secret persistence and App Intent identity.
    public var versionedID: String {
        let base64 = canonicalIdentity.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "v1_\(base64)"
    }

    public init?(versionedID: String) {
        guard versionedID.hasPrefix("v1_") else {
            self.init(legacyVersionedID: versionedID)
            return
        }
        guard let parsed = Self.parseCanonical(versionedID) else { return nil }
        self = parsed
    }

    private static func parseCanonical(_ versionedID: String) -> WindowSelection? {
        var encoded = String(versionedID.dropFirst(3))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded) else { return nil }
        var cursor = SelectionIdentityCursor(data)
        guard cursor.byte() == 1, let kind = cursor.byte() else { return nil }
        switch kind {
        case 0: return parseStandard(&cursor)
        case 1: return parseAdditional(&cursor)
        default: return nil
        }
    }

    private static func parseStandard(
        _ cursor: inout SelectionIdentityCursor
    ) -> WindowSelection? {
        guard let accountID = cursor.identifier(AccountID.self), let byte = cursor.byte(),
            cursor.isAtEnd
        else { return nil }
        let window: AccountWindow.StandardWindow
        switch byte {
        case 0: window = .fiveHour
        case 1: window = .weekly
        default: return nil
        }
        return .standard(AccountWindow(accountID: accountID, window: window))
    }

    private static func parseAdditional(
        _ cursor: inout SelectionIdentityCursor
    ) -> WindowSelection? {
        guard let accountID = cursor.identifier(AccountID.self),
            let product = product(cursor.byte()), let scope = optionalScope(&cursor),
            let duration = optionalDuration(&cursor),
            let limitData = cursor.lengthPrefixed(), !limitData.isEmpty, cursor.isAtEnd,
            let limitID = String(data: limitData, encoding: .utf8)
        else { return nil }
        return .additional(
            WindowID(
                accountID: accountID, product: product, scope: scope, limitID: limitID,
                durationMinutes: duration))
    }

    private static func product(_ byte: UInt8?) -> ProductID? {
        switch byte {
        case 0: .codex
        case 1: .claudeCode
        default: nil
        }
    }

    private static func optionalScope(
        _ cursor: inout SelectionIdentityCursor
    ) -> AccountScope?? {
        switch cursor.byte() {
        case 0: return .some(nil as AccountScope?)
        case 1:
            guard let scope = cursor.identifier(AccountScope.self) else { return nil }
            return .some(scope as AccountScope?)
        default: return nil
        }
    }

    private static func optionalDuration(
        _ cursor: inout SelectionIdentityCursor
    ) -> Int?? {
        switch cursor.byte() {
        case 0: return .some(nil as Int?)
        case 1:
            guard let raw = cursor.uint64(), raw > 0, raw <= UInt64(Int.max) else { return nil }
            return .some(Int(raw) as Int?)
        default: return nil
        }
    }

    /// Reads the draft dotted identity so an owner who exercised an earlier M15 build does not
    /// lose a saved widget selection. New writes always use the canonical length-delimited form.
    private init?(legacyVersionedID: String) {
        let parts = legacyVersionedID.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.first == "v1", parts.count >= 4 else { return nil }
        switch parts[1] {
        case "standard":
            guard parts.count == 4, let accountID = AccountID(hex: String(parts[2])),
                let window = AccountWindow.StandardWindow(rawValue: String(parts[3]))
            else { return nil }
            self = .standard(AccountWindow(accountID: accountID, window: window))
        case "additional":
            guard parts.count == 7, let accountID = AccountID(hex: String(parts[2])),
                let product = ProductID(rawValue: String(parts[3])),
                let limitData = Data(base64Encoded: String(parts[6])),
                let limitID = String(data: limitData, encoding: .utf8), !limitID.isEmpty
            else { return nil }
            let scope = parts[4] == "none" ? nil : AccountScope(hex: String(parts[4]))
            guard parts[4] == "none" || scope != nil else { return nil }
            let duration = parts[5] == "none" ? nil : Int(parts[5])
            guard parts[5] == "none" || duration.map({ $0 > 0 }) == true else { return nil }
            self = .additional(
                WindowID(
                    accountID: accountID, product: product, scope: scope, limitID: limitID,
                    durationMinutes: duration))
        default: return nil
        }
    }
}

private struct SelectionIdentityCursor {
    private let bytes: [UInt8]
    private var offset = 0

    init(_ data: Data) {
        bytes = Array(data)
    }

    var isAtEnd: Bool { offset == bytes.count }

    mutating func byte() -> UInt8? {
        guard offset < bytes.count else { return nil }
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func uint64() -> UInt64? {
        guard offset + 8 <= bytes.count else { return nil }
        defer { offset += 8 }
        return bytes[offset..<(offset + 8)].reduce(0) { ($0 << 8) | UInt64($1) }
    }

    mutating func lengthPrefixed() -> Data? {
        guard let length = uint64(), length <= UInt64(bytes.count - offset) else { return nil }
        let count = Int(length)
        defer { offset += count }
        return Data(bytes[offset..<(offset + count)])
    }

    mutating func identifier<ID: ByteIdentifier>(_ type: ID.Type) -> ID? {
        guard offset + ID.byteCount <= bytes.count else { return nil }
        defer { offset += ID.byteCount }
        return ID(data: Data(bytes[offset..<(offset + ID.byteCount)]))
    }
}

extension Data {
    fileprivate mutating func appendBigEndian(_ value: UInt64) {
        append(contentsOf: (0..<8).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }

    fileprivate mutating func appendLengthPrefixed(_ value: Data) {
        appendBigEndian(UInt64(value.count))
        append(value)
    }
}

/// Random 256-bit identifier for one Mac/relay relationship.
public struct PublisherID: ByteIdentifier {
    public static let byteCount = 32
    public let data: Data
    public init?(data: Data) {
        guard data.count == Self.byteCount else { return nil }
        self.data = data
    }
}

/// Random opaque 128-bit identifier for one paired iPhone or iPad.
public struct ReaderID: ByteIdentifier {
    public static let byteCount = 16
    public let data: Data
    public init?(data: Data) {
        guard data.count == Self.byteCount else { return nil }
        self.data = data
    }
}

/// Random 128-bit identifier of one manual-refresh request.
public struct RequestID: ByteIdentifier {
    public static let byteCount = 16
    public let data: Data
    public init?(data: Data) {
        guard data.count == Self.byteCount else { return nil }
        self.data = data
    }
}

/// Random 128-bit identifier of one iPhone installation, used by the Watch payload and receipt.
public struct InstallationID: ByteIdentifier {
    public static let byteCount = 16
    public let data: Data
    public init?(data: Data) {
        guard data.count == Self.byteCount else { return nil }
        self.data = data
    }
}

/// One concrete provider window. Never an array position; changes with the account scope.
public struct WindowID: Codable, Hashable, Sendable {
    public let accountID: AccountID
    public let product: ProductID
    public let scope: AccountScope?
    public let limitID: String
    public let durationMinutes: Int?

    public init(
        accountID: AccountID, product: ProductID, scope: AccountScope?, limitID: String,
        durationMinutes: Int?
    ) {
        self.accountID = accountID
        self.product = product
        self.scope = scope
        self.limitID = limitID
        self.durationMinutes = durationMinutes
    }
}
