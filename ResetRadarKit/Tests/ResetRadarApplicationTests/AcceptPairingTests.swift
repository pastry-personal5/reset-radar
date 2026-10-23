import Foundation
import ResetRadarDomain
import ResetRadarTestSupport
import Testing

@testable import ResetRadarApplication

let okHost = "a.workers.dev"

final class PairingRig: @unchecked Sendable {
    let base = ReaderRig(paired: false, seedSecrets: false)
    let codec = FakePairingCodec()

    func makeAccept() -> AcceptPairing {
        AcceptPairing(
            reader: base.store, secrets: base.secrets, relay: base.relay, cipher: base.cipher,
            codec: codec, clock: base.clock, afterCommit: base.pipeline())
    }

    func text(expires: Double = 300, token: Int = 32, host: String = okHost) -> String {
        let package = PairingPackage(
            relayEndpoint: URL(string: "https://\(host)")!, readerID: readerA,
            readToken: bytes(token, 0x55), contentKey: readerContentKey.reveal(),
            publisherID: publisher, keyVersion: 1, minimumSequence: 3,
            registrationExpiresAt: base.clock.now.addingTimeInterval(expires))
        // swiftlint:disable:next force_try
        return try! codec.encode(package)
    }

    func accept(_ use: AcceptPairing, _ text: String) async throws -> PairingOutcome {
        await use.accept(try use.preview(text), confirmed: true)
    }
}

@Suite struct AcceptPairingTests {
    let rig = PairingRig()

    @Test func previewShowsTheConfirmationCodeAndChangesNothing() throws {
        let text = rig.text()
        let before = rig.base.store.state
        let preview = try rig.makeAccept().preview(text)
        #expect(preview.confirmationCode == rig.codec.confirmationCode(for: text))
        #expect(rig.base.store.state == before)
        #expect(rig.base.secrets.names.isEmpty)
        #expect(rig.base.relay.calls.isEmpty)
    }

    @Test func acceptWithoutConfirmationFailsAndChangesNothing() async throws {
        let use = rig.makeAccept()
        let preview = try use.preview(rig.text())
        #expect(await use.accept(preview, confirmed: false) == .failed(.confirmationRequired))
        #expect(rig.base.relay.calls.isEmpty && rig.base.secrets.names.isEmpty)
    }

    @Test(arguments: [
        (-1.0, 32, "a.workers.dev", PairingCodecError.expired),
        (601.0, 32, "a.workers.dev", .implausibleDeadline),
        (300.0, 31, "a.workers.dev", .invalidKeyLength),
        (300.0, 32, "evil.example.com", .endpointNotAllowed),
    ])
    func codecFailuresSurfaceTypedWithoutAStoreWrite(
        expires: Double, token: Int, host: String, expected: PairingCodecError
    ) {
        let text = rig.text(expires: expires, token: token, host: host)
        #expect(throws: PairingError.codec(expected)) { try rig.makeAccept().preview(text) }
        #expect(rig.base.store.state.pairing == nil && rig.base.secrets.names.isEmpty)
    }

    @Test func aValidatedPreflightSnapshotIsCommittedAndActivationFollows() async throws {
        rig.base.relay.queueGet(rig.base.envelope(sequence: 5))
        #expect(try await rig.accept(rig.makeAccept(), rig.text()) == .paired)
        let state = rig.base.store.state
        #expect(state.snapshot != nil && state.committedSequence == 5)
        #expect(state.transportStatus == .current && !state.awaitingActivation)
        #expect(rig.base.relay.calls.map { operationName($0) } == ["get", "activate"])
        #expect(rig.base.secrets.names == [.readToken, .contentKey])
        #expect(rig.base.log.all == ["notifications", "liveActivities", "watch"])
    }

    @Test func anAuthenticatedFirstPublishNotFoundIsAccepted() async throws {
        rig.base.relay.queueGet(.awaitingFirstPublish)
        #expect(try await rig.accept(rig.makeAccept(), rig.text()) == .paired)
        let state = rig.base.store.state
        #expect(state.snapshot == nil && state.transportStatus == .awaitingFirstPublish)
    }

    @Test func nothingActivatesBeforeTheLocalCommit() async throws {
        rig.base.relay.queueGet(rig.base.envelope(sequence: 5))
        rig.base.relay.hold(.activateReader)
        let use = rig.makeAccept()
        let text = rig.text()
        let task = Task { try await rig.accept(use, text) }
        await rig.base.relay.waitForCalls(.activateReader)
        let state = rig.base.store.state
        #expect(state.pairing != nil && state.awaitingActivation)
        #expect(state.stagingReaderID == nil)
        #expect(state.transportStatus == .notPaired)
        #expect(rig.base.secrets.names == [.readToken, .contentKey])
        rig.base.relay.release(.activateReader)
        #expect(try await task.value == .paired)
    }

    @Test func aBadPreflightCommitsNothing() async throws {
        let cases: [(RelayOutcome, TransportStatus)] = [
            (rig.base.envelope(sequence: 5, publisherID: otherPublisher), .invalidSnapshot),
            (rig.base.envelope(sequence: 2), .invalidSnapshot),
            (.unauthorized, .authorizationRequired),
            (.offline, .offline),
        ]
        for (outcome, status) in cases {
            rig.base.relay.queueGet(outcome)
            let result = try await rig.accept(rig.makeAccept(), rig.text())
            #expect(result == .failed(.preflightFailed(status)))
        }
        #expect(rig.base.store.state.pairing == nil && rig.base.secrets.names.isEmpty)
        #expect(rig.base.relay.calls(.activateReader).isEmpty)
    }

    @Test func aKeychainFailureRemovesStagedSecretsAndSendsNoActivation() async throws {
        rig.base.relay.queueGet(.awaitingFirstPublish)
        rig.base.secrets.setWriteFailure(.interactionRequired)
        #expect(try await rig.accept(rig.makeAccept(), rig.text()) == .failed(.storageFailed))
        #expect(rig.base.store.state.stagingReaderID == nil && rig.base.store.state.pairing == nil)
        #expect(rig.base.relay.calls(.activateReader).isEmpty)
    }

    @Test func aLocalCommitFailureRemovesStagedSecretsAndSendsNoActivation() async throws {
        rig.base.relay.queueGet(.awaitingFirstPublish)
        rig.base.store.failNextTransactions(1, afterSuccesses: 1)
        #expect(try await rig.accept(rig.makeAccept(), rig.text()) == .failed(.storageFailed))
        #expect(rig.base.secrets.names.isEmpty && rig.base.store.state.pairing == nil)
        #expect(rig.base.store.state.stagingReaderID == nil)
        #expect(rig.base.relay.calls(.activateReader).isEmpty)
    }

    @Test func aLostActivationResponseIsRetriedIdempotentlyEvenAfterTheDeadline() async throws {
        rig.base.relay.queueGet(.awaitingFirstPublish)
        rig.base.relay.queueActivate(.offline)
        let use = rig.makeAccept()
        #expect(try await rig.accept(use, rig.text()) == .awaitingActivation)
        #expect(rig.base.store.state.awaitingActivation)
        for trigger in FetchTrigger.allCases {
            let outcome = await rig.base.makeIngest().run(trigger: trigger, inAppProcess: true)
            #expect(outcome == .skipped)
        }
        #expect(rig.base.relay.calls(.getSnapshot).count == 1)
        rig.base.clock.advance(by: 1_000)
        #expect(await use.resumeActivation() == .paired)
        #expect(!rig.base.store.state.awaitingActivation)
        #expect(await use.resumeActivation() == .paired)
    }

    @Test func anAuthenticated401ClearsThePendingPairing() async throws {
        rig.base.relay.queueGet(rig.base.envelope(sequence: 5))
        rig.base.relay.queueActivate(.unauthorized)
        let use = rig.makeAccept()
        #expect(try await rig.accept(use, rig.text()) == .activationRejected)
        let state = rig.base.store.state
        #expect(state.pairing == nil && state.snapshot == nil && !state.awaitingActivation)
        #expect(rig.base.secrets.names.isEmpty)
        #expect(await use.resumeActivation() == .failed(.nothingToResume))
    }

    @Test func aCrashAfterStagingIsRepairedBeforeTheNextPairing() async throws {
        rig.base.store.seed { $0.stagingReaderID = readerB }
        rig.base.secrets.seed(.readToken, SecretValue(bytes(32, 0x01)))
        rig.base.secrets.seed(.contentKey, SecretValue(bytes(32, 0x02)))
        let use = rig.makeAccept()
        await use.recoverStaging()
        #expect(rig.base.secrets.names.isEmpty && rig.base.store.state.stagingReaderID == nil)
        rig.base.store.seed { $0.stagingReaderID = readerB }
        rig.base.secrets.seed(.contentKey, SecretValue(bytes(32, 0x02)))
        rig.base.relay.queueGet(.awaitingFirstPublish)
        #expect(try await rig.accept(use, rig.text()) == .paired)
        #expect(try await rig.base.secrets.read(.contentKey) == readerContentKey)
    }

    @Test func aPairedOrCleaningUpReaderMustForgetFirst() async throws {
        rig.base.relay.queueGet(.awaitingFirstPublish)
        let use = rig.makeAccept()
        _ = try await rig.accept(use, rig.text())
        let before = try await rig.base.secrets.read(.contentKey)
        #expect(try await rig.accept(use, rig.text()) == .failed(.forgetRequired))
        #expect(try await rig.base.secrets.read(.contentKey) == before)
        rig.base.store.seed {
            $0.pairing = nil
            $0.forgetCleanupPending = true
        }
        #expect(try await rig.accept(use, rig.text()) == .failed(.cleanupPending))
    }
}

/// A short name for an operation, for compact order assertions.
func operationName(_ call: RelayCall) -> String {
    switch call {
    case .getSnapshot: "get"
    case .activateReader: "activate"
    default: "other"
    }
}
