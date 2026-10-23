import Foundation
import ResetRadarDomain

/// A named secret. Mac and reader roles use different subsets.
public enum SecretName: Hashable, Sendable {
    case contentKey
    /// The relay write bearer token (Mac).
    case writeToken
    /// The relay administration bearer token (Mac).
    case adminToken
    /// This reader's own read token (iPhone or iPad).
    case readToken
    /// The Mac's copy of one registered reader's read token.
    case readerToken(ReaderID)
    case accountScopeKey
}

/// Secret bytes. Redacted from every string form and mirror, so logging or `dump` cannot leak it.
public struct SecretValue: Sendable, Equatable {
    private let bytes: Data

    public init(_ bytes: Data) {
        self.bytes = bytes
    }

    /// The only way to read the bytes; call sites are the adapters that need them.
    public func reveal() -> Data { bytes }
}

extension SecretValue: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "SecretValue(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: []) }
}
