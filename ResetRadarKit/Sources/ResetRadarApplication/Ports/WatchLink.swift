import ResetRadarDomain

/// Availability facts supplied by the iPhone WatchConnectivity adapter. Application uses these
/// facts to decide whether a complication attempt is worth reserving; it never imports the
/// framework adapter.
public struct WatchLinkState: Sendable, Equatable {
    public var activated: Bool
    public var paired: Bool
    public var watchAppInstalled: Bool
    public var complicationEnabled: Bool
    public var remainingComplicationTransfers: Int

    public init(
        activated: Bool = false, paired: Bool = false, watchAppInstalled: Bool = false,
        complicationEnabled: Bool = false, remainingComplicationTransfers: Int = 0
    ) {
        self.activated = activated
        self.paired = paired
        self.watchAppInstalled = watchAppInstalled
        self.complicationEnabled = complicationEnabled
        self.remainingComplicationTransfers = remainingComplicationTransfers
    }
}

/// iPhone side of WatchConnectivity.
public protocol WatchLink: Sendable {
    func activate() async
    func state() async -> WatchLinkState
    func sendContext(_ payload: WatchPayload) async throws
    func transferComplication(_ payload: WatchPayload) async throws
}

/// Watch side of WatchConnectivity.
public protocol PhoneLink: Sendable {
    func activate() async
    /// Asks the iPhone to ingest and reply; `nil` when it is unreachable.
    func requestRefresh() async -> WatchPayload?
    func queueReceipt(_ receipt: WatchEraseReceipt) async throws
}

/// Existing inert implementations (iPad, tests, and platform stubs) need no lifecycle work.
extension WatchLink {
    public func activate() async {}
    public func state() async -> WatchLinkState { WatchLinkState() }
}

extension PhoneLink {
    public func activate() async {}
}
