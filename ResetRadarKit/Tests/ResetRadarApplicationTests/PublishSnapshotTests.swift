import Foundation
import ResetRadarDomain
import ResetRadarTestSupport
import Testing

@testable import ResetRadarApplication

final class PublishRig: @unchecked Sendable {
    let clock = FakeAppClock(start: epoch)
    let log = FakeEventLog()
    let store: FakePublisherStore
    let secrets = FakeSecretStore()
    let cipher = FakeEnvelopeCipher()
    let relay: FakeRelayGateway
    let sink = FakeDiagnosticsSink()
    let random = FakeSecretGenerator()

    init(
        lifecycle: RelayLifecycle = .active, configured: Bool = true, seedSecrets: Bool = true
    ) {
        store = FakePublisherStore(log: log)
        relay = FakeRelayGateway(log: log)
        store.seed {
            $0.lifecycle = lifecycle
            if configured {
                $0.endpoint = endpoint
                $0.publisherID = publisher
            }
        }
        if seedSecrets {
            secrets.seed(.contentKey, SecretValue(bytes(32, 0x11)))
            secrets.seed(.writeToken, SecretValue(bytes(32, 0x22)))
            secrets.seed(.adminToken, SecretValue(bytes(32, 0x33)))
        }
    }

    func makePublisher() -> PublishSnapshot {
        PublishSnapshot(
            publisher: store, secrets: secrets, cipher: cipher, relay: relay, diagnostics: sink,
            clock: clock, random: random)
    }
}

@Suite struct PublishSnapshotTests {
    let rig = PublishRig()

    func publish(
        _ use: PublishSnapshot, _ snapshot: UsageSnapshot? = nil,
        _ change: ChangeClass = .transition,
        _ trigger: PublishTrigger = .change
    ) async -> PublishOutcome {
        await use.publish(
            snapshot ?? currentSnapshot(), change: change, trigger: trigger)
    }

    func currentSnapshot(_ windows: [AllowanceWindow] = [window()]) -> UsageSnapshot {
        snapshot(windows: windows, generatedAt: rig.clock.now)
    }

    @Test(arguments: [RelayLifecycle.setupPending, .destroyPending, .notConfigured])
    func nonActiveLifecycleIsPausedWithoutSideEffects(lifecycle: RelayLifecycle) async {
        let rig = PublishRig(lifecycle: lifecycle)
        let outcome = await rig.makePublisher().publish(
            snapshot(windows: [window()]), change: .transition, trigger: .change)
        #expect(outcome == .paused)
        #expect(rig.secrets.readCount == 0)
        #expect(rig.store.nextSequenceCalls == 0)
        #expect(rig.relay.calls.isEmpty)
    }

    @Test func aMissingRelaySetupIsPaused() async {
        let rig = PublishRig(lifecycle: .active, configured: false)
        let outcome = await rig.makePublisher().publish(
            snapshot(windows: [window()]), change: .transition, trigger: .change)
        #expect(outcome == .paused)
        #expect(rig.relay.calls.isEmpty)
    }

    @Test func theSequenceIsPersistedBeforeSendingAndAFailedSendConsumesIt() async {
        let use = rig.makePublisher()
        rig.relay.queuePut(.offline, .accepted(sequence: nil))
        #expect(await publish(use) == .backoff(until: rig.clock.now.addingTimeInterval(15)))
        #expect(rig.log.all == ["nextSequence", "putSnapshot"])
        rig.clock.advance(by: 15)
        #expect(await publish(use) == .published(sequence: 2))
        #expect(rig.cipher.sealedHeaders.map(\.sequence) == [1, 2])
        #expect(rig.store.state.sequence == 2)
    }

    @Test func theEnvelopeLimitHasAnEdge() async {
        let use = rig.makePublisher()
        rig.cipher.setTargetSize(65_536)
        #expect(await publish(use) == .published(sequence: 1))
        #expect(rig.relay.calls(.putSnapshot).count == 1)
        rig.clock.advance(by: 400)
        rig.cipher.setTargetSize(65_537)
        #expect(await publish(use) == .envelopeTooLarge)
        #expect(rig.relay.calls(.putSnapshot).count == 1)
        #expect(rig.sink.categories() == [.envelopeTooLarge])
    }

    @Test func anOversizedShapeStopsRetriesUntilTheWindowSetChanges() async {
        let use = rig.makePublisher()
        rig.cipher.setTargetSize(65_537)
        #expect(await publish(use) == .envelopeTooLarge)
        let consumed = rig.store.nextSequenceCalls
        rig.clock.advance(by: 400)
        #expect(await publish(use, nil, .transition, .heartbeat) == .envelopeTooLarge)
        #expect(rig.store.nextSequenceCalls == consumed)
        let reshaped = currentSnapshot([window(), window(limitID: "extra", isDefault: false)])
        #expect(await publish(use, reshaped) == .envelopeTooLarge)
        #expect(rig.store.nextSequenceCalls == consumed + 1)
        #expect(rig.relay.calls(.putSnapshot).isEmpty)
    }

    @Test func aNewInstanceOrResumeClearsAStoppedState() async {
        let use = rig.makePublisher()
        rig.relay.queuePut(.unauthorized)
        #expect(await publish(use) == .stopped(.authorizationRequired))
        #expect(await publish(use) == .stopped(.authorizationRequired))
        await use.resume()
        #expect(await publish(use) == .published(sequence: 2))
        rig.relay.queuePut(.publisherConflict)
        rig.clock.advance(by: 400)
        _ = await publish(use)
        let relaunched = rig.makePublisher()
        #expect(await publish(relaunched) == .published(sequence: 4))
    }

    @Test func secretsAreReadOncePerProcessAndResumeAndInvalidateDropThem() async {
        let use = rig.makePublisher()
        _ = await publish(use)
        let firstReads = rig.secrets.readCount
        rig.clock.advance(by: 400)
        _ = await publish(use)
        #expect(rig.secrets.readCount == firstReads)
        rig.secrets.seed(.contentKey, SecretValue(bytes(32, 0x99)))
        await use.invalidateSecrets()
        rig.clock.advance(by: 400)
        _ = await publish(use)
        #expect(rig.secrets.readCount == 2 * firstReads)
        #expect(rig.cipher.sealKeys.last == bytes(32, 0x99))
        #expect(rig.secrets.invalidations == 1)
        await use.resume()
        rig.clock.advance(by: 400)
        _ = await publish(use)
        #expect(rig.secrets.readCount == 3 * firstReads)
    }

    @Test func interactionRequiredReportsSecretsUnavailableWithoutConsumingASequence() async {
        let use = rig.makePublisher()
        rig.secrets.setReadFailure(.interactionRequired)
        #expect(await publish(use) == .secretsUnavailable)
        #expect(rig.store.nextSequenceCalls == 0)
        #expect(rig.relay.calls.isEmpty)
        #expect(rig.sink.categories() == [.secretsUnavailable])
        rig.secrets.setReadFailure(nil)
        #expect(await publish(use) == .published(sequence: 1))
    }

    @Test(arguments: [
        (RelayOutcome.badRequest, StopReason.payloadRejected),
        (.unauthorized, .authorizationRequired),
        (.publisherConflict, .snapshotConflict),
        (.payloadTooLarge, .payloadRejected),
        (.unsupportedVersion, .incompatible),
    ])
    func stopCodesStopAutomaticRetry(outcome: RelayOutcome, reason: StopReason) async {
        let use = rig.makePublisher()
        rig.relay.queuePut(outcome)
        #expect(await publish(use) == .stopped(reason))
        #expect(rig.sink.categories() == [.publicationStopped])
        rig.clock.advance(by: 1_000)
        #expect(await publish(use, nil, .transition, .heartbeat) == .stopped(reason))
        #expect(rig.relay.calls(.putSnapshot).count == 1)
    }

    @Test(arguments: [RelayOutcome.offline, .quotaLimited, .protocolFailure])
    func transientFailuresBackOffWithJitterAndSuccessClearsTheCount(outcome: RelayOutcome) async {
        let use = rig.makePublisher()
        rig.random.queueUnits([0.5, 1.0], then: 0.5)
        rig.relay.queuePut(outcome, outcome)
        let start = rig.clock.now
        #expect(await publish(use) == .backoff(until: start.addingTimeInterval(15)))
        rig.clock.advance(by: 15)
        #expect(await publish(use) == .backoff(until: rig.clock.now.addingTimeInterval(60)))
        rig.clock.advance(by: 60)
        #expect(await publish(use) == .published(sequence: 3))
        rig.relay.queuePut(outcome)
        rig.random.queueUnits([1.0])
        rig.clock.advance(by: 400)
        #expect(await publish(use) == .backoff(until: rig.clock.now.addingTimeInterval(30)))
        #expect(rig.sink.categories().allSatisfy { $0 == .relayFailure })
    }

    @Test func notDueCarriesThePolicysNextInstantAndBackoffBeatsEveryTrigger() async {
        let use = rig.makePublisher()
        #expect(await publish(use) == .published(sequence: 1))
        rig.clock.advance(by: 10)
        let next = epoch.addingTimeInterval(30)
        #expect(await publish(use, nil, .material) == .notDue(next: next))
        rig.relay.queuePut(.offline)
        rig.clock.advance(by: 300)
        rig.random.queueUnits([1.0])
        let failed = await publish(use, nil, .transition)
        guard case .backoff(let until) = failed else {
            Issue.record("expected backoff, got \(failed)")
            return
        }
        for trigger in PublishTrigger.allCases {
            #expect(await publish(use, nil, .transition, trigger) == .backoff(until: until))
        }
    }

    @Test func bindPublishesDuringSetupIgnoringPolicy() async {
        let rig = PublishRig(lifecycle: .setupPending)
        let use = rig.makePublisher()
        #expect(await use.bind(snapshot(windows: [window()])) == .published(sequence: 1))
        let active = PublishRig(lifecycle: .active)
        #expect(await active.makePublisher().bind(snapshot(windows: [])) == .paused)
    }

    @Test func overlappingPublicationsSendOneAtATimeInSequenceOrder() async {
        let use = rig.makePublisher()
        rig.relay.holdNext(.putSnapshot)
        async let first = publish(use)
        await rig.relay.waitForCalls(.putSnapshot)
        async let second = publish(use, nil, .transition, .heartbeat)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(rig.relay.calls(.putSnapshot).count == 1)
        #expect(rig.store.nextSequenceCalls == 1)
        rig.relay.release(.putSnapshot)
        #expect(await first == .published(sequence: 1))
        // The waiting caller sends only after the first finished, with the next sequence.
        #expect(await second == .published(sequence: 2))
        #expect(rig.cipher.sealedHeaders.map(\.sequence) == [1, 2])
        #expect(rig.relay.calls(.putSnapshot).count == 2)
    }

    @Test func aSnapshotFromASupersededPublisherIsRestamped() async {
        let use = rig.makePublisher()
        let stale = snapshot(
            windows: [window()], generatedAt: rig.clock.now, publisherID: otherPublisher)
        #expect(await publish(use, stale) == .published(sequence: 1))
        guard case .putSnapshot(let sent)? = rig.relay.calls(.putSnapshot).first,
            let opened = try? rig.cipher.open(sent, key: SecretValue(bytes(32, 0x11)))
        else {
            Issue.record("expected one sent envelope")
            return
        }
        #expect(opened.snapshot.publisherID == publisher)
        #expect(opened.header.publisherID == publisher)
    }
}
