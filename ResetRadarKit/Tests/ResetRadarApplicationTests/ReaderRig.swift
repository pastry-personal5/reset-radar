import Foundation
import ResetRadarDomain
import ResetRadarTestSupport

@testable import ResetRadarApplication

/// Records the order in which after-commit stages run.
final class RecordingStep: AfterCommitStep, @unchecked Sendable {
    let name: String
    let log: FakeEventLog

    init(_ name: String, log: FakeEventLog) {
        self.name = name
        self.log = log
    }

    func afterCommitOutcome(_ event: CommitEvent) async -> AfterCommitOutcome {
        log.append(name)
        return .complete
    }
}

let readerContentKey = SecretValue(bytes(32, 0x44))
let readerReadToken = SecretValue(bytes(32, 0x55))

/// A paired iPhone: reader store, secrets, relay, and the after-commit pipeline.
final class ReaderRig: @unchecked Sendable {
    let clock = FakeAppClock(start: epoch)
    let store = FakeReaderStore(installationID: installation)
    let secrets = FakeSecretStore()
    let cipher = FakeEnvelopeCipher()
    let relay = FakeRelayGateway()
    let random = FakeSecretGenerator()
    let sink = FakeDiagnosticsSink()
    let reloader = FakeSurfaceReloader()
    let log = FakeEventLog()

    init(paired: Bool = true, floor: UInt64 = 3, seedSecrets: Bool = true) {
        if seedSecrets {
            secrets.seed(.readToken, readerReadToken)
            secrets.seed(.contentKey, readerContentKey)
        }
        if paired {
            store.seed { state in
                state.pairing = ReaderPairing(
                    endpoint: endpoint, publisherID: publisher, readerID: readerA,
                    minimumSequence: floor, keyVersion: 1, registrationExpiresAt: epoch)
                state.transportStatus = .awaitingFirstPublish
            }
        }
    }

    func pipeline(watch: Bool = true) -> AfterCommitPipeline {
        AfterCommitPipeline(
            reader: store, reloader: reloader,
            notifications: RecordingStep("notifications", log: log),
            liveActivities: RecordingStep("liveActivities", log: log),
            watch: watch ? RecordingStep("watch", log: log) : nil)
    }

    func makeIngest(watch: Bool = true) -> IngestRelaySnapshot {
        IngestRelaySnapshot(
            reader: store, secrets: secrets, cipher: cipher, relay: relay, random: random,
            clock: clock, diagnostics: sink, afterCommit: pipeline(watch: watch))
    }

    func claims() -> ReaderClaims {
        ReaderClaims(reader: store, random: random, clock: clock)
    }

    /// A relay response carrying a sealed snapshot at `sequence`.
    func envelope(
        sequence: UInt64, publisherID: PublisherID = publisher,
        snapshotPublisher: PublisherID? = nil, etag: String? = nil,
        windows: [AllowanceWindow]? = nil, results: [ManualRefreshResult] = []
    ) -> RelayOutcome {
        let header = EnvelopeHeader(
            protocolVersion: 1, envelopeVersion: 1, publisherID: publisherID, sequence: sequence,
            keyVersion: 1)
        let body = snapshot(
            windows: windows ?? [window(percent: Double(sequence))], generatedAt: clock.now,
            results: results, publisherID: snapshotPublisher ?? publisherID)
        // swiftlint:disable:next force_try
        let sealed = try! cipher.seal(body, header: header, key: readerContentKey)
        return .snapshot(sealed.encoded, etag: etag ?? "\"e\(sequence)\"", sequence: sequence)
    }
}
