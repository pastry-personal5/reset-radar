import Foundation
import ResetRadarApplication
import ResetRadarDomain

/// A reversible stand-in for AES-GCM: the envelope is JSON carrying header, snapshot, and a key
/// check. `targetSize` pads the encoded bytes with trailing spaces to an exact length.
public final class FakeEnvelopeCipher: EnvelopeCipher, @unchecked Sendable {
    private struct Payload: Codable {
        let header: EnvelopeHeader
        let snapshot: UsageSnapshot
        let key: Data
    }

    private struct State {
        var targetSize: Int?
        var sealed: [EnvelopeHeader] = []
        var sealKeys: [Data] = []
        var sealFailure: EnvelopeCipherError?
    }

    private let state = Locked(State())

    public init() {}

    public func setTargetSize(_ size: Int?) { state.withLock { $0.targetSize = size } }
    public func setSealFailure(_ error: EnvelopeCipherError?) {
        state.withLock { $0.sealFailure = error }
    }
    public var sealedHeaders: [EnvelopeHeader] { state.withLock { $0.sealed } }
    public var sealKeys: [Data] { state.withLock { $0.sealKeys } }

    public func seal(
        _ snapshot: UsageSnapshot, header: EnvelopeHeader, key: SecretValue
    ) throws(EnvelopeCipherError) -> SealedEnvelope {
        let (target, failure) = state.withLock { ($0.targetSize, $0.sealFailure) }
        if let failure { throw failure }
        guard
            var data = try? WireCoding.encoder().encode(
                Payload(header: header, snapshot: snapshot, key: key.reveal()))
        else { throw .malformed }
        if let target, data.count < target {
            data.append(Data(repeating: 0x20, count: target - data.count))
        }
        state.withLock {
            $0.sealed.append(header)
            $0.sealKeys.append(key.reveal())
        }
        return SealedEnvelope(header: header, encoded: data)
    }

    public func open(
        _ envelope: Data, key: SecretValue
    ) throws(EnvelopeCipherError) -> (header: EnvelopeHeader, snapshot: UsageSnapshot) {
        guard let payload = try? WireCoding.decoder().decode(Payload.self, from: envelope) else {
            throw .malformed
        }
        guard payload.key == key.reveal() else { throw .authenticationFailed }
        return (payload.header, payload.snapshot)
    }
}

/// Deterministic scoping that retains no identifier.
public final class FakeAccountScoper: AccountScoper, @unchecked Sendable {
    public init() {}

    public func scope(forAccountIdentifier identifier: String) async throws -> AccountScope {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in identifier.utf8 { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
        var bytes = Data()
        for shift in stride(from: 0, to: 64, by: 8) {
            bytes.append(UInt8(truncatingIfNeeded: hash >> UInt64(shift)))
        }
        bytes.append(bytes)
        return AccountScope(data: bytes)!
    }
}

/// Base64 of the wire JSON, with the validation rules of the real codec.
public final class FakePairingCodec: PairingCodec, @unchecked Sendable {
    public static let maximumLead: TimeInterval = 600

    public init() {}

    public func encode(_ package: PairingPackage) throws(PairingCodecError) -> String {
        guard let data = try? WireCoding.encoder().encode(package) else { throw .malformed }
        return data.base64EncodedString()
    }

    public func decode(_ text: String, now: Date) throws(PairingCodecError) -> PairingPackage {
        guard let data = Data(base64Encoded: text),
            let package = try? WireCoding.decoder().decode(PairingPackage.self, from: data)
        else { throw .malformed }
        guard package.registrationExpiresAt > now else { throw .expired }
        guard package.registrationExpiresAt.timeIntervalSince(now) <= Self.maximumLead else {
            throw .implausibleDeadline
        }
        guard package.readToken.count == 32, package.contentKey.count == 32 else {
            throw .invalidKeyLength
        }
        guard package.relayEndpoint.scheme == "https",
            package.relayEndpoint.host?.hasSuffix(".workers.dev") == true
        else { throw .endpointNotAllowed }
        return package
    }

    public func confirmationCode(for encoded: String) -> String {
        var hash: UInt32 = 2_166_136_261
        for byte in encoded.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        let hex = String(format: "%08X", hash)
        return "\(hex.prefix(4))-\(hex.suffix(4))"
    }
}
