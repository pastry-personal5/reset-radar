import Foundation
import ResetRadarDomain
import ResetRadarTestSupport
import ResetRadarWatchSync
import Testing

@Suite struct WatchWireCodecTests {
    private let codec = WatchWireCodec()

    @Test func payloadRoundTripsAsTheOnlyTypedPayloadEnvelope() throws {
        let installationID = try #require(InstallationID(data: Data(repeating: 1, count: 16)))
        let payload = try WatchPayload(
            installationID: installationID, deliveryRevision: 7, snapshot: nil,
            relaySequence: nil, transportStatus: .current, lastRelayContactAt: nil,
            lastCommitAt: nil, cleared: false)
        let encoded = try codec.encode(.payload(payload))
        #expect(try codec.decode(encoded) == .payload(payload))
        #expect(Set(encoded.keys) == ["v", "k", "b"])
    }

    @Test func refreshEmptyHasNoFabricatedPayloadOrRevision() throws {
        let encoded = try codec.encode(.refreshReply(.empty))
        #expect(Set(encoded.keys) == ["v", "k"])
        #expect(try codec.decode(encoded) == .refreshReply(.empty))
    }

    @Test func rejectsUnknownVersionsUnexpectedKeysAndMalformedBodies() throws {
        var unknown = try codec.encode(.refreshRequest)
        unknown["v"] = 2
        #expect(throws: WatchWireCodecError.unsupportedVersion) { try codec.decode(unknown) }

        var extra = try codec.encode(.refreshRequest)
        extra["secret"] = "never accepted"
        #expect(throws: WatchWireCodecError.unexpectedKeys) { try codec.decode(extra) }

        let malformed: [String: Any] = ["v": 1, "k": "payload", "b": Data([1, 2, 3])]
        #expect(throws: WatchWireCodecError.invalidBody) { try codec.decode(malformed) }
    }

    @Test func receiptRoundTripsWithoutUsageOrSecretFields() throws {
        let installationID = try #require(
            InstallationID(data: Data(repeating: 3, count: InstallationID.byteCount)))
        let receipt = WatchEraseReceipt(installationID: installationID, deliveryRevision: 12)
        let encoded = try codec.encode(.eraseReceipt(receipt))
        #expect(try codec.decode(encoded) == .eraseReceipt(receipt))
        #expect(Set(encoded.keys) == ["v", "k", "b"])
    }

    @Test func rejectsOversizedAndDeeplyNestedPropertyLists() {
        let oversized: [String: Any] = [
            "v": 1, "k": "payload", "b": Data(repeating: 0, count: WatchWireCodec.maximumBytes),
        ]
        #expect(throws: WatchWireCodecError.oversized) { try codec.decode(oversized) }

        var nested: Any = "leaf"
        for _ in 0...WatchWireCodec.maximumNesting { nested = ["x": nested] }
        let deep: [String: Any] = ["v": 1, "k": "refreshRequest", "extra": nested]
        #expect(throws: WatchWireCodecError.malformed) { try codec.decode(deep) }
    }
}

@Suite struct WatchSessionAdapterTests {
    private let codec = WatchWireCodec()

    @Test func phoneUsesApplicationContextEvenWhenComplicationIsUnavailable() async throws {
        let session = FakeWatchSession(
            state: WatchSessionState(
                activated: true, paired: true, watchAppInstalled: true,
                complicationEnabled: false, remainingComplicationTransfers: 0))
        let link = PhoneSideWatchLink(session: session)
        let payload = try payload()
        try await link.sendContext(payload)
        #expect(session.contextCount() == 1)
        await #expect(throws: WatchSessionError.complicationUnavailable) {
            try await link.transferComplication(payload)
        }
        let decoded = try codec.decode(try #require(session.context(at: 0)))
        #expect(decoded == .payload(payload))
    }

    @Test func watchDoesNotSendAnInteractiveRequestWhileUnreachable() async throws {
        let session = FakeWatchSession(state: WatchSessionState(activated: true, reachable: false))
        let phone = WatchSidePhoneLink(session: session)
        #expect(await phone.requestRefresh() == nil)
        #expect(session.messageCount() == 0)
    }

    @Test func phoneRejectsContextBeforeActivationOrPairing() async throws {
        let session = FakeWatchSession(state: WatchSessionState())
        let link = PhoneSideWatchLink(session: session)
        let payload = try payload()
        await #expect(throws: WatchSessionError.inactive) { try await link.sendContext(payload) }
        await link.activate()
        await #expect(throws: WatchSessionError.notPaired) { try await link.sendContext(payload) }
        #expect(session.contextCount() == 0)
    }

    @Test func watchQueuesReceiptOnlyAfterSessionActivation() async throws {
        let payload = try payload()
        let session = FakeWatchSession(state: WatchSessionState())
        let phone = WatchSidePhoneLink(session: session)
        let receipt = WatchEraseReceipt(
            installationID: payload.installationID, deliveryRevision: payload.deliveryRevision)
        await #expect(throws: WatchSessionError.inactive) {
            try await phone.queueReceipt(receipt)
        }
        await phone.activate()
        try await phone.queueReceipt(receipt)
        #expect(session.userInfo(at: 0) != nil)
    }

    @Test func watchDecodesTypedPayloadReplyAndQueuesOnlyReceiptEnvelope() async throws {
        let payload = try payload()
        let session = FakeWatchSession(state: WatchSessionState(activated: true, reachable: true))
        session.setReply(try codec.encode(.refreshReply(.payload(payload))))
        let phone = WatchSidePhoneLink(session: session)
        #expect(await phone.requestRefresh() == payload)
        let receipt = WatchEraseReceipt(
            installationID: payload.installationID, deliveryRevision: payload.deliveryRevision)
        try await phone.queueReceipt(receipt)
        let decoded = try codec.decode(try #require(session.userInfo(at: 0)))
        #expect(decoded == .eraseReceipt(receipt))
    }

    @Test func inactivePlatformStubsNeverDeliver() async throws {
        let payload = try payload()
        let watch = UnavailableWatchLink()
        await #expect(throws: WatchSessionError.unavailable) {
            try await watch.sendContext(payload)
        }
        let phone = UnavailablePhoneLink()
        #expect(await phone.requestRefresh() == nil)
        await #expect(throws: WatchSessionError.unavailable) {
            try await phone.queueReceipt(
                WatchEraseReceipt(
                    installationID: payload.installationID,
                    deliveryRevision: payload.deliveryRevision))
        }
    }

    private func payload() throws -> WatchPayload {
        let installationID = try #require(InstallationID(data: Data(repeating: 2, count: 16)))
        return try WatchPayload(
            installationID: installationID, deliveryRevision: 3, snapshot: nil,
            relaySequence: nil, transportStatus: .current, lastRelayContactAt: nil,
            lastCommitAt: nil, cleared: false)
    }
}

@Suite struct PayloadDrainTrackerTests {
    @Test func backgroundWaitEndsOnlyAfterEveryDeliveredPayloadFinishes() async {
        let tracker = PayloadDrainTracker()
        let probe = CompletionProbe()
        tracker.begin()
        tracker.begin()
        let waiting = Task {
            await tracker.waitUntilDrained()
            probe.completed = true
        }
        for _ in 0..<10 { await Task.yield() }
        #expect(!probe.completed)
        tracker.finish()
        for _ in 0..<10 { await Task.yield() }
        #expect(!probe.completed)
        tracker.finish()
        await waiting.value
        #expect(probe.completed)
    }
}

private final class CompletionProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var completed: Bool {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

private final class FakeWatchSession: WatchSession, @unchecked Sendable {
    private struct State {
        var session: WatchSessionState
        var contexts: [[String: Any]] = []
        var complications: [[String: Any]] = []
        var messages: [[String: Any]] = []
        var userInfos: [[String: Any]] = []
        var reply: [String: Any] = [:]
    }

    private let lock = NSLock()
    private var value: State

    init(state: WatchSessionState) { value = State(session: state) }

    func setReply(_ reply: [String: Any]) { withLock { $0.reply = reply } }
    func contextCount() -> Int { withLock { $0.contexts.count } }
    func context(at index: Int) -> [String: Any]? {
        withLock { $0.contexts.indices.contains(index) ? $0.contexts[index] : nil }
    }
    func messageCount() -> Int { withLock { $0.messages.count } }
    func userInfo(at index: Int) -> [String: Any]? {
        withLock { $0.userInfos.indices.contains(index) ? $0.userInfos[index] : nil }
    }

    func activate() async { withLock { $0.session.activated = true } }
    func state() async -> WatchSessionState { withLock { $0.session } }
    func updateApplicationContext(_ context: [String: Any]) async throws {
        withLock { $0.contexts.append(context) }
    }
    func transferComplication(_ complication: [String: Any]) async throws {
        withLock { $0.complications.append(complication) }
    }
    func sendMessage(_ message: [String: Any]) async throws -> [String: Any] {
        withLock {
            $0.messages.append(message)
            return $0.reply
        }
    }
    func transferUserInfo(_ userInfo: [String: Any]) async throws {
        withLock { $0.userInfos.append(userInfo) }
    }

    private func withLock<T>(_ body: (inout State) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
