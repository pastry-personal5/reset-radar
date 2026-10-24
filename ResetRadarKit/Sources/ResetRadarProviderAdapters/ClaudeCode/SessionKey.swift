import CryptoKit
import Foundation

/// The first 128 bits of SHA-256 over a Claude Code session ID, as 32 lowercase hex characters.
/// The raw identifier exists only inside `init(sessionID:)`; nothing here can reveal it. Swift
/// gives no way to prove immediate release of the immutable source string, and none is claimed.
public struct SessionKey: Hashable, Sendable {
    public static let hexLength = 32
    public let hex: String

    public init(sessionID: String) {
        let digest = SHA256.hash(data: Data(sessionID.utf8))
        hex = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    public init?(hex: String) {
        let bytes = hex.utf8
        guard bytes.count == Self.hexLength,
            bytes.allSatisfy({ ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66) })
        else { return nil }
        self.hex = hex
    }

    public var fileName: String { "\(hex).json" }

}

extension SessionKey: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "SessionKey" }
    public var debugDescription: String { "SessionKey" }
}
