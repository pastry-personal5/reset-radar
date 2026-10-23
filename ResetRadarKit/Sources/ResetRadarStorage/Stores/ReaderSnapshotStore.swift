import ResetRadarApplication
import ResetRadarDomain

/// A read facade over the reader bundle. `clear` changes only the snapshot, in the same
/// replacement that keeps the pairing and sequence.
public struct ReaderSnapshotStore: SnapshotStore {
    private let store: any ReaderStore

    public init(store: any ReaderStore) {
        self.store = store
    }

    public func load() async throws -> UsageSnapshot? {
        try await store.load().snapshot
    }

    public func clear() async throws {
        try await store.transact { $0.snapshot = nil }
    }
}
