import Foundation
import ResetRadarDomain

public protocol PairingCodec: Sendable {
    func encode(_ package: PairingPackage) throws(PairingCodecError) -> String
    /// Rejects an expired or implausibly distant deadline, wrong-length key or token, and an
    /// endpoint outside the origin rule.
    func decode(_ text: String, now: Date) throws(PairingCodecError) -> PairingPackage
    /// The grouped confirmation code both devices show for the exact encoded string.
    func confirmationCode(for encoded: String) -> String
}
