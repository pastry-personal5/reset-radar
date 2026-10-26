import Foundation
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

    /// `nil` when nothing may be shown. A failed read throws, so a reconciler can tell a
    /// transient store failure from "nothing to show" and leave its effects alone.
    public func load() async throws -> UsageSnapshot? {
        if let reader {
            let state = try await reader.load()
            guard state.pairing != nil, !state.awaitingActivation, !state.forgetCleanupPending
            else { return nil }
        }
        return try await snapshots.load()
    }

    /// The same value for read-only queries, where an unreadable store shows as empty.
    public func current() async -> UsageSnapshot? {
        (try? await load()) ?? nil
    }

    func transportStatus() async -> TransportStatus {
        guard let reader, let state = try? await reader.load() else { return .current }
        return state.transportStatus
    }

    /// The reader's last successful relay read; `nil` on the Mac, which has no reader.
    func lastSyncedAt() async -> Date? {
        guard let reader, let state = try? await reader.load() else { return nil }
        return state.lastSuccessAt
    }
}
