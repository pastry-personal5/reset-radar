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

extension SecretGenerator {
    /// A random UUID, for fetch claims and gate claims.
    public func randomUUID() throws -> UUID {
        let bytes = Array(try randomBytes(count: 16).reveal())
        guard bytes.count == 16 else { throw SecretGeneratorError.wrongLength }
        return UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
            ))
    }
}

public enum SecretGeneratorError: Error, Equatable, Sendable {
    case wrongLength
}
