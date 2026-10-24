import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarTestSupport
import ResetRadarTransport
import Testing

private struct NoOpAfterCommitStep: AfterCommitStep {
    func afterCommit(_ event: CommitEvent) async {}
}

private func sealedOutcome(
    publisher: PublisherID, sequence: UInt64, at date: Date,
    cipher: AESGCMEnvelopeCipher, key: SecretValue
) throws -> RelayOutcome {
    let snapshot = try UsageSnapshot(
        publisherID: publisher, generatedAt: date, heartbeatSeconds: 60,
        accounts: [], sources: [], windows: [])
    let header = EnvelopeHeader(
        protocolVersion: 1, envelopeVersion: 1, publisherID: publisher,
        sequence: sequence, keyVersion: 1)
    let bytes = try cipher.seal(snapshot, header: header, key: key).encoded
    return .snapshot(bytes, etag: "\"synthetic-\(sequence)\"", sequence: sequence)
}

@Test func publishUseCaseCommitsSequenceAndSendsRealAuthenticatedEnvelope() async throws {
    let publisherID = PublisherID(data: Data(repeating: 0x23, count: 32))!
    let endpoint = URL(string: "https://reset.example.workers.dev")!
    let contentKey = SecretValue(Data(repeating: 0x67, count: 32))
    let store = FakePublisherStore()
    store.seed {
        $0.lifecycle = .active
        $0.endpoint = endpoint
        $0.publisherID = publisherID
    }
    let secrets = FakeSecretStore()
    secrets.seed(.contentKey, contentKey)
    secrets.seed(.writeToken, SecretValue(Data(repeating: 0x11, count: 32)))
    let relay = FakeRelayGateway()
    let clock = FakeAppClock(start: Date(timeIntervalSince1970: 1_700_000_000))
    let cipher = AESGCMEnvelopeCipher(nonceSource: { Data(repeating: 0xAB, count: 12) })
    let useCase = PublishSnapshot(
        publisher: store, secrets: secrets, cipher: cipher, relay: relay,
        diagnostics: FakeDiagnosticsSink(), clock: clock, random: CryptoSecretGenerator())
    let snapshot = try UsageSnapshot(
        publisherID: publisherID, generatedAt: clock.now, heartbeatSeconds: 60,
        accounts: [], sources: [], windows: [])

    let outcome = await useCase.publish(snapshot, change: .transition, trigger: .change)
    #expect(outcome == .published(sequence: 1))
    #expect(store.state.sequence == 1)
    #expect(store.state.lastPublishedSequence == 1)
    guard let firstCall = relay.calls.first, case .putSnapshot(let bytes) = firstCall else {
        Issue.record("Expected one sealed publication")
        return
    }
    let opened = try cipher.open(bytes, key: contentKey)
    #expect(opened.header.sequence == 1)
    #expect(opened.snapshot == snapshot)
}

@Test func pairingAndIngestionUseRealCodecAndCipherWithoutLosingValidatedCache() async throws {
    let publisherID = PublisherID(data: Data(repeating: 0x23, count: 32))!
    let otherPublisher = PublisherID(data: Data(repeating: 0x24, count: 32))!
    let readerID = ReaderID(data: Data(repeating: 0x45, count: 16))!
    let installationID = InstallationID(data: Data(repeating: 0x10, count: 16))!
    let contentKey = SecretValue(Data(repeating: 0x67, count: 32))
    let clock = FakeAppClock(start: Date(timeIntervalSince1970: 1_700_000_000))
    let reader = FakeReaderStore(installationID: installationID)
    let secrets = FakeSecretStore()
    let relay = FakeRelayGateway()
    let cipher = AESGCMEnvelopeCipher()
    let codec = JSONPairingCodec()
    let pipeline = AfterCommitPipeline(
        reader: reader, reloader: FakeSurfaceReloader(),
        notifications: NoOpAfterCommitStep(), liveActivities: NoOpAfterCommitStep(), watch: nil)
    let pairing = AcceptPairing(
        reader: reader, secrets: secrets, relay: relay, cipher: cipher, codec: codec,
        clock: clock, afterCommit: pipeline)
    let package = PairingPackage(
        relayEndpoint: URL(string: "https://reset.example.workers.dev")!, readerID: readerID,
        readToken: Data(repeating: 0x89, count: 32), contentKey: contentKey.reveal(),
        publisherID: publisherID, keyVersion: 1, minimumSequence: 3,
        registrationExpiresAt: clock.now.addingTimeInterval(300))
    relay.queueGet(
        try sealedOutcome(
            publisher: publisherID, sequence: 5, at: clock.now, cipher: cipher, key: contentKey))
    let preview = try pairing.preview(codec.encode(package))
    #expect(await pairing.accept(preview, confirmed: true) == .paired)
    #expect(reader.state.committedSequence == 5)
    let validatedETag = reader.state.etag
    let lastSuccessAt = reader.state.lastSuccessAt

    let ingestion = IngestRelaySnapshot(
        reader: reader, secrets: secrets, cipher: cipher, relay: relay,
        random: CryptoSecretGenerator(), clock: clock,
        diagnostics: FakeDiagnosticsSink(), afterCommit: pipeline)
    relay.queueGet(
        try sealedOutcome(
            publisher: otherPublisher, sequence: 6, at: clock.now, cipher: cipher, key: contentKey))
    #expect(await ingestion.run(trigger: .manual, inAppProcess: true) == .failed(.invalidSnapshot))
    #expect(reader.state.committedSequence == 5)
    #expect(reader.state.snapshot?.publisherID == publisherID)
    relay.queueGet(.offline)
    #expect(await ingestion.run(trigger: .manual, inAppProcess: true) == .failed(.offline))
    #expect(reader.state.committedSequence == 5)
    #expect(reader.state.etag == validatedETag)
    #expect(reader.state.lastSuccessAt == lastSuccessAt)
    relay.queueGet(
        try sealedOutcome(
            publisher: publisherID, sequence: 7, at: clock.now, cipher: cipher, key: contentKey))
    #expect(await ingestion.run(trigger: .manual, inAppProcess: true) == .committed)
    #expect(reader.state.committedSequence == 7)
}

@Test func setupAndDestructionUseStubbedKeychainWithRealTransportCrypto() async throws {
    let backend = StubSecItemBackend()
    let secrets = KeychainSecretStore(backend: backend, build: .debug)
    let publisher = FakePublisherStore()
    let relay = FakeRelayGateway()
    let clock = FakeAppClock(start: Date(timeIntervalSince1970: 1_700_000_000))
    let random = CryptoSecretGenerator()
    let publishing = PublishSnapshot(
        publisher: publisher, secrets: secrets, cipher: AESGCMEnvelopeCipher(),
        relay: relay, diagnostics: FakeDiagnosticsSink(), clock: clock, random: random)
    let setup = SetUpRelay(
        publisher: publisher, secrets: secrets, random: random, relay: relay,
        snapshots: FakeSnapshotStore(), publishing: publishing, clock: clock,
        heartbeatSeconds: 300)
    let endpoint = URL(string: "https://reset.example.workers.dev")!
    let digests = try await setup.prepare(endpoint: endpoint)
    #expect(digests.writeToken.count == 32)
    #expect(digests.adminToken.count == 32)
    #expect(await setup.activate() == .active)
    #expect(publisher.state.lifecycle == .active)
    #expect(relay.calls(.putSnapshot).count == 1)
    let destroy = DestroyRelay(
        publisher: publisher, secrets: secrets, relay: relay, publishing: publishing)
    #expect(await destroy.run() == .destroyed)
    #expect(publisher.state.lifecycle == .notConfigured)
    do {
        _ = try await secrets.read(.contentKey)
        Issue.record("Destroyed content key remained cached")
    } catch {
        #expect(error == .notFound)
    }
}

@Test func pairReaderUsesRealGeneratorDigestAndCanonicalCodec() async throws {
    let publisherID = PublisherID(data: Data(repeating: 0x23, count: 32))!
    let endpoint = URL(string: "https://reset.example.workers.dev")!
    let publisher = FakePublisherStore()
    publisher.seed {
        $0.lifecycle = .active
        $0.endpoint = endpoint
        $0.publisherID = publisherID
        $0.lastPublishedSequence = 7
    }
    let secrets = FakeSecretStore()
    let contentKey = SecretValue(Data(repeating: 0x67, count: 32))
    secrets.seed(.contentKey, contentKey)
    secrets.seed(.adminToken, SecretValue(Data(repeating: 0x33, count: 32)))
    let relay = FakeRelayGateway()
    let clock = FakeAppClock(start: Date(timeIntervalSince1970: 1_700_000_000))
    let expiry = clock.now.addingTimeInterval(300)
    relay.queueRegister(.value(expiry))
    let codec = JSONPairingCodec()
    let pairing = PairReader(
        publisher: publisher, secrets: secrets, random: CryptoSecretGenerator(),
        relay: relay, codec: codec, clock: clock)

    let offer = try await pairing.begin(deviceName: "Synthetic Reader")
    let decoded = try codec.decode(offer.encoded, now: clock.now)
    #expect(decoded.readerID == offer.readerID)
    #expect(decoded.contentKey == contentKey.reveal())
    #expect(decoded.minimumSequence == 7)
    #expect(offer.confirmationCode == codec.confirmationCode(for: offer.encoded))
    guard let firstCall = relay.calls.first,
        case .registerReader(let registeredID, let digest) = firstCall
    else {
        Issue.record("Expected pending-reader registration")
        return
    }
    #expect(registeredID == offer.readerID)
    #expect(digest == CryptoSecretGenerator().digest(of: SecretValue(decoded.readToken)))
    relay.queueListReaders(.value([RelayReader(id: offer.readerID, activated: true)]))
    #expect(await pairing.pollActivation() == .confirmed)
    #expect(publisher.state.devices.map(\.readerID) == [offer.readerID])
}

@Test func revokeReaderDeletesStubbedKeychainTokenAfterRelayConfirmation() async throws {
    let readerID = ReaderID(data: Data(repeating: 0x45, count: 16))!
    let publisher = FakePublisherStore()
    publisher.seed {
        $0.lifecycle = .active
        $0.endpoint = URL(string: "https://reset.example.workers.dev")!
        $0.devices = [
            PairedDevice(
                readerID: readerID, name: "Synthetic Reader",
                pairedAt: Date(timeIntervalSince1970: 1_700_000_000))
        ]
    }
    let secrets = KeychainSecretStore(backend: StubSecItemBackend(), build: .debug)
    try await secrets.write(.adminToken, value: SecretValue(Data(repeating: 0x33, count: 32)))
    try await secrets.write(
        .readerToken(readerID), value: SecretValue(Data(repeating: 0x89, count: 32)))
    _ = try await secrets.read(.readerToken(readerID))
    let useCase = RevokeReader(publisher: publisher, secrets: secrets, relay: FakeRelayGateway())
    #expect(await useCase.revoke(readerID) == .revoked)
    #expect(publisher.state.devices.isEmpty)
    do {
        _ = try await secrets.read(.readerToken(readerID))
        Issue.record("Revoked reader token remained cached")
    } catch {
        #expect(error == .notFound)
    }
}

@Test func manualRefreshRateLimitClearsMarkerWithRealTransportDependencies() async throws {
    let readerID = ReaderID(data: Data(repeating: 0x45, count: 16))!
    let publisherID = PublisherID(data: Data(repeating: 0x23, count: 32))!
    let installationID = InstallationID(data: Data(repeating: 0x10, count: 16))!
    let clock = FakeAppClock(start: Date(timeIntervalSince1970: 1_700_000_000))
    let reader = FakeReaderStore(installationID: installationID)
    reader.seed {
        $0.pairing = ReaderPairing(
            endpoint: URL(string: "https://reset.example.workers.dev")!,
            publisherID: publisherID, readerID: readerID, minimumSequence: 1,
            keyVersion: 1, registrationExpiresAt: clock.now.addingTimeInterval(300))
    }
    let secrets = FakeSecretStore()
    secrets.seed(.readToken, SecretValue(Data(repeating: 0x89, count: 32)))
    secrets.seed(.contentKey, SecretValue(Data(repeating: 0x67, count: 32)))
    let relay = FakeRelayGateway()
    relay.queueGet(.awaitingFirstPublish)
    relay.queuePost(.requestRateLimited)
    let random = CryptoSecretGenerator()
    let pipeline = AfterCommitPipeline(
        reader: reader, reloader: FakeSurfaceReloader(),
        notifications: NoOpAfterCommitStep(), liveActivities: NoOpAfterCommitStep(), watch: nil)
    let ingest = IngestRelaySnapshot(
        reader: reader, secrets: secrets, cipher: AESGCMEnvelopeCipher(), relay: relay,
        random: random, clock: clock, diagnostics: FakeDiagnosticsSink(), afterCommit: pipeline)
    let refresh = RequestMacRefresh(
        reader: reader, secrets: secrets, relay: relay, random: random,
        clock: clock, ingest: ingest)
    #expect(await refresh.run(scope: [.codex]) == .rateLimited)
    #expect(reader.state.pendingManualRequest == nil)
    #expect(relay.calls(.postRefreshRequest).count == 1)
}
