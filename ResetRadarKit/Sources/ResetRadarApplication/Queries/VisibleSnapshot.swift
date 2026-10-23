import ResetRadarDomain

/// The committed snapshot as the UI may show it. On an iPhone or iPad, usage stays hidden while
/// no pairing exists, while activation is pending, and while Forget Mac cleanup is unfinished.
public struct VisibleSnapshot: Sendable {
    private let snapshots: any SnapshotStore
    private let reader: (any ReaderStore)?

    public init(snapshots: any SnapshotStore, reader: (any ReaderStore)? = nil) {
        self.snapshots = snapshots
        self.reader = reader
    }

    public func current() async -> UsageSnapshot? {
        if let reader {
            guard let state = try? await reader.load(), state.pairing != nil,
                !state.awaitingActivation, !state.forgetCleanupPending
            else { return nil }
        }
        return (try? await snapshots.load()) ?? nil
    }

    func transportStatus() async -> TransportStatus {
        guard let reader, let state = try? await reader.load() else { return .current }
        return state.transportStatus
    }
}
