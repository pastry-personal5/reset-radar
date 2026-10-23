import Foundation
import ResetRadarDomain

public enum RevokeOutcome: Sendable, Equatable {
    case revoked
    /// The relay did not confirm, so the local entry stays.
    case failed(RelayOutcome)
    case secretsUnavailable
    case notActive
}

/// Revocation shared by `RevokeReader`, `ReconcileReaders`, and `PairReader`: the relay first,
/// then the local entry and its token.
enum RelayRevocation {
    static func revoke(
        _ id: ReaderID, publisher: any PublisherStore, secrets: any SecretStore,
        relay: any RelayGateway
    ) async -> RevokeOutcome {
        guard let state = try? await publisher.load(), let endpoint = state.endpoint else {
            return .notActive
        }
        guard let admin = try? await secrets.read(.adminToken) else { return .secretsUnavailable }
        let outcome = await relay.revokeReader(id, endpoint: endpoint, adminToken: admin)
        guard outcome == .deleted else { return .failed(outcome) }
        try? await publisher.transact { state in
            state.devices.removeAll { $0.readerID == id }
            state.pendingRegistrations.removeAll { $0.readerID == id }
        }
        // The relay no longer honors the token, so a leftover Keychain item grants nothing.
        try? await secrets.delete(.readerToken(id))
        return .revoked
    }
}

public actor RevokeReader {
    private let publisher: any PublisherStore
    private let secrets: any SecretStore
    private let relay: any RelayGateway

    public init(
        publisher: any PublisherStore, secrets: any SecretStore, relay: any RelayGateway
    ) {
        self.publisher = publisher
        self.secrets = secrets
        self.relay = relay
    }

    public func revoke(_ id: ReaderID) async -> RevokeOutcome {
        await RelayRevocation.revoke(id, publisher: publisher, secrets: secrets, relay: relay)
    }
}
