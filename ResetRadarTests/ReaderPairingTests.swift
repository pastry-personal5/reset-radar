import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarTestSupport
import ResetRadarUI
import Testing

@testable import ResetRadar

@MainActor
@Suite struct ReaderPairingTests {
    let harness = ReaderHarness()

    @Test func aPastedPackageShowsItsCodeAndSavesNothingBeforeConfirmation() async throws {
        let environment = harness.environment()
        await environment.reload()
        #expect(environment.setupStep == .pairMac)
        let package = try harness.package()
        environment.previewPairing("  \(package)\n")
        #expect(
            environment.pairingStep == .confirm(code: harness.codec.confirmationCode(for: package)))
        #expect(harness.relay.calls.isEmpty)
        #expect(harness.secrets.names.isEmpty)
        #expect(try await harness.state.pairing == nil)
    }

    @Test func anUnavailableCameraLeavesManualPasteUsable() async throws {
        let environment = harness.environment()
        await environment.reload()
        environment.reportCameraUnavailable()
        #expect(
            environment.pairingMessage
                == "Camera scanning is unavailable. Paste the Pairing Package instead.")
        let package = try harness.package()
        environment.previewPairing(package)
        #expect(
            environment.pairingStep == .confirm(code: harness.codec.confirmationCode(for: package)))
        #expect(environment.pairingMessage == nil)
    }

    @Test func anInvalidPackageShowsNoCode() async {
        let environment = harness.environment()
        environment.previewPairing("not a pairing package")
        #expect(environment.pairingStep == .entry)
        #expect(environment.pairingMessage == PairingSyncText.pairingError(.codec(.malformed)))
    }

    @Test func aLostActivationHidesThePreflightUntilTheNextActivation() async throws {
        let environment = harness.environment()
        try harness.relay.queueGet(harness.envelope(sequence: 5))
        harness.relay.queueActivate(.offline)
        environment.previewPairing(try harness.package())
        await environment.confirmPairing()
        #expect(environment.pairing?.state == .awaitingActivation)
        #expect(environment.setupStep == .confirmingPairing)
        #expect(environment.home.accounts.isEmpty)
        #expect(try await harness.state.snapshot != nil)
        #expect(environment.pairingMessage == PairingSyncText.pairingOutcome(.awaitingActivation))

        harness.relay.queueActivate(.accepted(sequence: nil))
        await environment.sceneBecameActive()
        environment.sceneBecameInactive()
        #expect(environment.pairing?.state == .paired)
        #expect(environment.home.accounts.map(\.account.id) == [codexA, codexB, claude])
        #expect(harness.relay.calls(.activateReader).count == 2)
    }

    @Test func overlappingActivationsSendOneActivationRequest() async throws {
        try await harness.seedPaired(committed: nil)
        try await harness.store.transact { $0.awaitingActivation = true }
        harness.relay.hold(.activateReader)
        let environment = harness.environment()
        async let first: Void = environment.sceneBecameActive()
        async let second: Void = environment.sceneBecameActive()
        await harness.relay.waitForCalls(.activateReader)
        harness.relay.release(.activateReader)
        _ = await (first, second)
        environment.sceneBecameInactive()
        #expect(harness.relay.calls(.activateReader).count == 1)
    }

    @Test func anExpiredOrRevokedRegistrationReturnsToSetupForAFreshPackage() async throws {
        let environment = harness.environment()
        harness.relay.queueGet(.awaitingFirstPublish)
        harness.relay.queueActivate(.unauthorized)
        environment.previewPairing(try harness.package())
        await environment.confirmPairing()
        #expect(environment.pairing?.state == .notPaired)
        #expect(environment.setupStep == .pairMac)
        #expect(environment.pairingMessage == PairingSyncText.pairingOutcome(.activationRejected))
        #expect(harness.secrets.names.isEmpty)
    }

    @Test func aFirstPublicationNotFoundCompletesPairingAsWaitingForMacData() async throws {
        let environment = harness.environment()
        harness.relay.queueGet(.awaitingFirstPublish, .awaitingFirstPublish)
        environment.previewPairing(try harness.package())
        await environment.confirmPairing()
        #expect(environment.pairing?.state == .paired)
        #expect(environment.setupStep == .waitingForMacData)
        #expect(environment.home.accounts.isEmpty)
    }

    @Test func aFailedPreflightOrLocalSaveSendsNoActivation() async throws {
        let environment = harness.environment()
        harness.relay.queueGet(.offline)
        environment.previewPairing(try harness.package())
        await environment.confirmPairing()
        #expect(
            environment.pairingMessage == PairingSyncText.pairingError(.preflightFailed(.offline)))
        harness.relay.queueGet(.awaitingFirstPublish)
        harness.secrets.setWriteFailure(.unexpected(statusClass: 1))
        environment.previewPairing(try harness.package())
        await environment.confirmPairing()
        #expect(environment.pairingMessage == PairingSyncText.pairingError(.storageFailed))
        #expect(harness.relay.calls(.activateReader).isEmpty)
        #expect(try await harness.state.pairing == nil)
    }

    @Test func forgetMacThenPairingAnotherMacSucceeds() async throws {
        try await harness.seedPaired()
        let environment = harness.environment()
        await environment.forget()
        #expect(PairingSyncText.acceptsPairingPackage(environment.pairing))
        try harness.relay.queueGet(harness.envelope(sequence: 3, publisher: publisherB))
        environment.previewPairing(try harness.package(publisher: publisherB))
        await environment.confirmPairing()
        #expect(environment.pairing?.state == .paired)
        #expect(try await harness.state.pairing?.publisherID == publisherB)
        #expect(environment.home.accounts.count == 3)
    }

    @Test func aRejectedActivationAcceptsAFreshPackage() async throws {
        let environment = harness.environment()
        harness.relay.queueGet(.awaitingFirstPublish, .awaitingFirstPublish, .awaitingFirstPublish)
        harness.relay.queueActivate(.unauthorized, .accepted(sequence: nil))
        environment.previewPairing(try harness.package())
        await environment.confirmPairing()
        #expect(environment.pairing?.state == .notPaired)
        environment.previewPairing(try harness.package())
        await environment.confirmPairing()
        #expect(environment.pairing?.state == .paired)
        #expect(environment.setupStep == .waitingForMacData)
    }

    @Test func pairingAnotherMacRequiresForgetMacFirst() async throws {
        try await harness.seedPaired()
        let environment = harness.environment()
        await environment.reload()
        #expect(!PairingSyncText.acceptsPairingPackage(environment.pairing))
        environment.previewPairing(try harness.package(publisher: publisherB))
        await environment.confirmPairing()
        #expect(environment.pairingMessage == PairingSyncText.pairingError(.forgetRequired))
        #expect(try await harness.state.pairing?.publisherID == publisherA)
    }

    @Test func secretsStagedBeforeACrashAreRemovedAtLaunch() async throws {
        harness.secrets.seed(.readToken, readToken)
        harness.secrets.seed(.contentKey, contentKey)
        try await harness.store.transact { $0.stagingReaderID = readerA }
        let environment = harness.environment()
        await environment.sceneBecameActive()
        environment.sceneBecameInactive()
        #expect(harness.secrets.names.isEmpty)
        #expect(try await harness.state.stagingReaderID == nil)
        #expect(environment.setupStep == .pairMac)
    }
}
