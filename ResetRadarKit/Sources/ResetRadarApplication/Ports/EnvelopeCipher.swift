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
