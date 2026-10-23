import Foundation
import ResetRadarDomain

/// The single path by which an iPhone or iPad accepts relay data, whatever the trigger.
public actor IngestRelaySnapshot {
    /// What a fetch concluded, before it is committed under the claim.
    enum Verdict: Sendable {
        case fresh(UsageSnapshot, sequence: UInt64, etag: String)
        case notModified
        case awaitingFirstPublish
        case rejected(TransportStatus, backoff: Bool, clearETag: Bool)
    }

    struct Applied: Sendable {
        let outcome: IngestOutcome
        let statusChanged: Bool
    }

    private let reader: any ReaderStore
    private let secrets: any SecretStore
    private let cipher: any EnvelopeCipher
    private let relay: any RelayGateway
    private let random: any SecretGenerator
    private let clock: any AppClock
    private let diagnostics: any DiagnosticsSink
    private let afterCommit: AfterCommitPipeline
    private let claims: ReaderClaims

    public init(
        reader: any ReaderStore, secrets: any SecretStore, cipher: any EnvelopeCipher,
        relay: any RelayGateway, random: any SecretGenerator, clock: any AppClock,
        diagnostics: any DiagnosticsSink, afterCommit: AfterCommitPipeline
    ) {
        self.reader = reader
        self.secrets = secrets
        self.cipher = cipher
        self.relay = relay
        self.random = random
        self.clock = clock
        self.diagnostics = diagnostics
        self.afterCommit = afterCommit
        self.claims = ReaderClaims(reader: reader, random: random, clock: clock)
    }

    public func run(trigger: FetchTrigger, inAppProcess: Bool) async -> IngestOutcome {
        let claimed: ClaimedFetch
        do {
            switch try await claims.claim(trigger: trigger) {
            case .inProgress: return .inProgress
            case .skipped: return .skipped
            case .claimed(let fetch): claimed = fetch
            }
        } catch {
            return .storageFailed
        }
        let verdict = await fetch(claimed)
        guard let applied = await apply(verdict, to: claimed, inAppProcess: inAppProcess) else {
            return .storageFailed
        }
        await notify(applied, verdict: verdict, inAppProcess: inAppProcess)
        return applied.outcome
    }

    private func notify(_ applied: Applied, verdict: Verdict, inAppProcess: Bool) async {
        guard let state = try? await reader.load(), let snapshot = state.snapshot else { return }
        let event = CommitEvent(snapshot: snapshot, process: inAppProcess ? .app : .widget)
        if applied.outcome == .committed {
            await afterCommit.run(event)
        } else if applied.statusChanged && inAppProcess {
            await afterCommit.statusChanged(event)
        }
    }

    // MARK: fetch

    private func fetch(_ claimed: ClaimedFetch) async -> Verdict {
        let keys: (read: SecretValue, content: SecretValue)
        do {
            keys = (try await secrets.read(.readToken), try await secrets.read(.contentKey))
        } catch {
            await diagnostics.record(.secretsUnavailable(at: clock.now))
            return .rejected(.secretsUnavailable, backoff: false, clearETag: false)
        }
        var etag = claimed.hasValidatedSnapshot ? claimed.etag : nil
        var unexpectedNotModified = 0
        while true {
            let outcome = await relay.getSnapshot(
                endpoint: claimed.pairing.endpoint, readToken: keys.read, etag: etag)
            guard case .notModified = outcome else {
                return await judge(outcome, pairing: claimed.pairing, key: keys.content)
            }
            if etag != nil { return .notModified }
            // A 304 with no validated cache behind it: drop the ETag and read once unconditionally.
            unexpectedNotModified += 1
            if unexpectedNotModified > 1 {
                return .rejected(.invalidSnapshot, backoff: true, clearETag: true)
            }
            etag = nil
        }
    }

    private func judge(
        _ outcome: RelayOutcome, pairing: ReaderPairing, key: SecretValue
    ) async -> Verdict {
        switch outcome {
        case .snapshot(let data, let etag, _):
            return await open(data, etag: etag, pairing: pairing, key: key)
        case .awaitingFirstPublish:
            return .awaitingFirstPublish
        case .unauthorized, .unsupportedVersion, .payloadTooLarge:
            return .rejected(terminalStatus(outcome), backoff: false, clearETag: false)
        default:
            let context = MappingContext(snapshotValidated: false)
            let status = TransportStatusMapping.status(for: outcome, context: context)
            await diagnostics.record(
                .relayFailure(
                    status: status ?? .invalidSnapshot, httpStatusClass: nil, at: clock.now))
            return .rejected(status ?? .invalidSnapshot, backoff: true, clearETag: false)
        }
    }

    private func terminalStatus(_ outcome: RelayOutcome) -> TransportStatus {
        TransportStatusMapping.status(
            for: outcome, context: MappingContext(snapshotValidated: false))
            ?? .invalidSnapshot
    }

    /// Opens and validates an envelope; a failure keeps the committed snapshot and retains no ETag.
    private func open(
        _ data: Data, etag: String, pairing: ReaderPairing, key: SecretValue
    ) async -> Verdict {
        let opened: (header: EnvelopeHeader, snapshot: UsageSnapshot)
        do {
            opened = try cipher.open(data, key: key)
        } catch {
            let incompatible = error == .unsupportedVersion
            return .rejected(
                incompatible ? .incompatible : .invalidSnapshot, backoff: !incompatible,
                clearETag: false)
        }
        let header = opened.header
        let valid =
            header.publisherID == pairing.publisherID
            && opened.snapshot.publisherID == header.publisherID
            && header.sequence >= pairing.minimumSequence
        guard valid else {
            await diagnostics.record(
                .relayFailure(status: .invalidSnapshot, httpStatusClass: nil, at: clock.now))
            return .rejected(.invalidSnapshot, backoff: true, clearETag: false)
        }
        return .fresh(opened.snapshot, sequence: header.sequence, etag: etag)
    }

    // MARK: commit

    private func apply(
        _ verdict: Verdict, to claimed: ClaimedFetch, inAppProcess: Bool
    ) async -> Applied? {
        let now = clock.now
        let claimID = claimed.claim.id
        var unit = 0.0
        if case .rejected(_, true, _) = verdict { unit = random.randomUnit() }
        let jitter = unit
        return try? await reader.transact { state in
            guard state.lease?.id == claimID else {
                return Applied(outcome: .skipped, statusChanged: false)
            }
            state.lease = nil
            let before = state.transportStatus
            let outcome = Self.record(
                verdict, in: &state, now: now, jitter: jitter, inAppProcess: inAppProcess)
            return Applied(outcome: outcome, statusChanged: state.transportStatus != before)
        }
    }

    private static func record(
        _ verdict: Verdict, in state: inout ReaderState, now: Date, jitter: Double,
        inAppProcess: Bool
    ) -> IngestOutcome {
        switch verdict {
        case .fresh(let snapshot, let sequence, let etag):
            markSuccess(&state, now: now, status: .current)
            if let committed = state.committedSequence, sequence <= committed {
                // The relay still serves the committed snapshot: keep its ETag so the next
                // fetch is conditional instead of a full read.
                if sequence == committed { state.etag = etag }
                return .unchanged
            }
            state.snapshot = snapshot
            state.committedSequence = sequence
            state.etag = etag
            state.lastCommitAt = now
            if !inAppProcess { state.needsAppReconcile = true }
            return .committed
        case .notModified:
            markSuccess(&state, now: now, status: .current)
            return .unchanged
        case .awaitingFirstPublish:
            markSuccess(&state, now: now, status: .awaitingFirstPublish)
            return .failed(.awaitingFirstPublish)
        case .rejected(let status, let backoff, let clearETag):
            state.transportStatus = status
            if clearETag { state.etag = nil }
            if backoff {
                state.failureCount += 1
                let delay = BackoffPolicy.delay(
                    afterFailures: state.failureCount, randomUnit: jitter)
                state.backoffUntil = now.addingTimeInterval(delay)
            }
            return .failed(status)
        }
    }

    private static func markSuccess(
        _ state: inout ReaderState, now: Date, status: TransportStatus
    ) {
        state.lastContactAt = now
        state.lastSuccessAt = now
        state.transportStatus = status
        state.failureCount = 0
        state.backoffUntil = nil
    }
}
