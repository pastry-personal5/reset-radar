import Foundation
import ResetRadarDomain

public struct RosterEntry: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        case pending(expiresAt: Date)
        case activated
        /// Known locally but absent from the relay list: revoked or wiped elsewhere.
        case missingOnRelay
    }

    public let readerID: ReaderID
    /// `nil` for a relay reader this Mac has no name for.
    public let name: String?
    public let status: Status
}

public enum ReconcileReadersOutcome: Sendable, Equatable {
    case reconciled([RosterEntry])
    case failed(RelayOutcome)
    case secretsUnavailable
    case notActive
}

/// Merges local device names with the relay's reader list at launch.
public actor ReconcileReaders {
    private let publisher: any PublisherStore
    private let secrets: any SecretStore
    private let relay: any RelayGateway
    private let clock: any AppClock

    public init(
        publisher: any PublisherStore, secrets: any SecretStore, relay: any RelayGateway,
        clock: any AppClock
    ) {
        self.publisher = publisher
        self.secrets = secrets
        self.relay = relay
        self.clock = clock
    }

    public func run() async -> ReconcileReadersOutcome {
        guard let state = try? await publisher.load(), state.lifecycle == .active,
            let endpoint = state.endpoint
        else { return .notActive }
        guard let admin = try? await secrets.read(.adminToken) else { return .secretsUnavailable }
        let listed = await relay.listReaders(endpoint: endpoint, adminToken: admin)
        let remote: [RelayReader]
        switch listed {
        case .value(let readers): remote = readers
        case .outcome(let outcome): return .failed(outcome)
        }
        let now = clock.now
        let activated = Set(remote.filter(\.activated).map(\.id))
        await promoteActivated(activated, now: now)
        for pending in state.pendingRegistrations
        where pending.expiresAt <= now && !activated.contains(pending.readerID) {
            _ = await RelayRevocation.revoke(
                pending.readerID, publisher: publisher, secrets: secrets, relay: relay)
        }
        guard let merged = try? await publisher.load() else { return .notActive }
        return .reconciled(roster(local: merged, remote: remote))
    }

    private func promoteActivated(_ activated: Set<ReaderID>, now: Date) async {
        try? await publisher.transact { state in
            for pending in state.pendingRegistrations where activated.contains(pending.readerID) {
                if !state.devices.contains(where: { $0.readerID == pending.readerID }) {
                    state.devices.append(
                        PairedDevice(
                            readerID: pending.readerID, name: pending.name, pairedAt: now))
                }
            }
            state.pendingRegistrations.removeAll { activated.contains($0.readerID) }
        }
    }

    private func roster(local: PublisherState, remote: [RelayReader]) -> [RosterEntry] {
        var entries: [RosterEntry] = []
        let remoteIDs = Set(remote.map(\.id))
        for reader in remote {
            let device = local.devices.first { $0.readerID == reader.id }
            let pending = local.pendingRegistrations.first { $0.readerID == reader.id }
            entries.append(
                RosterEntry(
                    readerID: reader.id, name: device?.name ?? pending?.name,
                    status: reader.activated
                        ? .activated : .pending(expiresAt: pending?.expiresAt ?? clock.now)))
        }
        for device in local.devices where !remoteIDs.contains(device.readerID) {
            entries.append(
                RosterEntry(readerID: device.readerID, name: device.name, status: .missingOnRelay))
        }
        return entries
    }
}
