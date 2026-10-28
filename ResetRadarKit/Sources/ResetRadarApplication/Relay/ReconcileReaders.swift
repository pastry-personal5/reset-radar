import Foundation
import ResetRadarDomain

public struct RosterEntry: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        case pending(expiresAt: Date)
        case activated
        /// Known locally but absent from the relay list: revoked or wiped elsewhere.
        case missingOnRelay
        /// Activated at the relay but absent from this Mac's local history.
        case unknownOnThisMac
    }

    public let readerID: ReaderID
    /// `nil` for a relay reader this Mac has no name for.
    public let name: String?
    public let status: Status
    public let date: Date?
    public let dateLabel: String?
    public let profileUnavailable: Bool
    public let deviceClass: ReaderDeviceClass?

    public init(
        readerID: ReaderID, name: String?, status: Status, date: Date? = nil,
        dateLabel: String? = nil, profileUnavailable: Bool = false,
        deviceClass: ReaderDeviceClass? = nil
    ) {
        self.readerID = readerID
        self.name = name
        self.status = status
        self.date = date
        self.dateLabel = dateLabel
        self.profileUnavailable = profileUnavailable
        self.deviceClass = deviceClass
    }

    public var shortID: String { "ID " + String(readerID.hex.suffix(8)) }
}

public enum ReconcileReadersOutcome: Sendable, Equatable {
    case reconciled([RosterEntry])
    case failed(RelayOutcome)
    case secretsUnavailable
    case storageFailed
    case notActive
}

/// Merges local device names with the relay's reader list at launch.
public actor ReconcileReaders {
    private let publisher: any PublisherStore
    private let secrets: any SecretStore
    private let relay: any RelayGateway
    private let clock: any AppClock
    private let profileCipher: (any ReaderProfileCipher)?

    public init(
        publisher: any PublisherStore, secrets: any SecretStore, relay: any RelayGateway,
        clock: any AppClock, profileCipher: (any ReaderProfileCipher)? = nil
    ) {
        self.publisher = publisher
        self.secrets = secrets
        self.relay = relay
        self.clock = clock
        self.profileCipher = profileCipher
    }

    public func run() async -> ReconcileReadersOutcome {
        let state: PublisherState
        do {
            state = try await publisher.load()
        } catch { return .storageFailed }
        guard state.lifecycle == .active, let endpoint = state.endpoint else { return .notActive }
        guard let admin = try? await secrets.read(.adminToken) else { return .secretsUnavailable }
        let listed = await listReaders(endpoint: endpoint, admin: admin)
        let remote: [RelayReader]
        switch listed {
        case .value(let readers): remote = readers
        case .outcome(let outcome): return .failed(outcome)
        }
        let now = clock.now
        let activated = Set(remote.filter(\.activated).map(\.id))
        let contentKey = try? await secrets.read(.contentKey)
        let profiles = Dictionary(
            uniqueKeysWithValues: remote.compactMap { reader in
                profile(reader, key: contentKey, publisherID: state.publisherID)
                    .map { (reader.id, $0) }
            })
        do {
            try await promoteActivated(remote, profiles: profiles, now: now)
        } catch { return .storageFailed }
        for pending in state.pendingRegistrations
        where pending.expiresAt <= now && !activated.contains(pending.readerID) {
            _ = await RelayRevocation.revoke(
                pending.readerID, publisher: publisher, secrets: secrets, relay: relay)
        }
        guard let merged = try? await publisher.load() else { return .storageFailed }
        return .reconciled(roster(local: merged, remote: remote, profiles: profiles))
    }

    private func listReaders(endpoint: URL, admin: SecretValue) async -> RelayResponse<
        [RelayReader]
    > {
        guard profileCipher != nil else {
            return await relay.listReaders(endpoint: endpoint, adminToken: admin)
        }
        let profileResponse = await relay.listReadersV2(endpoint: endpoint, adminToken: admin)
        if case .value = profileResponse { return profileResponse }
        let fallback = await relay.listReaders(endpoint: endpoint, adminToken: admin)
        if case .value = fallback { return fallback }
        return profileResponse
    }

    private func promoteActivated(
        _ remote: [RelayReader], profiles: [ReaderID: ReaderProfile], now: Date
    ) async throws {
        let activated = Set(remote.filter(\.activated).map(\.id))
        let legacyNames = profileCipher == nil
        try await publisher.transact { state in
            for pending in state.pendingRegistrations where activated.contains(pending.readerID) {
                let relayReader = remote.first { $0.id == pending.readerID }
                let profile = profiles[pending.readerID]
                if !state.devices.contains(where: { $0.readerID == pending.readerID }) {
                    state.devices.append(
                        PairedDevice(
                            readerID: pending.readerID,
                            name: profile?.displayName.value
                                ?? (legacyNames ? pending.name : "iPhone or iPad"),
                            pairedAt: relayReader?.activatedAt ?? now,
                            relayActivatedAt: relayReader?.activatedAt,
                            profileUnavailable: relayReader?.profileEnvelope != nil
                                && profile == nil,
                            deviceClass: profile?.deviceClass))
                }
            }
            for index in state.devices.indices {
                guard
                    let relayReader = remote.first(where: {
                        $0.id == state.devices[index].readerID
                    })
                else { continue }
                if let profile = profiles[relayReader.id] {
                    state.devices[index].name = profile.displayName.value
                    state.devices[index].deviceClass = profile.deviceClass
                    state.devices[index].profileUnavailable = false
                } else if relayReader.profileEnvelope != nil {
                    state.devices[index].profileUnavailable = true
                }
                if state.devices[index].relayActivatedAt == nil {
                    state.devices[index].relayActivatedAt = relayReader.activatedAt
                }
            }
            state.pendingRegistrations.removeAll { activated.contains($0.readerID) }
        }
    }

    private func profile(
        _ reader: RelayReader, key: SecretValue?, publisherID: PublisherID?
    ) -> ReaderProfile? {
        guard let profileCipher, let key, let publisherID,
            let envelope = reader.profileEnvelope,
            let opened = try? profileCipher.open(envelope, expected: nil, key: key),
            opened.header.readerID == reader.id,
            opened.header.publisherID == publisherID
        else { return nil }
        return opened.profile
    }

    private func roster(
        local: PublisherState, remote: [RelayReader], profiles: [ReaderID: ReaderProfile]
    ) -> [RosterEntry] {
        var entries: [RosterEntry] = []
        let remoteIDs = Set(remote.map(\.id))
        for reader in remote {
            let device = local.devices.first { $0.readerID == reader.id }
            let pending = local.pendingRegistrations.first { $0.readerID == reader.id }
            entries.append(
                RosterEntry(
                    readerID: reader.id,
                    name: reader.activated
                        ? (profiles[reader.id]?.displayName.value ?? device?.name) : nil,
                    status: reader.activated
                        ? (device == nil && pending == nil ? .unknownOnThisMac : .activated)
                        : .pending(expiresAt: pending?.expiresAt ?? clock.now),
                    date: reader.activated
                        ? (reader.activatedAt ?? device?.pairedAt) : pending?.expiresAt,
                    dateLabel: reader.activated
                        ? (reader.activatedAt == nil ? "First seen" : "Paired") : "Expires",
                    profileUnavailable: device?.profileUnavailable == true
                        || (reader.profileEnvelope != nil && profiles[reader.id] == nil),
                    deviceClass: device?.deviceClass ?? profiles[reader.id]?.deviceClass))
        }
        for device in local.devices where !remoteIDs.contains(device.readerID) {
            entries.append(
                RosterEntry(
                    readerID: device.readerID, name: device.name, status: .missingOnRelay,
                    date: device.relayActivatedAt ?? device.pairedAt,
                    dateLabel: device.relayActivatedAt == nil ? "First seen" : "Paired",
                    profileUnavailable: device.profileUnavailable == true,
                    deviceClass: device.deviceClass))
        }
        entries.sort { left, right in
            let leftRank = Self.rank(left.status)
            let rightRank = Self.rank(right.status)
            return leftRank == rightRank
                ? left.readerID.hex < right.readerID.hex : leftRank < rightRank
        }
        return entries
    }

    private static func rank(_ status: RosterEntry.Status) -> Int {
        switch status {
        case .activated: 0
        case .pending: 1
        case .missingOnRelay: 2
        case .unknownOnThisMac: 3
        }
    }
}
