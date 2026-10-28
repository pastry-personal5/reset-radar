import Foundation
import ResetRadarDomain

/// A decoded package, ready for the owner to compare its confirmation code with the Mac's.
public struct PairingPreview: Sendable, Equatable, CustomStringConvertible {
    public let package: PairingPackage
    public let confirmationCode: String

    public var description: String { "PairingPreview(redacted)" }
}

/// Pairs this iPhone or iPad with a Mac: preview, confirmation, one preflight read, staged
/// local commit, then activation. Nothing activates before the local commit succeeds.
public actor AcceptPairing {
    private struct Preflight {
        let snapshot: UsageSnapshot?
        let sequence: UInt64?
        let etag: String?
    }

    private let reader: any ReaderStore
    private let secrets: any SecretStore
    private let relay: any RelayGateway
    private let cipher: any EnvelopeCipher
    private let codec: any PairingCodec
    private let clock: any AppClock
    private let afterCommit: AfterCommitPipeline

    public init(
        reader: any ReaderStore, secrets: any SecretStore, relay: any RelayGateway,
        cipher: any EnvelopeCipher, codec: any PairingCodec, clock: any AppClock,
        afterCommit: AfterCommitPipeline
    ) {
        self.reader = reader
        self.secrets = secrets
        self.relay = relay
        self.cipher = cipher
        self.codec = codec
        self.clock = clock
        self.afterCommit = afterCommit
    }

    /// Decodes without writing anything.
    public nonisolated func preview(_ text: String) throws(PairingError) -> PairingPreview {
        do {
            let package = try codec.decode(text, now: clock.now)
            return PairingPreview(
                package: package, confirmationCode: codec.confirmationCode(for: text))
        } catch {
            throw .codec(error)
        }
    }

    public func accept(
        _ preview: PairingPreview, confirmed: Bool,
        profile: ReaderProfileState? = nil
    ) async -> PairingOutcome {
        guard confirmed else { return .failed(.confirmationRequired) }
        await recoverStaging()
        guard let state = try? await reader.load() else { return .failed(.storageFailed) }
        if state.forgetCleanupPending { return .failed(.cleanupPending) }
        if state.pairing != nil { return .failed(.forgetRequired) }
        let package = preview.package
        let preflight: Preflight
        switch await readPreflight(package) {
        case .success(let result): preflight = result
        case .failure(let error): return .failed(error)
        }
        guard await stage(package) else { return .failed(.storageFailed) }
        guard await commit(package, preflight, profile: profile) else {
            await unstage()
            return .failed(.storageFailed)
        }
        return await activate()
    }

    /// Retries activation of a saved pairing, idempotently, even after the displayed deadline.
    public func resumeActivation() async -> PairingOutcome {
        guard let state = try? await reader.load(), state.pairing != nil else {
            return .failed(.nothingToResume)
        }
        return state.awaitingActivation ? await activate() : .paired
    }

    /// Repairs a crash during staging: secrets saved with no committed pairing are removed.
    public func recoverStaging() async {
        guard let state = try? await reader.load(), state.stagingReaderID != nil,
            state.pairing == nil
        else { return }
        await unstage()
    }

    // MARK: steps

    private func readPreflight(_ package: PairingPackage) async -> Result<Preflight, PairingError> {
        let outcome = await relay.getSnapshot(
            endpoint: package.relayEndpoint, readToken: SecretValue(package.readToken), etag: nil)
        switch outcome {
        case .awaitingFirstPublish:
            return .success(Preflight(snapshot: nil, sequence: nil, etag: nil))
        case .snapshot(let data, let etag, _):
            return validated(data, etag: etag, package: package)
        default:
            let context = MappingContext(snapshotValidated: false)
            let status = TransportStatusMapping.status(for: outcome, context: context)
            return .failure(.preflightFailed(status ?? .invalidSnapshot))
        }
    }

    private func validated(
        _ data: Data, etag: String, package: PairingPackage
    ) -> Result<Preflight, PairingError> {
        guard let opened = try? cipher.open(data, key: SecretValue(package.contentKey)),
            opened.header.publisherID == package.publisherID,
            opened.snapshot.publisherID == package.publisherID,
            opened.header.sequence >= package.minimumSequence
        else { return .failure(.preflightFailed(.invalidSnapshot)) }
        return .success(
            Preflight(snapshot: opened.snapshot, sequence: opened.header.sequence, etag: etag))
    }

    /// Marker first, then the two Keychain items; any failure removes what was staged.
    private func stage(_ package: PairingPackage) async -> Bool {
        let readerID = package.readerID
        do {
            try await reader.transact { $0.stagingReaderID = readerID }
            try await secrets.write(.readToken, value: SecretValue(package.readToken))
            try await secrets.write(.contentKey, value: SecretValue(package.contentKey))
            return true
        } catch {
            await unstage()
            return false
        }
    }

    private func unstage() async {
        // Best effort: an orphan is repaired by `recoverStaging` before the next pairing.
        try? await secrets.delete(.readToken)
        try? await secrets.delete(.contentKey)
        try? await reader.transact { $0.stagingReaderID = nil }
    }

    /// One atomic replacement: pairing metadata, the validated preflight snapshot if any, and
    /// `awaitingActivation`. The preflight snapshot is stored but not presented until activation.
    private func commit(
        _ package: PairingPackage, _ preflight: Preflight, profile: ReaderProfileState?
    ) async -> Bool {
        let pairing = ReaderPairing(
            endpoint: package.relayEndpoint, publisherID: package.publisherID,
            readerID: package.readerID, minimumSequence: package.minimumSequence,
            keyVersion: package.keyVersion, registrationExpiresAt: package.registrationExpiresAt)
        let now = clock.now
        do {
            try await reader.transact { state in
                state.pairing = pairing
                state.snapshot = preflight.snapshot
                state.committedSequence = preflight.sequence
                state.etag = preflight.etag
                state.lastCommitAt = preflight.snapshot == nil ? nil : now
                state.transportStatus = .notPaired
                state.awaitingActivation = true
                state.stagingReaderID = nil
                state.lease = nil
                state.lastAttemptAt = nil
                state.lastSuccessAt = nil
                state.lastContactAt = nil
                state.failureCount = 0
                state.backoffUntil = nil
                state.needsAppReconcile = preflight.snapshot != nil
                state.pendingManualRequest = nil
                state.readerProfile = profile
            }
            return true
        } catch {
            return false
        }
    }

    private func activate() async -> PairingOutcome {
        guard let state = try? await reader.load(), let pairing = state.pairing,
            let token = try? await secrets.read(.readToken)
        else { return .failed(.secretsUnavailable) }
        switch await relay.activateReader(endpoint: pairing.endpoint, readToken: token) {
        case .accepted:
            return await finishActivation()
        case .unauthorized:
            await clearPendingPairing()
            return .activationRejected
        default:
            return .awaitingActivation
        }
    }

    private func finishActivation() async -> PairingOutcome {
        let now = clock.now
        let finished: (UsageSnapshot, UInt64)?
        do {
            finished = try await reader.transact { state -> (UsageSnapshot, UInt64)? in
                state.awaitingActivation = false
                state.lastContactAt = now
                state.lastSuccessAt = now
                state.transportStatus = state.snapshot == nil ? .awaitingFirstPublish : .current
                guard let snapshot = state.snapshot, let sequence = state.committedSequence else {
                    return nil
                }
                state.needsAppReconcile = true
                return (snapshot, sequence)
            }
        } catch {
            return .awaitingActivation
        }
        if let (snapshot, sequence) = finished {
            await afterCommit.run(
                CommitEvent(snapshot: snapshot, process: .app, relaySequence: sequence))
        }
        return .paired
    }

    /// An authenticated 401 means the registration expired or was revoked: re-pairing is needed.
    private func clearPendingPairing() async {
        // The secrets go only after the state no longer needs them: a failed write would
        // otherwise leave a pairing with no secrets and no way back but Forget Mac.
        do {
            try await reader.transact { state in
                state.pairing = nil
                state.lease = nil
                state.pendingManualRequest = nil
                state.snapshot = nil
                state.committedSequence = nil
                state.etag = nil
                state.awaitingActivation = false
                state.transportStatus = .notPaired
                state.readerProfile = nil
            }
        } catch {
            return
        }
        try? await secrets.delete(.readToken)
        try? await secrets.delete(.contentKey)
    }
}

public enum ReaderProfileUpdateOutcome: Sendable, Equatable {
    case available
    case waiting
    case failed(RelayOutcome)
    case notPaired
    case invalidName(ReaderProfileNameError)
}

/// Saves the selected reader name first, then independently publishes its opaque profile.
public actor ReportReaderProfile {
    private let reader: any ReaderStore
    private let secrets: any SecretStore
    private let relay: any RelayGateway
    private let cipher: any ReaderProfileCipher

    public init(
        reader: any ReaderStore, secrets: any SecretStore, relay: any RelayGateway,
        cipher: any ReaderProfileCipher
    ) {
        self.reader = reader
        self.secrets = secrets
        self.relay = relay
        self.cipher = cipher
    }

    public func update(
        name input: String, namingMode: ReaderNamingMode, deviceClass: ReaderDeviceClass
    ) async -> ReaderProfileUpdateOutcome {
        let name: ReaderProfileName
        do { name = try ReaderProfileName(validating: input) } catch { return .invalidName(error) }
        let canReport: Bool?
        do {
            canReport = try await reader.transact { state -> Bool? in
                guard state.pairing != nil else { return nil }
                let revision = state.readerProfile?.revision ?? 0
                state.readerProfile = ReaderProfileState(
                    name: name, namingMode: namingMode, deviceClass: deviceClass,
                    revision: revision, delivery: .waiting)
                return !state.awaitingActivation
            }
        } catch { return .waiting }
        guard let canReport else { return .notPaired }
        guard canReport else { return .waiting }
        return await createAndSend()
    }

    /// Uses a previously persisted exact body, including after app relaunch.
    public func retry() async -> ReaderProfileUpdateOutcome {
        guard let state = try? await reader.load(), let pairing = state.pairing,
            let profile = state.readerProfile
        else { return .notPaired }
        guard !state.awaitingActivation else { return .waiting }
        if let pending = profile.pendingEnvelope {
            return await send(pending, pairing: pairing)
        }
        if profile.delivery == .available { return .available }
        return await createAndSend()
    }

    private func createAndSend() async -> ReaderProfileUpdateOutcome {
        guard let state = try? await reader.load(), let pairing = state.pairing,
            let profileState = state.readerProfile
        else { return .notPaired }
        guard !state.awaitingActivation else { return .waiting }
        guard let key = try? await secrets.read(.contentKey) else {
            return await markFailed(.protocolFailure, expected: profileState)
        }
        guard profileState.revision < 9_007_199_254_740_991 else {
            return await markFailed(.protocolFailure, expected: profileState)
        }
        let revision = profileState.revision + 1
        let header = ReaderProfileHeader(
            publisherID: pairing.publisherID, readerID: pairing.readerID,
            keyVersion: pairing.keyVersion, revision: revision)
        let profile = ReaderProfile(
            displayName: profileState.name, deviceClass: profileState.deviceClass)
        guard let body = try? cipher.seal(profile, header: header, key: key) else {
            return await markFailed(.protocolFailure, expected: profileState)
        }
        do {
            let stored = try await reader.transact { state -> Bool in
                guard state.pairing == pairing, !state.awaitingActivation,
                    var current = state.readerProfile,
                    current.revision == profileState.revision,
                    current.name == profileState.name,
                    current.namingMode == profileState.namingMode,
                    current.deviceClass == profileState.deviceClass
                else { return false }
                current.revision = revision
                current.pendingEnvelope = body
                current.delivery = .waiting
                state.readerProfile = current
                return true
            }
            guard stored else { return .waiting }
        } catch { return .waiting }
        return await send(body, pairing: pairing)
    }

    private func send(
        _ body: Data, pairing: ReaderPairing
    ) async -> ReaderProfileUpdateOutcome {
        guard let state = try? await reader.load(), state.pairing == pairing,
            !state.awaitingActivation, state.readerProfile?.pendingEnvelope == body
        else { return .waiting }
        guard let token = try? await secrets.read(.readToken) else {
            return await markFailed(.protocolFailure, envelope: body)
        }
        let outcome = await relay.putReaderProfile(
            body, endpoint: pairing.endpoint, readToken: token)
        if case .accepted = outcome {
            let applied = try? await reader.transact { state -> Bool in
                guard state.pairing == pairing,
                    state.readerProfile?.pendingEnvelope == body
                else { return false }
                state.readerProfile?.pendingEnvelope = nil
                state.readerProfile?.delivery = .available
                return true
            }
            return applied == true ? .available : .waiting
        }
        return await markFailed(outcome, envelope: body)
    }

    private func markFailed(
        _ outcome: RelayOutcome, envelope: Data? = nil, expected: ReaderProfileState? = nil
    ) async -> ReaderProfileUpdateOutcome {
        let applied = try? await reader.transact { state -> Bool in
            if let envelope, state.readerProfile?.pendingEnvelope != envelope { return false }
            if let expected, state.readerProfile != expected { return false }
            state.readerProfile?.delivery = .failed
            return true
        }
        return applied == true ? .failed(outcome) : .waiting
    }
}
