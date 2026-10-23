import Foundation
import ResetRadarDomain

/// SHA-256 digests of the new write and administration tokens, for the owner to install as
/// Worker secrets before the relay is wiped and bound.
public struct ProvisioningDigests: Sendable, Equatable {
    public let writeToken: Data
    public let adminToken: Data

    public init(writeToken: Data, adminToken: Data) {
        self.writeToken = writeToken
        self.adminToken = adminToken
    }
}

public enum SetUpError: Error, Equatable, Sendable {
    case secretsUnavailable
    case storageFailed
}

public enum SetUpOutcome: Sendable, Equatable {
    case active
    /// `prepare` has not run, or setup is no longer pending.
    case notPrepared
    case secretsUnavailable
    case wipeFailed(RelayOutcome)
    case bindFailed(PublishOutcome)
}

/// Relay setup in two owner-visible steps. `prepare` pauses publication and persists a
/// recoverable pending setup; `activate` wipes the relay and binds the new publisher.
public actor SetUpRelay {
    private let publisher: any PublisherStore
    private let secrets: any SecretStore
    private let random: any SecretGenerator
    private let relay: any RelayGateway
    private let snapshots: any LocalSnapshotCommitting
    private let publishing: PublishSnapshot
    private let clock: any AppClock
    private let heartbeatSeconds: Int

    public init(
        publisher: any PublisherStore, secrets: any SecretStore, random: any SecretGenerator,
        relay: any RelayGateway, snapshots: any LocalSnapshotCommitting,
        publishing: PublishSnapshot, clock: any AppClock, heartbeatSeconds: Int
    ) {
        self.publisher = publisher
        self.secrets = secrets
        self.random = random
        self.relay = relay
        self.snapshots = snapshots
        self.publishing = publishing
        self.clock = clock
        self.heartbeatSeconds = heartbeatSeconds
    }

    public func prepare(endpoint: URL) async throws -> ProvisioningDigests {
        let previous = try await load()
        if let resumed = await resumableDigests(previous, endpoint: endpoint) { return resumed }
        let stale = previous.devices.map(\.readerID) + previous.pendingRegistrations.map(\.readerID)
        try await store { state in
            state = PublisherState()
            state.lifecycle = .setupPending
            state.endpoint = endpoint
        }
        let content = try generate()
        let write = try generate()
        let admin = try generate()
        let publisherID: PublisherID
        do {
            publisherID = try random.randomIdentifier(PublisherID.self)
            try await secrets.write(.contentKey, value: content)
            try await secrets.write(.writeToken, value: write)
            try await secrets.write(.adminToken, value: admin)
        } catch {
            throw SetUpError.secretsUnavailable
        }
        try await store { $0.publisherID = publisherID }
        for id in stale {
            // An orphaned reader token is unreferenced once the relay is wiped, so a failed
            // delete leaves nothing to act on.
            try? await secrets.delete(.readerToken(id))
        }
        return ProvisioningDigests(
            writeToken: random.digest(of: write), adminToken: random.digest(of: admin))
    }

    public func activate() async -> SetUpOutcome {
        guard let state = try? await publisher.load(), state.lifecycle == .setupPending,
            let endpoint = state.endpoint, let publisherID = state.publisherID
        else { return .notPrepared }
        guard let admin = try? await secrets.read(.adminToken) else { return .secretsUnavailable }
        let wipe = await relay.destroyRelay(endpoint: endpoint, adminToken: admin)
        guard wipe == .deleted else { return .wipeFailed(wipe) }
        await publishing.invalidateSecrets()
        guard let binding = await bindingSnapshot(publisherID: publisherID) else {
            return .bindFailed(.paused)
        }
        let bound = await publishing.bind(binding)
        guard case .published = bound else { return .bindFailed(bound) }
        guard (try? await store { $0.lifecycle = .active }) != nil else {
            return .bindFailed(.paused)
        }
        await publishing.resume()
        return .active
    }

    /// The current local content under the new publisher ID; `nil` if the heartbeat is invalid.
    private func bindingSnapshot(publisherID: PublisherID) async -> UsageSnapshot? {
        let base = try? await snapshots.load()
        return try? UsageSnapshot(
            publisherID: publisherID, generatedAt: clock.now, heartbeatSeconds: heartbeatSeconds,
            sources: base?.sources ?? [], windows: base?.windows ?? [])
    }

    private func resumableDigests(
        _ state: PublisherState, endpoint: URL
    ) async -> ProvisioningDigests? {
        guard state.lifecycle == .setupPending, state.endpoint == endpoint,
            state.publisherID != nil,
            let write = try? await secrets.read(.writeToken),
            let admin = try? await secrets.read(.adminToken),
            (try? await secrets.read(.contentKey)) != nil
        else { return nil }
        return ProvisioningDigests(
            writeToken: random.digest(of: write), adminToken: random.digest(of: admin))
    }

    private func generate() throws -> SecretValue {
        do {
            return try random.randomBytes(count: 32)
        } catch {
            throw SetUpError.secretsUnavailable
        }
    }

    private func load() async throws -> PublisherState {
        do {
            return try await publisher.load()
        } catch {
            throw SetUpError.storageFailed
        }
    }

    private func store(_ body: @Sendable (inout PublisherState) -> Void) async throws {
        do {
            try await publisher.transact(body)
        } catch {
            throw SetUpError.storageFailed
        }
    }
}
