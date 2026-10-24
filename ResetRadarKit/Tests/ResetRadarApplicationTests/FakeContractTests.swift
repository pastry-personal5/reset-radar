import Foundation
import ResetRadarDomain
import Testing

@testable import ResetRadarApplication
@testable import ResetRadarTestSupport

private let readerInstallation = InstallationID(data: Data(repeating: 0x0C, count: 16))!
private let publisherID = PublisherID(data: Data(repeating: 0x01, count: 32))!
private let readerID = ReaderID(data: Data(repeating: 0x0A, count: 16))!
private let origin = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func emptySnapshot() throws -> UsageSnapshot {
    try UsageSnapshot(
        publisherID: publisherID, generatedAt: origin, heartbeatSeconds: 300, accounts: [],
        sources: [], windows: [])
}

@Suite struct ClockContractTests {
    @Test func sleepResumesAtTheAdvancedInstant() async throws {
        let clock = FakeAppClock(start: origin)
        let woke = Locked(false)
        let task = Task {
            try await clock.sleep(for: .seconds(45))
            woke.withLock { $0 = true }
        }
        await clock.waitForSleepers()
        clock.advance(by: 44.999)
        try await Task.sleep(for: .milliseconds(20))
        #expect(!woke.snapshot)
        clock.advance(by: 0.001)
        try await task.value
        #expect(woke.snapshot)
        #expect(clock.now == origin.addingTimeInterval(45))
    }

    @Test func cancellationEndsASleep() async {
        let clock = FakeAppClock(start: origin)
        let task = Task { try await clock.sleep(for: .seconds(60)) }
        await clock.waitForSleepers()
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(clock.sleeperCount == 0)
    }
}

@Suite struct SecretContractTests {
    @Test func interactionRequiredIsInjectable() async {
        let store = FakeSecretStore()
        store.seed(.contentKey, SecretValue(Data([1])))
        store.setReadFailure(.interactionRequired)
        await #expect(throws: SecretStoreError.interactionRequired) {
            try await store.read(.contentKey)
        }
        store.setReadFailure(nil)
        #expect((try? await store.read(.contentKey))?.reveal() == Data([1]))
        await #expect(throws: SecretStoreError.notFound) { try await store.read(.writeToken) }
        #expect(store.readCount == 3)
    }

    @Test func deletingAMissingSecretSucceeds() async throws {
        let store = FakeSecretStore()
        try await store.delete(.writeToken)
        try await store.delete(.writeToken)
    }

    @Test func secretValueRedactsEveryStringForm() {
        let secret = SecretValue(Data([0xDE, 0xAD, 0xBE, 0xEF]))
        var dumped = ""
        dump(secret, to: &dumped)
        for form in [
            String(describing: secret), String(reflecting: secret), "\(secret)", dumped,
        ] {
            #expect(!form.localizedCaseInsensitiveContains("dead"))
            #expect(!form.contains("222"))
        }
    }

    @Test func generatorIsDeterministicAndJitterIsScripted() throws {
        let generator = FakeSecretGenerator()
        generator.queueUnits([0.25, 1], then: 0.5)
        #expect(generator.randomUnit() == 0.25)
        #expect(generator.randomUnit() == 1)
        #expect(generator.randomUnit() == 0.5)
        let first: ReaderID = try generator.randomIdentifier()
        let second: ReaderID = try generator.randomIdentifier()
        #expect(first != second)
        #expect(generator.digest(of: SecretValue(Data([1]))) != Data([1]))
    }
}

@Suite struct EnvelopeAndCodecContractTests {
    @Test func cipherSealsExactSizesAndRejectsAWrongKey() throws {
        let cipher = FakeEnvelopeCipher()
        let header = EnvelopeHeader(
            protocolVersion: 1, envelopeVersion: 1, publisherID: publisherID, sequence: 1,
            keyVersion: 1)
        let key = SecretValue(Data(repeating: 7, count: 32))
        cipher.setTargetSize(65_536)
        let sealed = try cipher.seal(try emptySnapshot(), header: header, key: key)
        #expect(sealed.encoded.count == 65_536)
        let opened = try cipher.open(sealed.encoded, key: key)
        #expect(opened.header == header)
        #expect(throws: EnvelopeCipherError.authenticationFailed) {
            try cipher.open(sealed.encoded, key: SecretValue(Data([9])))
        }
        #expect(throws: EnvelopeCipherError.malformed) { try cipher.open(Data([1]), key: key) }
    }

    @Test func codecAppliesTheRealRules() throws {
        let codec = FakePairingCodec()
        let okHost = "a.workers.dev"
        func make(_ expires: Double, token: Int = 32, host: String = okHost) -> PairingPackage {
            PairingPackage(
                relayEndpoint: URL(string: "https://\(host)")!, readerID: readerID,
                readToken: Data(repeating: 1, count: token),
                contentKey: Data(repeating: 2, count: 32), publisherID: publisherID,
                keyVersion: 1, minimumSequence: 0,
                registrationExpiresAt: origin.addingTimeInterval(expires))
        }
        let good = try codec.encode(make(300))
        #expect(try codec.decode(good, now: origin).readerID == readerID)
        #expect(throws: PairingCodecError.expired) {
            try codec.decode(try codec.encode(make(-1)), now: origin)
        }
        #expect(throws: PairingCodecError.implausibleDeadline) {
            try codec.decode(try codec.encode(make(601)), now: origin)
        }
        #expect(throws: PairingCodecError.invalidKeyLength) {
            try codec.decode(try codec.encode(make(300, token: 31)), now: origin)
        }
        #expect(throws: PairingCodecError.endpointNotAllowed) {
            try codec.decode(try codec.encode(make(300, host: "evil.com")), now: origin)
        }
        #expect(codec.confirmationCode(for: good) == codec.confirmationCode(for: good))
        #expect(codec.confirmationCode(for: good) != codec.confirmationCode(for: good + "x"))
    }
}

@Suite struct StoreContractTests {
    @Test func aThrowingTransactionLeavesStateUnchanged() async throws {
        let store = FakeReaderStore(installationID: readerInstallation)
        struct Boom: Error {}
        await #expect(throws: Boom.self) {
            try await store.transact { state in
                state.failureCount = 9
                throw Boom()
            }
        }
        #expect(store.state.failureCount == 0)
    }

    @Test func transactionsAreSerializedAcrossConcurrentCallers() async throws {
        let store = FakeReaderStore(installationID: readerInstallation)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<50 {
                group.addTask { try await store.transact { $0.failureCount += 1 } }
            }
            try await group.waitForAll()
        }
        #expect(store.state.failureCount == 50)
    }

    @Test func snapshotFacadeAndReaderShareOneBundle() async throws {
        let store = FakeReaderStore(installationID: readerInstallation)
        let snapshot = try emptySnapshot()
        try await store.transact { $0.snapshot = snapshot }
        #expect(try await store.snapshotStore.load() == snapshot)
        try await store.snapshotStore.clear()
        #expect(store.state.snapshot == nil)
    }

    @Test func publisherSequenceIncrementsAndNeverRepeatsAfterAFailure() async throws {
        let store = FakePublisherStore()
        #expect(try await store.nextSequence() == 1)
        store.failNextSequenceAfterPersist()
        await #expect(throws: FakeStoreError.injected) { try await store.nextSequence() }
        #expect(try await store.nextSequence() == 3)
        store.failNextTransactions()
        await #expect(throws: FakeStoreError.injected) { try await store.nextSequence() }
        #expect(try await store.nextSequence() == 4)
    }

    @Test func localCommitKeepsHistoryAndNeverTouchesSequences() async throws {
        let store = FakeSnapshotStore()
        try await store.commitLocal(try emptySnapshot())
        #expect(store.commits.count == 1)
        try await store.clear()
        #expect(try await store.load() == nil)
    }
}

@Suite struct GateAndRelayContractTests {
    @Test func gateRefusesALiveClaimAndReclaimsAfterTheLease() async {
        let clock = FakeAppClock(start: origin)
        let gate = FakeNotificationReconcileGate(clock: clock)
        let first = await gate.claim()
        #expect(first != nil)
        #expect(await gate.claim() == nil)
        clock.advance(by: FakeNotificationReconcileGate.lease)
        #expect(await gate.claim() != nil)
        if let first { await gate.release(first) }
    }

    @Test func relayPopsItsQueueThenRepeatsTheFallback() async {
        let relay = FakeRelayGateway()
        let token = SecretValue(Data([1]))
        let url = URL(string: "https://a.workers.dev")!
        relay.queueGet(.offline, .unauthorized)
        #expect(await relay.getSnapshot(endpoint: url, readToken: token, etag: nil) == .offline)
        #expect(
            await relay.getSnapshot(endpoint: url, readToken: token, etag: "x") == .unauthorized)
        #expect(await relay.getSnapshot(endpoint: url, readToken: token, etag: nil) == .notModified)
        #expect(relay.calls.count == 3)
    }

    @Test func aHeldCallSuspendsUntilReleased() async {
        let relay = FakeRelayGateway()
        let url = URL(string: "https://a.workers.dev")!
        relay.hold(.putSnapshot)
        let done = Locked(false)
        let task = Task {
            _ = await relay.putSnapshot(Data(), endpoint: url, writeToken: SecretValue(Data()))
            done.withLock { $0 = true }
        }
        await relay.waitForCalls(.putSnapshot)
        try? await Task.sleep(for: .milliseconds(20))
        #expect(!done.snapshot)
        relay.release(.putSnapshot)
        await task.value
        #expect(done.snapshot)
    }
}

@Suite struct SystemFakeContractTests {
    @Test func deferredReadReceiptCannotMasqueradeAsAPhysicalRead() {
        let receipt = ReadReceipt.deferred(
            retryAt: origin.addingTimeInterval(60), sourceState: .sourceOffline)
        #expect(!receipt.performedAfter(origin))
        #expect(!receipt.performedSuccessfully)
        #expect(receipt.report == nil)
    }

    @Test func configuratorRefusesAnUnsafeExistingCommand() async {
        let configurator = FakeSourceConfigurator(product: .claudeCode, configuration: .unsafe)
        await #expect(throws: FakeConfigurationError.unsafeExistingConfiguration) {
            try await configurator.apply(
                ConfigurationPreview(
                    product: .claudeCode, optionID: configurator.option.id,
                    revision: ConfigurationPreviewRevision(), intent: .add,
                    launch: configurator.option.launch))
        }
        #expect(configurator.applied.isEmpty)
    }

    @Test func schedulerKeepsOneRequestPerAccountWindowAndRequestsAuthorizationOnce() async throws {
        let scheduler = FakeNotificationScheduler(authorization: .notDetermined)
        #expect(await scheduler.requestAuthorization() == .authorized)
        let accountID = AccountID(data: Data(repeating: 0xC1, count: 16))!
        let fiveHour = AccountWindow(accountID: accountID, window: .fiveHour)
        let weekly = AccountWindow(accountID: accountID, window: .weekly)
        try await scheduler.schedule(ResetRequest(accountWindow: fiveHour, fireAt: origin))
        try await scheduler.schedule(
            ResetRequest(accountWindow: fiveHour, fireAt: origin.addingTimeInterval(60)))
        #expect(await scheduler.pending().count == 1)
        #expect(
            ResetRequest(accountWindow: weekly, fireAt: origin).identifier
                == "reset.\(accountID.hex).weekly")
    }

    @Test func diagnosticsKeepHistoryInOrder() async {
        let sink = FakeDiagnosticsSink()
        await sink.record(.secretsUnavailable(at: origin))
        await sink.record(.envelopeTooLarge(sequence: 1, at: origin))
        #expect(await sink.history().map(\.category) == [.secretsUnavailable, .envelopeTooLarge])
    }
}

@Suite struct AccountScoperContractTests {
    @Test func scopesAreDeterministicDistinctAndSixteenBytes() async throws {
        let scoper = FakeAccountScoper()
        let first = try await scoper.scope(forAccountIdentifier: "account-a")
        let again = try await scoper.scope(forAccountIdentifier: "account-a")
        let other = try await scoper.scope(forAccountIdentifier: "account-b")
        #expect(first == again)
        #expect(first != other)
        #expect(first.data.count == AccountScope.byteCount)
    }
}
