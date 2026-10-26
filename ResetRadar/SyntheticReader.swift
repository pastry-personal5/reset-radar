#if DEBUG
    import Foundation
    import ResetRadarApplication
    import ResetRadarDomain
    import ResetRadarStorage
    import ResetRadarTransport
    import UIKit

    /// Development-only reader states for UI tests and previews. Each launch uses a fresh
    /// temporary store, in-memory secrets, and an in-process relay that seals synthetic
    /// snapshots with the real envelope cipher, so the real ingest path runs and nothing leaves
    /// the device.
    enum SyntheticReaderScenario: String, CaseIterable {
        case notPaired
        case confirmingPairing
        case waitingForMacData
        case paired
        case syncProblem
        case cleanupPending

        static let keepSelectionArgument = "-ResetRadarKeepSelection"

        @MainActor
        func dependencies(keepSelection: Bool) throws -> ReaderDependencies {
            let root = FileManager.default.temporaryDirectory.appending(
                path: "ResetRadarSynthetic/\(UUID().uuidString)", directoryHint: .isDirectory)
            let locations = StorageLocations(root: root, flavor: .debug)
            let store = FileReaderStore(locations: locations)
            let now = Date()
            let relay = SyntheticRelay(scenario: self, start: now)
            try seed(store, relay: relay, now: now)
            let selection = UserDefaultsSelectionStore(
                defaults: UserDefaults(suiteName: "ResetRadarSynthetic") ?? .standard)
            if !keepSelection { selection.save(nil) }
            return ReaderDependencies(
                reader: store, snapshots: ReaderSnapshotStore(store: store),
                // Failing deletes keep the interrupted Forget Mac cleanup retryable.
                secrets: SyntheticSecretStore(
                    seeded: self == .notPaired ? [:] : SyntheticRelay.secrets,
                    failsDeletes: self == .cleanupPending),
                relay: relay, cipher: AESGCMEnvelopeCipher(), codec: JSONPairingCodec(),
                random: CryptoSecretGenerator(), clock: SystemReaderClock(),
                diagnostics: LogDiagnosticsSink(locations: locations),
                system: LiveReaderSystemStatus(), selection: selection,
                preferences: DefaultsPreferenceStore(
                    defaults: UserDefaults(suiteName: "ResetRadarSynthetic.preferences")
                        ?? .standard),
                notificationGate: FileNotificationReconcileGate(
                    locations: locations, clock: SystemReaderClock()),
                hasWatchStage: UIDevice.current.userInterfaceIdiom == .phone)
        }

        private func seed(_ store: FileReaderStore, relay: SyntheticRelay, now: Date) throws {
            let snapshot = try SyntheticRelay.snapshot(at: now, results: [])
            let scenario = self
            try runBlocking {
                try await store.transact { state in
                    guard scenario != .notPaired else { return }
                    state.pairing = SyntheticRelay.pairing
                    switch scenario {
                    case .notPaired:
                        break
                    case .confirmingPairing:
                        state.awaitingActivation = true
                    case .waitingForMacData:
                        state.transportStatus = .awaitingFirstPublish
                        state.lastSuccessAt = now
                    case .paired, .syncProblem:
                        state.snapshot = snapshot
                        state.committedSequence = SyntheticRelay.firstSequence
                        state.etag = SyntheticRelay.etag(SyntheticRelay.firstSequence)
                        state.transportStatus = .current
                        state.lastSuccessAt = now
                        state.lastCommitAt = now
                    case .cleanupPending:
                        state.pairing = nil
                        state.forgetCleanupPending = true
                        let clear = try? WatchPayload(
                            installationID: state.installationID, deliveryRevision: 1,
                            snapshot: nil, relaySequence: nil, transportStatus: .notPaired,
                            lastRelayContactAt: nil, lastCommitAt: nil, cleared: true)
                        state.watchErasePending = clear.map(WatchErasure.init(clear:))
                    }
                }
            }
        }
    }

    /// Seeding happens before the first scene appears, so it waits for its single write.
    private func runBlocking(_ body: @escaping @Sendable () async throws -> Void) throws {
        let semaphore = DispatchSemaphore(value: 0)
        let failure = SyntheticFailureBox()
        Task.detached {
            do { try await body() } catch { failure.set(error) }
            semaphore.signal()
        }
        semaphore.wait()
        if let error = failure.error { throw error }
    }

    private final class SyntheticFailureBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: (any Error)?
        var error: (any Error)? { lock.withLock { stored } }
        func set(_ error: any Error) { lock.withLock { stored = error } }
    }

    actor SyntheticSecretStore: SecretStore {
        private var values: [SecretName: SecretValue]
        private let failsDeletes: Bool

        init(seeded: [SecretName: SecretValue], failsDeletes: Bool = false) {
            values = seeded
            self.failsDeletes = failsDeletes
        }

        func read(_ name: SecretName) throws(SecretStoreError) -> SecretValue {
            guard let value = values[name] else { throw .notFound }
            return value
        }

        func write(_ name: SecretName, value: SecretValue) throws(SecretStoreError) {
            values[name] = value
        }

        func delete(_ name: SecretName) throws(SecretStoreError) {
            if failsDeletes { throw .interactionRequired }
            values[name] = nil
        }

        func invalidateCache() {}
    }

    /// The approved reader operations over synthetic data. A posted Codex request is answered
    /// by the next publication, as a responsive Collector Mac would.
    actor SyntheticRelay: RelayGateway {
        static let firstSequence: UInt64 = 10
        static let endpoint = URL(string: "https://synthetic.workers.dev")!
        static let publisherID = PublisherID(data: Data(repeating: 0x5A, count: 32))!
        static let readerID = ReaderID(data: Data(repeating: 0x5B, count: 16))!
        static let contentKey = SecretValue(Data(repeating: 0x5C, count: 32))
        static let readToken = SecretValue(Data(repeating: 0x5D, count: 32))
        static let secrets: [SecretName: SecretValue] = [
            .readToken: readToken, .contentKey: contentKey,
        ]
        static let work = AccountID(data: Data(repeating: 0xA1, count: 16))!
        static let second = AccountID(data: Data(repeating: 0xA2, count: 16))!
        static let personal = AccountID(data: Data(repeating: 0xA3, count: 16))!

        static var pairing: ReaderPairing {
            ReaderPairing(
                endpoint: endpoint, publisherID: publisherID, readerID: readerID,
                minimumSequence: 1, keyVersion: 1,
                registrationExpiresAt: Date().addingTimeInterval(600))
        }

        static func etag(_ sequence: UInt64) -> String { "\"synthetic-\(sequence)\"" }

        private let scenario: SyntheticReaderScenario
        private var sequence = firstSequence
        private var results: [ManualRefreshResult] = []
        private var answer: (RequestID, ManualRefreshTarget)?

        init(scenario: SyntheticReaderScenario, start: Date) {
            self.scenario = scenario
        }

        func getSnapshot(endpoint: URL, readToken: SecretValue, etag: String?) -> RelayOutcome {
            switch scenario {
            case .notPaired, .confirmingPairing, .cleanupPending: return .unauthorized
            case .waitingForMacData: return .awaitingFirstPublish
            case .syncProblem: return .offline
            case .paired: break
            }
            if let pending = answer {
                answer = nil
                sequence += 1
                results = (try? Self.answer(pending.0, target: pending.1)).map { [$0] } ?? []
            }
            if etag == Self.etag(sequence) { return .notModified }
            do {
                let sealed = try AESGCMEnvelopeCipher().seal(
                    Self.snapshot(at: Date(), results: results),
                    header: EnvelopeHeader(
                        protocolVersion: 1, envelopeVersion: 1, publisherID: Self.publisherID,
                        sequence: sequence, keyVersion: 1),
                    key: Self.contentKey)
                return .snapshot(sealed.encoded, etag: Self.etag(sequence), sequence: sequence)
            } catch {
                return .protocolFailure
            }
        }

        func activateReader(endpoint: URL, readToken: SecretValue) -> RelayOutcome {
            scenario == .confirmingPairing ? .offline : .accepted(sequence: nil)
        }

        func postRefreshRequest(
            _ id: RequestID, target: ManualRefreshTarget, endpoint: URL, readToken: SecretValue
        ) -> RelayOutcome {
            answer = (id, target)
            return .refreshAccepted(expiresAt: Date().addingTimeInterval(60))
        }

        func putSnapshot(_ envelope: Data, endpoint: URL, writeToken: SecretValue) -> RelayOutcome {
            .badRequest
        }

        func listRefreshRequests(
            endpoint: URL, writeToken: SecretValue
        ) -> RelayResponse<[PendingRefreshRequest]> {
            .outcome(.badRequest)
        }

        func deleteRefreshRequest(
            _ id: RequestID, endpoint: URL, writeToken: SecretValue
        ) -> RelayOutcome {
            .badRequest
        }

        func registerReader(
            _ id: ReaderID, digest: Data, endpoint: URL, adminToken: SecretValue
        ) -> RelayResponse<Date> {
            .outcome(.badRequest)
        }

        func listReaders(endpoint: URL, adminToken: SecretValue) -> RelayResponse<[RelayReader]> {
            .outcome(.badRequest)
        }

        func revokeReader(_ id: ReaderID, endpoint: URL, adminToken: SecretValue) -> RelayOutcome {
            .badRequest
        }

        func destroyRelay(endpoint: URL, adminToken: SecretValue) -> RelayOutcome {
            .badRequest
        }

        private static func answer(
            _ requestID: RequestID, target: ManualRefreshTarget
        ) throws -> ManualRefreshResult {
            let accounts: [AccountID] =
                switch target {
                case .allCodex: [work, second]
                case .account(let id): [id]
                }
            return try ManualRefreshResult(
                readerID: readerID, requestID: requestID, completedAt: Date(), target: target,
                accountResults: accounts.map {
                    ManualRefreshAccountResult(
                        accountID: $0, outcome: $0 == second ? .sourceUnavailable : .codexRead)
                })
        }

        /// “Work” has both standard windows and one additional window; `Account #2` has no
        /// five-hour reading; “personal” is Claude Code with a passed weekly reset.
        static func snapshot(at now: Date, results: [ManualRefreshResult]) throws -> UsageSnapshot {
            func source(_ account: AccountID, _ product: ProductID) -> AccountSource {
                AccountSource(
                    accountID: account, product: product,
                    kind: product == .codex ? .codexAppServer : .claudeCodeStatusLine,
                    version: "synthetic", state: .reporting)
            }
            return try UsageSnapshot(
                publisherID: publisherID, generatedAt: now, heartbeatSeconds: 300,
                accounts: [
                    AccountMetadata(
                        id: work, product: .codex, number: 1,
                        alias: try AccountAlias(validating: "Work")),
                    AccountMetadata(id: second, product: .codex, number: 2),
                    AccountMetadata(
                        id: personal, product: .claudeCode, number: 3,
                        alias: try AccountAlias(validating: "personal")),
                ],
                sources: [
                    source(work, .codex), source(second, .codex), source(personal, .claudeCode),
                ],
                windows: try windows(at: now), manualRefreshResults: results)
        }

        private static func windows(at now: Date) throws -> [AllowanceWindow] {
            let observed = now.addingTimeInterval(-60)
            func window(
                _ account: AccountID, _ limit: String, label: String? = nil, minutes: Int,
                percent: Double, resetsIn: TimeInterval
            ) throws -> AllowanceWindow {
                let product: ProductID = account == personal ? .claudeCode : .codex
                return try AllowanceWindow(
                    validating: RawWindow(
                        accountID: account.hex, product: product.rawValue, limitID: limit,
                        label: label, durationMinutes: minutes, isDefaultLimit: label == nil,
                        reportState: .reported, resetsAt: now.addingTimeInterval(resetsIn),
                        observation: RawObservation(
                            usedPercent: percent, observedAt: observed,
                            sourceVersion: "synthetic",
                            fractionDigits: product == .codex ? 0 : 1)))
            }
            return [
                try window(work, "primary", minutes: 300, percent: 42, resetsIn: 7_200),
                try window(work, "secondary", minutes: 10_080, percent: 7, resetsIn: 400_000),
                try window(
                    work, "review", label: "Code review", minutes: 10_080, percent: 12,
                    resetsIn: 300_000),
                try window(second, "secondary", minutes: 10_080, percent: 63, resetsIn: 200_000),
                try window(personal, "five_hour", minutes: 300, percent: 33.5, resetsIn: 5_000),
                try window(personal, "seven_day", minutes: 10_080, percent: 80, resetsIn: -30),
            ]
        }
    }
#endif
