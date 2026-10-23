import ResetRadarDomain

/// iPhone side of WatchConnectivity.
public protocol WatchLink: Sendable {
    func sendContext(_ payload: WatchPayload) async throws
    func transferComplication(_ payload: WatchPayload) async throws
}

/// Watch side of WatchConnectivity.
public protocol PhoneLink: Sendable {
    /// Asks the iPhone to ingest and reply; `nil` when it is unreachable.
    func requestRefresh() async -> WatchPayload?
    func queueReceipt(_ receipt: WatchEraseReceipt) async throws
}
