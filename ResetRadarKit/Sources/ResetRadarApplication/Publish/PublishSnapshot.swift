import Foundation
import ResetRadarDomain

/// Seals and sends the collected snapshot to the relay. Persists the sequence before sending,
/// stops automatic retry on rejection, and backs off on transient failure.
public actor PublishSnapshot {
    public static let maximumEnvelopeBytes = 65_536

    private struct Secrets {
        let contentKey: SecretValue
        let writeToken: SecretValue
    }

    private struct Target {
        let endpoint: URL
        let publisherID: PublisherID
    }

    private let publisher: any PublisherStore
    private let secretStore: any SecretStore
    private let cipher: any EnvelopeCipher
    private let relay: any RelayGateway
    private let diagnostics: any DiagnosticsSink
    private let clock: any AppClock
    private let random: any SecretGenerator

    private var secrets: Secrets?
    private var lastPublishedAt: Date?
    private var backoffUntil: Date?
    private var failureCount = 0
    private var stop: StopReason?
    private var oversizedShape: Set<WindowID>?

    public init(
        publisher: any PublisherStore, secrets: any SecretStore, cipher: any EnvelopeCipher,
        relay: any RelayGateway, diagnostics: any DiagnosticsSink, clock: any AppClock,
        random: any SecretGenerator
    ) {
        self.publisher = publisher
        self.secretStore = secrets
        self.cipher = cipher
        self.relay = relay
        self.diagnostics = diagnostics
        self.clock = clock
        self.random = random
    }

    /// Clears every stop, backoff, and cached secret, after relay setup succeeded.
    public func resume() {
        secrets = nil
        stop = nil
        oversizedShape = nil
        backoffUntil = nil
        failureCount = 0
    }

    /// Drops the cached secrets so the next send re-reads superseded keys and tokens.
    public func invalidateSecrets() async {
        secrets = nil
        await secretStore.invalidateCache()
    }

    public func publish(
        _ snapshot: UsageSnapshot, change: ChangeClass, trigger: PublishTrigger
    ) async -> PublishOutcome {
        guard let target = await activeTarget(requiring: .active) else { return .paused }
        let shape = Set(snapshot.windows.map(\.id))
        if let stop { return .stopped(stop) }
        if let oversizedShape, oversizedShape == shape { return .envelopeTooLarge }
        let state = PublicationState(lastPublishedAt: lastPublishedAt, backoffUntil: backoffUntil)
        let decision = PublicationPolicy.decide(
            change: change, trigger: trigger, state: state, now: clock.now)
        if case .wait(let until) = decision {
            return until == backoffUntil ? .backoff(until: until) : .notDue(next: until)
        }
        return await send(snapshot, to: target)
    }

    /// The first publication of relay setup: it binds the new publisher on the empty relay and
    /// ignores the publication policy. Only valid while setup is pending.
    public func bind(_ snapshot: UsageSnapshot) async -> PublishOutcome {
        guard let target = await activeTarget(requiring: .setupPending) else { return .paused }
        return await send(snapshot, to: target)
    }

    private func activeTarget(requiring lifecycle: RelayLifecycle) async -> Target? {
        guard let state = try? await publisher.load(), state.lifecycle == lifecycle,
            let endpoint = state.endpoint, let publisherID = state.publisherID
        else { return nil }
        return Target(endpoint: endpoint, publisherID: publisherID)
    }

    private func send(_ snapshot: UsageSnapshot, to target: Target) async -> PublishOutcome {
        guard let keys = await readSecrets() else {
            await diagnostics.record(.secretsUnavailable(at: clock.now))
            return .secretsUnavailable
        }
        guard let sequence = try? await publisher.nextSequence() else { return .paused }
        let header = EnvelopeHeader(
            protocolVersion: 1, envelopeVersion: 1, publisherID: target.publisherID,
            sequence: sequence, keyVersion: 1)
        guard let sealed = try? cipher.seal(snapshot, header: header, key: keys.contentKey) else {
            return await halt(.incompatible, status: nil, sequence: sequence)
        }
        guard sealed.encoded.count <= Self.maximumEnvelopeBytes else {
            oversizedShape = Set(snapshot.windows.map(\.id))
            await diagnostics.record(.envelopeTooLarge(sequence: sequence, at: clock.now))
            return .envelopeTooLarge
        }
        let outcome = await relay.putSnapshot(
            sealed.encoded, endpoint: target.endpoint, writeToken: keys.writeToken)
        return await finish(outcome, sequence: sequence)
    }

    private func readSecrets() async -> Secrets? {
        if let secrets { return secrets }
        do {
            let loaded = Secrets(
                contentKey: try await secretStore.read(.contentKey),
                writeToken: try await secretStore.read(.writeToken))
            secrets = loaded
            return loaded
        } catch {
            return nil
        }
    }

    private func finish(_ outcome: RelayOutcome, sequence: UInt64) async -> PublishOutcome {
        switch outcome {
        case .accepted:
            // A failed floor update is safe: a lower pairing floor only accepts more.
            try? await publisher.transact { $0.lastPublishedSequence = sequence }
            lastPublishedAt = clock.now
            backoffUntil = nil
            failureCount = 0
            return .published(sequence: sequence)
        case .badRequest: return await halt(.payloadRejected, status: 4, sequence: sequence)
        case .unauthorized: return await halt(.authorizationRequired, status: 4, sequence: sequence)
        case .publisherConflict: return await halt(.snapshotConflict, status: 4, sequence: sequence)
        case .payloadTooLarge: return await halt(.payloadRejected, status: 4, sequence: sequence)
        case .unsupportedVersion: return await halt(.incompatible, status: 4, sequence: sequence)
        default: return await backOff(after: outcome)
        }
    }

    private func halt(
        _ reason: StopReason, status: Int?, sequence: UInt64
    ) async -> PublishOutcome {
        stop = reason
        await diagnostics.record(
            .publicationStopped(httpStatusClass: status, lastSequence: sequence, at: clock.now))
        return .stopped(reason)
    }

    private func backOff(after outcome: RelayOutcome) async -> PublishOutcome {
        failureCount += 1
        let delay = BackoffPolicy.delay(
            afterFailures: failureCount, randomUnit: random.randomUnit())
        let until = clock.now.addingTimeInterval(delay)
        backoffUntil = until
        let status =
            TransportStatusMapping.status(
                for: outcome, context: MappingContext(snapshotValidated: false)) ?? .offline
        await diagnostics.record(
            .relayFailure(
                status: status, httpStatusClass: outcome == .quotaLimited ? 4 : nil, at: clock.now))
        return .backoff(until: until)
    }
}
