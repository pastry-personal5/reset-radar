import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarStorage
import ResetRadarTestSupport
import UIKit

@testable import ResetRadar

let epoch = Date(timeIntervalSinceReferenceDate: 800_000_000)

func identifier<T: ByteIdentifier>(_ type: T.Type, _ value: UInt8) -> T {
    guard let id = T(data: Data(repeating: value, count: T.byteCount)) else {
        preconditionFailure("invalid fixture identifier")
    }
    return id
}

let publisherA: PublisherID = identifier(PublisherID.self, 0x01)
let publisherB: PublisherID = identifier(PublisherID.self, 0x02)
let readerA: ReaderID = identifier(ReaderID.self, 0x0A)
let codexA: AccountID = identifier(AccountID.self, 0xC1)
let codexB: AccountID = identifier(AccountID.self, 0xC3)
let claude: AccountID = identifier(AccountID.self, 0xC2)
let relayEndpoint = URL(string: "https://reader-tests.workers.dev")!
let readToken = SecretValue(Data(repeating: 0x55, count: 32))
let contentKey = SecretValue(Data(repeating: 0x44, count: 32))

final class MemorySelectionStore: AccountSelectionStore, @unchecked Sendable {
    private let stored = Locked<AccountID?>(nil)
    var value: AccountID? { stored.snapshot }

    func load() -> AccountID? { stored.snapshot }
    func save(_ accountID: AccountID?) { stored.withLock { $0 = accountID } }
}

struct FixedSystemStatus: ReaderSystemStatus {
    var liveActivities: Bool? = true

    func liveActivitiesEnabled() async -> Bool? { liveActivities }
}

/// One reader process over a real `FileReaderStore` in a temporary App Group stand-in, with
/// scripted relay, secrets, and clock. Two harnesses may share a root to act as two processes.
@MainActor
final class ReaderHarness {
    let root: URL
    let store: FileReaderStore
    let secrets = FakeSecretStore()
    let relay = FakeRelayGateway()
    let cipher = FakeEnvelopeCipher()
    let codec = FakePairingCodec()
    let random = FakeSecretGenerator()
    let watchLink = FakeWatchLink()
    let clock: FakeAppClock
    let selection = MemorySelectionStore()

    init(sharing other: ReaderHarness? = nil) {
        root =
            other?.root
            ?? FileManager.default.temporaryDirectory.appending(
                path: "ReaderTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        store = FileReaderStore(locations: StorageLocations(root: root, flavor: .debug))
        clock = other?.clock ?? FakeAppClock(start: epoch)
    }

    func environment(watch: Bool = true) -> ReaderEnvironment {
        ReaderEnvironment(
            dependencies: ReaderDependencies(
                reader: store, snapshots: ReaderSnapshotStore(store: store), secrets: secrets,
                relay: relay, cipher: cipher, codec: codec, random: random, clock: clock,
                diagnostics: FakeDiagnosticsSink(), system: FixedSystemStatus(),
                selection: selection, preferences: FakePreferenceStore(),
                notificationGate: FakeNotificationReconcileGate(clock: clock), hasWatchStage: watch,
                watchLink: watchLink)
        )
    }

    var state: ReaderState {
        get async throws { try await store.load() }
    }

    /// An encoded package for this harness's relay, valid for five minutes.
    func package(publisher: PublisherID = publisherA) throws -> String {
        try codec.encode(
            PairingPackage(
                relayEndpoint: relayEndpoint, readerID: readerA, readToken: readToken.reveal(),
                contentKey: contentKey.reveal(), publisherID: publisher, keyVersion: 1,
                minimumSequence: 1, registrationExpiresAt: clock.now.addingTimeInterval(300)))
    }

    /// An activated pairing with its secrets and, optionally, a committed snapshot.
    func seedPaired(committed sequence: UInt64? = 5, hasSentToWatch: Bool = false) async throws {
        secrets.seed(.readToken, readToken)
        secrets.seed(.contentKey, contentKey)
        let snapshot = sequence.map { _ in Self.snapshot(at: clock.now) }
        let now = clock.now
        try await store.transact { state in
            state.pairing = ReaderPairing(
                endpoint: relayEndpoint, publisherID: publisherA, readerID: readerA,
                minimumSequence: 1, keyVersion: 1, registrationExpiresAt: now)
            state.snapshot = snapshot
            state.committedSequence = sequence
            state.etag = sequence.map { "\"s\($0)\"" }
            state.transportStatus = sequence == nil ? .awaitingFirstPublish : .current
            state.lastSuccessAt = sequence == nil ? nil : now
            state.lastCommitAt = sequence == nil ? nil : now
            state.hasSentToWatch = hasSentToWatch
        }
    }

    func envelope(
        sequence: UInt64, publisher: PublisherID = publisherA, key: SecretValue = contentKey,
        results: [ManualRefreshResult] = [], percent: Double = 42
    ) throws -> RelayOutcome {
        let sealed = try cipher.seal(
            Self.snapshot(at: clock.now, results: results, publisher: publisher, percent: percent),
            header: EnvelopeHeader(
                protocolVersion: 1, envelopeVersion: 1, publisherID: publisher, sequence: sequence,
                keyVersion: 1),
            key: key)
        return .snapshot(sealed.encoded, etag: "\"s\(sequence)\"", sequence: sequence)
    }

    func result(
        _ requestID: RequestID, target: ManualRefreshTarget,
        _ outcomes: [(AccountID, ManualRefreshAccountResult.Outcome)]
    ) throws -> ManualRefreshResult {
        try ManualRefreshResult(
            readerID: readerA, requestID: requestID, completedAt: clock.now, target: target,
            accountResults: outcomes.map {
                ManualRefreshAccountResult(accountID: $0.0, outcome: $0.1)
            })
    }

    /// The request ID and target of the `index`th posted refresh request.
    func posted(_ index: Int = 0) -> (RequestID, ManualRefreshTarget)? {
        let posts = relay.calls(.postRefreshRequest)
        guard posts.indices.contains(index),
            case .postRefreshRequest(let id, let target) = posts[index]
        else { return nil }
        return (id, target)
    }

    /// Two Codex accounts and one Claude Code account, each with both standard windows.
    static func snapshot(
        at now: Date, results: [ManualRefreshResult] = [], publisher: PublisherID = publisherA,
        percent: Double = 42, accounts: [AccountID] = [codexA, codexB, claude]
    ) -> UsageSnapshot {
        let metadata: [AccountMetadata] = accounts.enumerated().map { index, id in
            AccountMetadata(
                id: id, product: id == claude ? .claudeCode : .codex, number: index + 1)
        }
        let windows = metadata.flatMap { account in
            AccountWindow.StandardWindow.allCases.map { standard in
                window(account, standard, now: now, percent: percent)
            }
        }
        do {
            return try UsageSnapshot(
                publisherID: publisher, generatedAt: now, heartbeatSeconds: 300,
                accounts: metadata,
                sources: metadata.map {
                    AccountSource(
                        accountID: $0.id, product: $0.product,
                        kind: $0.product == .codex ? .codexAppServer : .claudeCodeStatusLine,
                        version: "test", state: .reporting)
                },
                windows: windows, manualRefreshResults: results)
        } catch {
            preconditionFailure("invalid fixture snapshot: \(error)")
        }
    }

    private static func window(
        _ account: AccountMetadata, _ standard: AccountWindow.StandardWindow, now: Date,
        percent: Double
    ) -> AllowanceWindow {
        do {
            return try AllowanceWindow(
                validating: RawWindow(
                    accountID: account.id.hex, product: account.product.rawValue,
                    limitID: standard.rawValue, durationMinutes: standard.durationMinutes,
                    isDefaultLimit: true, reportState: .reported,
                    resetsAt: now.addingTimeInterval(7_200),
                    observation: RawObservation(
                        usedPercent: percent, observedAt: now, sourceVersion: "test",
                        fractionDigits: 0)))
        } catch {
            preconditionFailure("invalid fixture window: \(error)")
        }
    }
}

/// Advances the fake clock whenever the code under test is sleeping, until `finished`.
@MainActor
func drive(_ clock: FakeAppClock, step: TimeInterval = 5, until finished: () -> Bool) async {
    for _ in 0..<20_000 where !finished() {
        if clock.sleeperCount > 0 {
            clock.advance(by: step)
        }
        try? await Task.sleep(for: .milliseconds(1))
    }
}
