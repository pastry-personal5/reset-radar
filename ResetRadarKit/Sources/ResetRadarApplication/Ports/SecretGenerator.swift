import Foundation
import ResetRadarDomain

public protocol SecretGenerator: Sendable {
    func randomBytes(count: Int) throws -> SecretValue
    /// A uniform value in `0...1`, the jitter source for `BackoffPolicy`.
    func randomUnit() -> Double
    func digest(of secret: SecretValue) -> Data
}

extension SecretGenerator {
    /// A random identifier of any fixed-length Domain type.
    public func randomIdentifier<ID: ByteIdentifier>(_ type: ID.Type = ID.self) throws -> ID {
        let bytes = try randomBytes(count: ID.byteCount).reveal()
        guard let identifier = ID(data: bytes) else { throw SecretGeneratorError.wrongLength }
        return identifier
    }
}

public enum SecretGeneratorError: Error, Equatable, Sendable {
    case wrongLength
}
