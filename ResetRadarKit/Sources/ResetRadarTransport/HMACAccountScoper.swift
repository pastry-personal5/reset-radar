import CryptoKit
import Foundation
import ResetRadarApplication
import ResetRadarDomain

public enum HMACAccountScoperError: Error, Equatable, Sendable {
    case invalidKeyLength
}

/// Serializes first use so concurrent source reads establish one per-installation scope key.
public actor HMACAccountScoper: AccountScoper {
    private let secrets: any SecretStore
    private let generator: any SecretGenerator
    private var keyTask: Task<SecretValue, Error>?

    public init(
        secrets: any SecretStore, generator: any SecretGenerator = CryptoSecretGenerator()
    ) {
        self.secrets = secrets
        self.generator = generator
    }

    public func scope(forAccountIdentifier identifier: String) async throws -> AccountScope {
        let key = try await scopeKey()
        let code = HMAC<SHA256>.authenticationCode(
            for: Data(identifier.utf8), using: SymmetricKey(data: key.reveal()))
        return AccountScope(data: Data(code.prefix(AccountScope.byteCount)))!
    }

    private func scopeKey() async throws -> SecretValue {
        if keyTask == nil {
            let secrets = secrets
            let generator = generator
            keyTask = Task {
                do {
                    let key = try await secrets.read(.accountScopeKey)
                    guard key.reveal().count == 32 else {
                        throw HMACAccountScoperError.invalidKeyLength
                    }
                    return key
                } catch SecretStoreError.notFound {
                    let key = try generator.randomBytes(count: 32)
                    guard key.reveal().count == 32 else {
                        throw HMACAccountScoperError.invalidKeyLength
                    }
                    try await secrets.write(.accountScopeKey, value: key)
                    return key
                }
            }
        }
        do {
            return try await keyTask!.value
        } catch {
            keyTask = nil
            throw error
        }
    }
}
