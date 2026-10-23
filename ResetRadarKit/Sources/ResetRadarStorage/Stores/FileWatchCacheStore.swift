import ResetRadarApplication

/// The Watch cache bundle: snapshot, relay sequence, delivery revision, clear tombstone, and
/// erase hold in one file, replaced whole.
public final class FileWatchCacheStore: WatchCacheStore {
    private let file: TransactionalFile<WatchCacheState>

    public init(locations: StorageLocations, writer: AtomicFileWriter = AtomicFileWriter()) {
        file = TransactionalFile(
            locations: locations, name: "watch-cache", writer: writer,
            makeDefault: { WatchCacheState() })
    }

    public func load() async throws -> WatchCacheState {
        try await file.load()
    }

    public func transact<T: Sendable>(
        _ body: @Sendable (inout WatchCacheState) throws -> T
    ) async throws -> T {
        try await file.transact(body)
    }
}
