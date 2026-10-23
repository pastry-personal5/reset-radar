import CryptoKit
import Foundation
import ResetRadarApplication
import Security

public enum CryptoSecretGeneratorError: Error, Sendable {
    case invalidCount
    case randomUnavailable
}

public struct CryptoSecretGenerator: SecretGenerator {
    public init() {}

    public func randomBytes(count: Int) throws -> SecretValue {
        guard count > 0 else { throw CryptoSecretGeneratorError.invalidCount }
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
            throw CryptoSecretGeneratorError.randomUnavailable
        }
        return SecretValue(Data(bytes))
    }

    public func randomUnit() -> Double {
        let bits = UInt64.random(in: 0...9_007_199_254_740_991)
        return Double(bits) / 9_007_199_254_740_991
    }

    public func digest(of secret: SecretValue) -> Data {
        Data(SHA256.hash(data: secret.reveal()))
    }
}
