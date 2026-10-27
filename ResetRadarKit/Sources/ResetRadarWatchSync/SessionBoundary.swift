import Foundation
import ResetRadarApplication
import ResetRadarDomain

/// The WatchConnectivity state relevant to delivery. The framework adapter supplies this atomically
/// so Application policy never imports WatchConnectivity.
public struct WatchSessionState: Sendable, Equatable {
    public var activated: Bool
    public var paired: Bool
    public var watchAppInstalled: Bool
    public var reachable: Bool
    public var complicationEnabled: Bool
    public var remainingComplicationTransfers: Int

    public init(
        activated: Bool = false, paired: Bool = false, watchAppInstalled: Bool = false,
        reachable: Bool = false, complicationEnabled: Bool = false,
        remainingComplicationTransfers: Int = 0
    ) {
        self.activated = activated
        self.paired = paired
        self.watchAppInstalled = watchAppInstalled
        self.reachable = reachable
        self.complicationEnabled = complicationEnabled
        self.remainingComplicationTransfers = remainingComplicationTransfers
    }
}

public enum WatchSessionError: Error, Equatable, Sendable {
    case unavailable
    case inactive
    case notPaired
    case notReachable
    case complicationUnavailable
    case frameworkFailure
}

/// Injectable narrow surface over `WCSession`. It is intentionally dictionary-based only at this
/// adapter boundary; all clients use `WatchWireMessage`.
public protocol WatchSession: Sendable {
    func activate() async
    func state() async -> WatchSessionState
    func updateApplicationContext(_ value: [String: Any]) async throws
    func transferComplication(_ value: [String: Any]) async throws
    func sendMessage(_ value: [String: Any]) async throws -> [String: Any]
    func transferUserInfo(_ value: [String: Any]) async throws
}

/// iPhone implementation of `WatchLink`. It never stores payloads or makes ordering decisions.
public actor PhoneSideWatchLink: WatchLink {
    private let session: any WatchSession
    private let codec: WatchWireCodec

    public init(session: any WatchSession, codec: WatchWireCodec = .init()) {
        self.session = session
        self.codec = codec
    }

    public func activate() async { await session.activate() }

    public func state() async -> WatchLinkState {
        let state = await session.state()
        return WatchLinkState(
            activated: state.activated, paired: state.paired,
            watchAppInstalled: state.watchAppInstalled,
            complicationEnabled: state.complicationEnabled,
            remainingComplicationTransfers: state.remainingComplicationTransfers)
    }

    public func sendContext(_ payload: WatchPayload) async throws {
        let state = await session.state()
        guard state.activated else { throw WatchSessionError.inactive }
        guard state.paired, state.watchAppInstalled else { throw WatchSessionError.notPaired }
        try await session.updateApplicationContext(try codec.encode(.payload(payload)))
    }

    public func transferComplication(_ payload: WatchPayload) async throws {
        let state = await session.state()
        guard state.activated else { throw WatchSessionError.inactive }
        guard state.paired, state.watchAppInstalled else { throw WatchSessionError.notPaired }
        guard state.complicationEnabled, state.remainingComplicationTransfers > 0 else {
            throw WatchSessionError.complicationUnavailable
        }
        try await session.transferComplication(try codec.encode(.payload(payload)))
    }
}

/// Watch implementation of `PhoneLink`. A request is only attempted while interactive reachability
/// is true; all other delivery is via the two inbound payload channels.
public actor WatchSidePhoneLink: PhoneLink {
    private let session: any WatchSession
    private let codec: WatchWireCodec

    public init(session: any WatchSession, codec: WatchWireCodec = .init()) {
        self.session = session
        self.codec = codec
    }

    public func activate() async { await session.activate() }

    public func requestRefresh() async -> WatchPayload? {
        let state = await session.state()
        guard state.activated, state.reachable else { return nil }
        guard let reply = try? await session.sendMessage(try codec.encode(.refreshRequest)),
            let message = try? codec.decode(reply)
        else { return nil }
        guard case .refreshReply(let refreshReply) = message else { return nil }
        guard case .payload(let payload) = refreshReply else { return nil }
        return payload
    }

    public func queueReceipt(_ receipt: WatchEraseReceipt) async throws {
        guard await session.state().activated else { throw WatchSessionError.inactive }
        try await session.transferUserInfo(try codec.encode(.eraseReceipt(receipt)))
    }
}

/// Explicit iPad/macOS stub. Composition normally omits the Watch stage entirely; this value is
/// available to tests and any platform-generic object graph and can never deliver data.
public struct UnavailableWatchLink: WatchLink {
    public init() {}
    public func sendContext(_ payload: WatchPayload) async throws {
        throw WatchSessionError.unavailable
    }
    public func transferComplication(_ payload: WatchPayload) async throws {
        throw WatchSessionError.unavailable
    }
}

public struct UnavailablePhoneLink: PhoneLink {
    public init() {}
    public func requestRefresh() async -> WatchPayload? { nil }
    public func queueReceipt(_ receipt: WatchEraseReceipt) async throws {
        throw WatchSessionError.unavailable
    }
}
