import CryptoKit
import Foundation
import ResetRadarApplication
import ResetRadarDomain

public struct AESGCMEnvelopeCipher: EnvelopeCipher {
    public static let maximumSequence: UInt64 = 9_007_199_254_740_991
    public static let maximumEnvelopeBytes = 65_536

    private let nonceSource: @Sendable () throws -> Data

    public init(
        nonceSource: @escaping @Sendable () throws -> Data = {
            try CryptoSecretGenerator().randomBytes(count: 12).reveal()
        }
    ) {
        self.nonceSource = nonceSource
    }

    public func seal(
        _ snapshot: UsageSnapshot, header: EnvelopeHeader, key: SecretValue
    ) throws(EnvelopeCipherError) -> SealedEnvelope {
        try validate(header)
        guard snapshot.publisherID == header.publisherID,
            snapshot.schemaVersion == UsageSnapshot.currentSchemaVersion
        else { throw .invalidSnapshot }
        guard key.reveal().count == 32 else { throw .malformed }
        guard let plaintext = try? WireCoding.encoder().encode(snapshot),
            let additionalData = try? WireCoding.encoder().encode(header),
            let nonceBytes = try? nonceSource(), nonceBytes.count == 12,
            let nonce = try? AES.GCM.Nonce(data: nonceBytes),
            let box = try? AES.GCM.seal(
                plaintext, using: SymmetricKey(data: key.reveal()), nonce: nonce,
                authenticating: additionalData)
        else { throw .malformed }
        let outer = EnvelopeOuter(
            header: header, nonce: Base64URL.encode(nonceBytes),
            ciphertext: Base64URL.encode(box.ciphertext), tag: Base64URL.encode(box.tag))
        guard let encoded = try? WireCoding.encoder().encode(outer),
            encoded.count <= Self.maximumEnvelopeBytes
        else { throw .malformed }
        return SealedEnvelope(header: header, encoded: encoded)
    }

    public func open(
        _ envelope: Data, key: SecretValue
    ) throws(EnvelopeCipherError) -> (header: EnvelopeHeader, snapshot: UsageSnapshot) {
        guard envelope.count <= Self.maximumEnvelopeBytes,
            let outer = try? WireCoding.decoder().decode(EnvelopeOuter.self, from: envelope),
            let canonical = try? WireCoding.encoder().encode(outer), canonical == envelope,
            let nonceBytes = Base64URL.decode(outer.nonce), nonceBytes.count == 12,
            let ciphertext = Base64URL.decode(outer.ciphertext),
            let tag = Base64URL.decode(outer.tag), tag.count == 16,
            key.reveal().count == 32
        else { throw .malformed }
        let header = outer.header
        try validate(header)
        guard let aad = try? WireCoding.encoder().encode(header),
            let nonce = try? AES.GCM.Nonce(data: nonceBytes),
            let box = try? AES.GCM.SealedBox(
                nonce: nonce, ciphertext: ciphertext, tag: tag),
            let plaintext = try? AES.GCM.open(
                box, using: SymmetricKey(data: key.reveal()), authenticating: aad)
        else { throw .authenticationFailed }
        guard let snapshot = try? WireCoding.decoder().decode(UsageSnapshot.self, from: plaintext),
            let canonicalPlaintext = try? WireCoding.encoder().encode(snapshot),
            canonicalPlaintext == plaintext, snapshot.publisherID == header.publisherID
        else { throw .invalidSnapshot }
        return (header, snapshot)
    }

    private func validate(_ header: EnvelopeHeader) throws(EnvelopeCipherError) {
        guard header.protocolVersion == 1, header.envelopeVersion == 1,
            header.keyVersion == 1
        else { throw .unsupportedVersion }
        guard (1...Self.maximumSequence).contains(header.sequence) else { throw .malformed }
    }
}

struct EnvelopeOuter: Codable {
    let protocolVersion: Int
    let envelopeVersion: Int
    let publisherID: PublisherID
    let sequence: UInt64
    let keyVersion: Int
    let nonce: String
    let ciphertext: String
    let tag: String

    var header: EnvelopeHeader {
        EnvelopeHeader(
            protocolVersion: protocolVersion, envelopeVersion: envelopeVersion,
            publisherID: publisherID, sequence: sequence, keyVersion: keyVersion)
    }

    init(header: EnvelopeHeader, nonce: String, ciphertext: String, tag: String) {
        protocolVersion = header.protocolVersion
        envelopeVersion = header.envelopeVersion
        publisherID = header.publisherID
        sequence = header.sequence
        keyVersion = header.keyVersion
        self.nonce = nonce
        self.ciphertext = ciphertext
        self.tag = tag
    }

    static func parse(_ data: Data) -> EnvelopeOuter? {
        guard data.count <= AESGCMEnvelopeCipher.maximumEnvelopeBytes,
            let outer = try? WireCoding.decoder().decode(Self.self, from: data),
            let canonical = try? WireCoding.encoder().encode(outer), canonical == data,
            outer.protocolVersion == 1, outer.envelopeVersion == 1, outer.keyVersion == 1,
            (1...AESGCMEnvelopeCipher.maximumSequence).contains(outer.sequence),
            let nonceBytes = Base64URL.decode(outer.nonce), nonceBytes.count == 12,
            Base64URL.decode(outer.ciphertext) != nil,
            let tagBytes = Base64URL.decode(outer.tag), tagBytes.count == 16
        else { return nil }
        return outer
    }
}
