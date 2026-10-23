import Foundation
import ResetRadarDomain

public enum DestroyOutcome: Sendable, Equatable {
    case destroyed
    /// The remote delete failed: local state is kept, publication stays paused, retry later.
    case remoteFailed(RelayOutcome)
    case secretsUnavailable
    case storageFailed
}

/// Destroys the relay, then local secrets and state, in that order, so an interrupted run can
/// be repeated.
public actor DestroyRelay {
    private let publisher: any PublisherStore
    private let secrets: any SecretStore
    private let relay: any RelayGateway
    private let publishing: PublishSnapshot

    public init(
        publisher: any PublisherStore, secrets: any SecretStore, relay: any RelayGateway,
        publishing: PublishSnapshot
    ) {
        self.publisher = publisher
        self.secrets = secrets
        self.relay = relay
        self.publishing = publishing
    }

    public func run() async -> DestroyOutcome {
        do {
            try await publisher.transact { $0.lifecycle = .destroyPending }
        } catch {
            return .storageFailed
        }
        guard let state = try? await publisher.load() else { return .storageFailed }
        if let outcome = await destroyRemote(state) { return outcome }
        await publishing.invalidateSecrets()
        let readerIDs = state.devices.map(\.readerID) + state.pendingRegistrations.map(\.readerID)
        let names: [SecretName] =
            [.contentKey, .writeToken, .adminToken, .accountScopeKey]
            + readerIDs.map { SecretName.readerToken($0) }
        for name in names {
            do {
                try await secrets.delete(name)
            } catch {
                return .secretsUnavailable
            }
        }
        do {
            try await publisher.transact { $0 = PublisherState() }
        } catch {
            return .storageFailed
        }
        return .destroyed
    }

    /// `nil` when the remote side is gone. A missing administration token after an interrupted
    /// run means the remote delete already succeeded, since secrets are deleted only after it.
    private func destroyRemote(_ state: PublisherState) async -> DestroyOutcome? {
        guard let endpoint = state.endpoint else { return nil }
        let admin: SecretValue
        do {
            admin = try await secrets.read(.adminToken)
        } catch SecretStoreError.notFound {
            return nil
        } catch {
            return .secretsUnavailable
        }
        let outcome = await relay.destroyRelay(endpoint: endpoint, adminToken: admin)
        return outcome == .deleted ? nil : .remoteFailed(outcome)
    }
}
