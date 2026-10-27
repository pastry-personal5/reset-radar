import CryptoKit
import Foundation
import ResetRadarApplication
import ResetRadarDomain

public struct AESGCMReaderProfileCipher: ReaderProfileCipher {
    public static let maximumEnvelopeBytes = 2_048
    public static let maximumRevision: UInt64 = 9_007_199_254_740_991

    private let nonceSource: @Sendable () throws -> Data

    public init(
        nonceSource: @escaping @Sendable () throws -> Data = {
            try CryptoSecretGenerator().randomBytes(count: 12).reveal()
        }
    ) {
        self.nonceSource = nonceSource
    }

    public func seal(
        _ profile: ReaderProfile, header: ReaderProfileHeader, key: SecretValue
    ) throws(ReaderProfileCipherError) -> Data {
        try validate(header)
        guard profile.profileVersion == header.profileVersion, key.reveal().count == 32,
            let plaintext = try? WireCoding.encoder().encode(profile),
            let aad = try? WireCoding.encoder().encode(header),
            let nonceData = try? nonceSource(), nonceData.count == 12,
            let nonce = try? AES.GCM.Nonce(data: nonceData),
            let box = try? AES.GCM.seal(
                plaintext, using: SymmetricKey(data: key.reveal()), nonce: nonce,
                authenticating: aad)
        else { throw .malformed }
        let envelope = ReaderProfileEnvelope(
            header: header, nonce: Base64URL.encode(nonceData),
            ciphertext: Base64URL.encode(box.ciphertext), tag: Base64URL.encode(box.tag))
        guard let encoded = try? WireCoding.encoder().encode(envelope),
            encoded.count <= Self.maximumEnvelopeBytes
        else { throw .malformed }
        return encoded
    }

    public func open(
        _ envelope: Data, expected: ReaderProfileHeader?, key: SecretValue
    ) throws(ReaderProfileCipherError) -> (header: ReaderProfileHeader, profile: ReaderProfile) {
        guard envelope.count <= Self.maximumEnvelopeBytes,
            let outer = try? WireCoding.decoder().decode(
                ReaderProfileEnvelope.self, from: envelope),
            let canonical = try? WireCoding.encoder().encode(outer), canonical == envelope,
            outer.protocolVersion == 2, outer.profileVersion == 1, outer.keyVersion == 1,
            (1...Self.maximumRevision).contains(outer.revision),
            key.reveal().count == 32,
            let nonceData = Base64URL.decode(outer.nonce), nonceData.count == 12,
            let ciphertext = Base64URL.decode(outer.ciphertext), !ciphertext.isEmpty,
            let tag = Base64URL.decode(outer.tag), tag.count == 16
        else { throw .malformed }
        let header = outer.header
        try validate(header)
        if let expected, expected != header { throw .authenticationFailed }
        guard let aad = try? WireCoding.encoder().encode(header),
            let nonce = try? AES.GCM.Nonce(data: nonceData),
            let box = try? AES.GCM.SealedBox(
                nonce: nonce, ciphertext: ciphertext, tag: tag),
            let plaintext = try? AES.GCM.open(
                box, using: SymmetricKey(data: key.reveal()), authenticating: aad),
            let profile = try? WireCoding.decoder().decode(ReaderProfile.self, from: plaintext),
            let canonicalPlaintext = try? WireCoding.encoder().encode(profile),
            canonicalPlaintext == plaintext, profile.profileVersion == header.profileVersion
        else { throw .authenticationFailed }
        return (header, profile)
    }

    private func validate(_ header: ReaderProfileHeader) throws(ReaderProfileCipherError) {
        guard header.protocolVersion == 2, header.profileVersion == 1, header.keyVersion == 1
        else { throw .unsupportedVersion }
        guard (1...Self.maximumRevision).contains(header.revision) else { throw .malformed }
    }
}
