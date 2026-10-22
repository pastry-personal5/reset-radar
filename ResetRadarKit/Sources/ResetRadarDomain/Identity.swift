import Foundation

public enum ProductID: String, Codable, CaseIterable, Hashable, Sendable {
    case codex
    case claudeCode
}

public enum SourceKind: String, Codable, CaseIterable, Hashable, Sendable {
    case codexAppServer
    case claudeCodeStatusLine
}

/// Stable key for Home cells, widget configuration, intents, and notification opt-in.
public enum HomeSlot: String, Codable, CaseIterable, Hashable, Sendable {
    case codexFiveHour
    case codexWeekly
    case claudeCodeFiveHour
    case claudeCodeWeekly

    public var product: ProductID {
        switch self {
        case .codexFiveHour, .codexWeekly: .codex
        case .claudeCodeFiveHour, .claudeCodeWeekly: .claudeCode
        }
    }

    /// The exact window duration this slot resolves to; no other duration is ever inferred.
    public var durationMinutes: Int {
        switch self {
        case .codexFiveHour, .claudeCodeFiveHour: 300
        case .codexWeekly, .claudeCodeWeekly: 10_080
        }
    }
}

/// Fixed-length opaque bytes, written on the wire as lowercase hexadecimal.
public protocol ByteIdentifier: Codable, Hashable, Sendable {
    static var byteCount: Int { get }
    var data: Data { get }
    init?(data: Data)
}

extension ByteIdentifier {
    public init?(hex: String) {
        guard hex.utf8.count == 2 * Self.byteCount else { return nil }
        var bytes = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16),
                hex[index..<next].allSatisfy({ $0.isNumber || ("a"..."f").contains($0) })
            else { return nil }
            bytes.append(byte)
            index = next
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
    public let product: ProductID
    public let scope: AccountScope?
    public let limitID: String
    public let durationMinutes: Int?

    public init(product: ProductID, scope: AccountScope?, limitID: String, durationMinutes: Int?) {
        self.product = product
        self.scope = scope
        self.limitID = limitID
        self.durationMinutes = durationMinutes
    }
}
