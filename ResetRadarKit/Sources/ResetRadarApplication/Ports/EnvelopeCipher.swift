import Foundation
import ResetRadarDomain

public protocol EnvelopeCipher: Sendable {
    func seal(
        _ snapshot: UsageSnapshot, header: EnvelopeHeader, key: SecretValue
    ) throws(EnvelopeCipherError) -> SealedEnvelope

    func open(
        _ envelope: Data, key: SecretValue
    ) throws(EnvelopeCipherError) -> (header: EnvelopeHeader, snapshot: UsageSnapshot)
}

public enum ReaderProfileCipherError: Error, Equatable, Sendable {
    case malformed
    case authenticationFailed
    case unsupportedVersion
}

public protocol ReaderProfileCipher: Sendable {
    func seal(
        _ profile: ReaderProfile, header: ReaderProfileHeader, key: SecretValue
    ) throws(ReaderProfileCipherError) -> Data

    func open(
        _ envelope: Data, expected: ReaderProfileHeader?, key: SecretValue
    ) throws(ReaderProfileCipherError) -> (header: ReaderProfileHeader, profile: ReaderProfile)
}
