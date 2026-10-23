import Foundation
import ResetRadarDomain
import ResetRadarTestSupport
import Testing

@testable import ResetRadarApplication

@Suite struct PairReaderTests {
    let rig = PublishRig()
    let codec = FakePairingCodec()

    init() {
        rig.store.seed { $0.lastPublishedSequence = 7 }
    }

    func make() -> PairReader {
        PairReader(
            publisher: rig.store, secrets: rig.secrets, random: rig.random, relay: rig.relay,
            codec: codec, clock: rig.clock)
    }

    @Test func beginRegistersAPendingReaderWithTheRelayDeadline() async throws {
        let deadline = rig.clock.now.addingTimeInterval(300)
        rig.relay.queueRegister(.value(deadline))
        let offer = try await make().begin(deviceName: "Phone")
        #expect(offer.expiresAt == deadline)
        #expect(offer.package.registrationExpiresAt == deadline)
        #expect(offer.package.minimumSequence == 7)
        #expect(offer.package.publisherID == publisher)
        #expect(offer.package.contentKey == bytes(32, 0x11))
        #expect(rig.store.state.pendingRegistrations.map(\.readerID) == [offer.readerID])
        #expect(rig.secrets.names.contains(.readerToken(offer.readerID)))
        guard case .registerReader(_, let digest) = rig.relay.calls(.registerReader).first else {
            Issue.record("no registration")
            return
        }
        #expect(digest == rig.random.digest(of: SecretValue(offer.package.readToken)))
        #expect(digest != offer.package.readToken)
        #expect(offer.confirmationCode == codec.confirmationCode(for: offer.encoded))
        #expect(try codec.decode(offer.encoded, now: rig.clock.now).readerID == offer.readerID)
        #expect(!String(describing: offer).contains(offer.encoded))
    }

    @Test func aFourthReaderIsRefusedWithoutLeavingState() async {
        rig.relay.queueRegister(.outcome(.readerCapReached))
        await #expect(throws: PairReaderError.readerCapReached) {
            try await make().begin(deviceName: "Fourth")
        }
        #expect(rig.store.state.pendingRegistrations.isEmpty)
        #expect(rig.secrets.names.filter { $0 != .contentKey }.count == 2)
    }

    @Test func pairingNeedsAnActiveRelay() async {
        let inactive = PublishRig(lifecycle: .setupPending)
        let use = PairReader(
            publisher: inactive.store, secrets: inactive.secrets, random: inactive.random,
            relay: inactive.relay, codec: codec, clock: inactive.clock)
        await #expect(throws: PairReaderError.notActive) { try await use.begin(deviceName: "x") }
        #expect(inactive.relay.calls.isEmpty)
    }

    @Test func activationIsConfirmedOnlyWhenTheRelayListsAnActivatedReader() async throws {
        let use = make()
        rig.relay.queueRegister(.value(rig.clock.now.addingTimeInterval(300)))
        let offer = try await use.begin(deviceName: "Phone")
        rig.relay.queueListReaders(.value([RelayReader(id: offer.readerID, activated: false)]))
        #expect(await use.pollActivation() == .pending)
        rig.relay.queueListReaders(.value([RelayReader(id: offer.readerID, activated: true)]))
        #expect(await use.pollActivation() == .confirmed)
        let state = rig.store.state
        #expect(state.devices.map(\.name) == ["Phone"])
        #expect(state.pendingRegistrations.isEmpty)
    }

    @Test func aRelayErrorWhilePollingStaysPendingUntilTheDeadline() async throws {
        let use = make()
        rig.relay.queueRegister(.value(rig.clock.now.addingTimeInterval(300)))
        _ = try await use.begin(deviceName: "Phone")
        rig.relay.queueListReaders(.outcome(.offline))
        #expect(await use.pollActivation() == .pending)
        rig.clock.advance(by: 300)
        rig.relay.queueListReaders(.outcome(.offline))
        #expect(await use.pollActivation() == .expired)
    }

    @Test func expiryRevokesAtTheDeadlineAndNotBefore() async throws {
        let use = make()
        rig.relay.queueRegister(.value(rig.clock.now.addingTimeInterval(300)))
        let offer = try await use.begin(deviceName: "Phone")
        rig.clock.advance(by: 299)
        await use.revokeIfExpired()
        #expect(rig.relay.calls(.revokeReader).isEmpty)
        rig.clock.advance(by: 1)
        await use.revokeIfExpired()
        #expect(rig.relay.calls(.revokeReader) == [.revokeReader(offer.readerID)])
        #expect(rig.store.state.pendingRegistrations.isEmpty)
        #expect(!rig.secrets.names.contains(.readerToken(offer.readerID)))
    }

    @Test func aReaderThatActivatedJustBeforeTheDeadlineIsKept() async throws {
        let use = make()
        rig.relay.queueRegister(.value(rig.clock.now.addingTimeInterval(300)))
        let offer = try await use.begin(deviceName: "Phone")
        rig.clock.advance(by: 300)
        rig.relay.queueListReaders(.value([RelayReader(id: offer.readerID, activated: true)]))
        await use.revokeIfExpired()
        #expect(rig.relay.calls(.revokeReader).isEmpty)
        #expect(rig.store.state.devices.count == 1)
    }
}
