import ResetRadarApplication
import ResetRadarDomain

/// A read facade over the Watch cache bundle. `clear` drops only the snapshot and keeps the
/// delivery revision and tombstone.
public struct WatchSnapshotStore: SnapshotStore {
    private let store: any WatchCacheStore

    public init(store: any WatchCacheStore) {
        self.store = store
    }

    public func load() async throws -> UsageSnapshot? {
        try await store.load().snapshot
    }

    public func clear() async throws {
        try await store.transact { $0.snapshot = nil }
    }
}
