import CryptoKit
import Foundation
import ResetRadarApplication
import ResetRadarDomain

public struct JSONPairingCodec: PairingCodec {
    public init() {}

    public func encode(_ package: PairingPackage) throws(PairingCodecError) -> String {
        try validate(package)
        guard let bytes = try? WireCoding.encoder().encode(package) else { throw .malformed }
        return Base64URL.encode(bytes)
    }

    public func decode(_ text: String, now: Date) throws(PairingCodecError) -> PairingPackage {
        guard let bytes = Base64URL.decode(text) else { throw .malformed }
        if let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] {
            if let schemaVersion = object["schemaVersion"] as? Int, schemaVersion != 1 {
                throw .unsupportedVersion
            }
            if let keyVersion = object["keyVersion"] as? Int, keyVersion != 1 {
                throw .unsupportedVersion
            }
            if let readerID = object["readerID"] as? String, ReaderID(hex: readerID) == nil {
                throw .invalidIdentifier
            }
            let invalidPublisherID =
                (object["publisherID"] as? String).map {
                    PublisherID(hex: $0) == nil
                } ?? false
            if invalidPublisherID {
                throw .invalidIdentifier
            }
        }
        guard
            let package = try? WireCoding.decoder().decode(PairingPackage.self, from: bytes),
            let canonical = try? WireCoding.encoder().encode(package),
            bytes == canonical, Base64URL.encode(bytes) == text
        else { throw .malformed }
        try validate(package)
        let offset = package.registrationExpiresAt.timeIntervalSince(now)
        guard offset >= -30 else { throw .expired }
        guard offset <= 330 else { throw .implausibleDeadline }
        return package
    }

    public func confirmationCode(for encoded: String) -> String {
        let digest = SHA256.hash(data: Data(encoded.utf8))
        let hex = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        return stride(from: 0, to: hex.count, by: 4).map { offset in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            let end = hex.index(start, offsetBy: 4)
            return String(hex[start..<end])
        }.joined(separator: "-")
    }

    private func validate(_ package: PairingPackage) throws(PairingCodecError) {
        guard package.schemaVersion == .init(rawValue: 1), package.keyVersion == 1,
            package.minimumSequence <= 9_007_199_254_740_991
        else { throw .unsupportedVersion }
        guard OriginGuard.accepts(package.relayEndpoint) else { throw .endpointNotAllowed }
        guard package.contentKey.count == 32 else { throw .invalidKeyLength }
        guard package.readToken.count == 32 else { throw .invalidTokenLength }
    }
}

enum Base64URL {
    static func encode(_ bytes: Data) -> String {
        bytes.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ text: String) -> Data? {
        guard !text.isEmpty,
            text.utf8.allSatisfy({
                (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains($0)
                    || (UInt8(ascii: "a")...UInt8(ascii: "z")).contains($0)
                    || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0)
                    || $0 == UInt8(ascii: "-") || $0 == UInt8(ascii: "_")
            })
        else { return nil }
        let base64 = text.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let result = Data(base64Encoded: base64 + padding), encode(result) == text else {
            return nil
        }
        return result
    }
}
