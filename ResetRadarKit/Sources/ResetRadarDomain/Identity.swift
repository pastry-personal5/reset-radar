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
