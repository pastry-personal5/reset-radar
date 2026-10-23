import Foundation
import ResetRadarDomain

public enum PairReaderError: Error, Equatable, Sendable {
    case notActive
    case readerCapReached
    case relay(RelayOutcome)
    case secretsUnavailable
    case storageFailed
    case encodingFailed
}

/// The package to show or copy, with its confirmation code and the relay-assigned deadline.
public struct PairingOffer: Sendable, Equatable, CustomStringConvertible {
    public let readerID: ReaderID
    public let package: PairingPackage
    /// The exact string behind the QR code and the manual copy.
    public let encoded: String
    public let confirmationCode: String
    public let expiresAt: Date

    public var description: String { "PairingOffer(redacted)" }
}

/// Registers a pending reader, builds its package, and follows it to activation or expiry.
/// Timers belong to the Mac driver, which calls `pollActivation` and `revokeIfExpired`.
public actor PairReader {
    private let publisher: any PublisherStore
    private let secrets: any SecretStore
    private let random: any SecretGenerator
    private let relay: any RelayGateway
    private let codec: any PairingCodec
    private let clock: any AppClock
    private struct Offer {
        let readerID: ReaderID
        let name: String
        let expiresAt: Date
    }

    private var current: Offer?

    public init(
        publisher: any PublisherStore, secrets: any SecretStore, random: any SecretGenerator,
        relay: any RelayGateway, codec: any PairingCodec, clock: any AppClock
    ) {
        self.publisher = publisher
        self.secrets = secrets
        self.random = random
        self.relay = relay
        self.codec = codec
        self.clock = clock
    }

    public func begin(deviceName: String) async throws -> PairingOffer {
        guard let state = try? await publisher.load(), state.lifecycle == .active,
            let endpoint = state.endpoint, let publisherID = state.publisherID
        else { throw PairReaderError.notActive }
        let keys = try await readKeys()
        let readerID: ReaderID
        let token: SecretValue
        do {
            readerID = try random.randomIdentifier(ReaderID.self)
            token = try random.randomBytes(count: 32)
        } catch {
            throw PairReaderError.secretsUnavailable
        }
        let expiresAt = try await register(
            readerID, digest: random.digest(of: token), endpoint: endpoint, admin: keys.admin)
        let package = PairingPackage(
            relayEndpoint: endpoint, readerID: readerID, readToken: token.reveal(),
            contentKey: keys.content.reveal(), publisherID: publisherID, keyVersion: 1,
            minimumSequence: state.lastPublishedSequence, registrationExpiresAt: expiresAt)
        let encoded: String
        do {
            encoded = try codec.encode(package)
        } catch {
            throw PairReaderError.encodingFailed
        }
        try await persist(readerID, name: deviceName, token: token, expiresAt: expiresAt)
        current = Offer(readerID: readerID, name: deviceName, expiresAt: expiresAt)
        return PairingOffer(
            readerID: readerID, package: package, encoded: encoded,
            confirmationCode: codec.confirmationCode(for: encoded), expiresAt: expiresAt)
    }

    /// `confirmed` only when the relay lists the reader as activated.
    public func pollActivation() async -> ActivationState {
        guard let offer = current else { return .expired }
        if await isActivated(offer.readerID) {
            await promote(offer.readerID, name: offer.name)
            current = nil
            return .confirmed
        }
        return clock.now >= offer.expiresAt ? .expired : .pending
    }

    /// Revokes the pending reader at its deadline (not before), unless it activated meanwhile.
    public func revokeIfExpired() async {
        guard let offer = current, await pollActivation() == .expired else { return }
        let revoked = await RelayRevocation.revoke(
            offer.readerID, publisher: publisher, secrets: secrets, relay: relay)
        if revoked == .revoked { current = nil }
    }

    private func readKeys() async throws -> (content: SecretValue, admin: SecretValue) {
        do {
            return (try await secrets.read(.contentKey), try await secrets.read(.adminToken))
        } catch {
            throw PairReaderError.secretsUnavailable
        }
    }

    private func register(
        _ id: ReaderID, digest: Data, endpoint: URL, admin: SecretValue
    ) async throws -> Date {
        let response = await relay.registerReader(
            id, digest: digest, endpoint: endpoint, adminToken: admin)
        switch response {
        case .value(let expiresAt): return expiresAt
        case .outcome(.readerCapReached): throw PairReaderError.readerCapReached
        case .outcome(let outcome): throw PairReaderError.relay(outcome)
        }
    }

    private func persist(
        _ id: ReaderID, name: String, token: SecretValue, expiresAt: Date
    ) async throws {
        do {
            try await secrets.write(.readerToken(id), value: token)
            try await publisher.transact {
                $0.pendingRegistrations.append(
                    PendingRegistration(readerID: id, name: name, expiresAt: expiresAt))
            }
        } catch {
            throw PairReaderError.storageFailed
        }
    }

    private func isActivated(_ id: ReaderID) async -> Bool {
        guard let state = try? await publisher.load(), let endpoint = state.endpoint,
            let admin = try? await secrets.read(.adminToken)
        else { return false }
        guard
            case .value(let readers) = await relay.listReaders(
                endpoint: endpoint, adminToken: admin)
        else { return false }
        return readers.contains { $0.id == id && $0.activated }
    }

    private func promote(_ id: ReaderID, name: String) async {
        let now = clock.now
        try? await publisher.transact { state in
            state.pendingRegistrations.removeAll { $0.readerID == id }
            if !state.devices.contains(where: { $0.readerID == id }) {
                state.devices.append(PairedDevice(readerID: id, name: name, pairedAt: now))
            }
        }
    }
}
