/// The Watch cache under one lock; same `transact` contract as `ReaderStore`.
public protocol WatchCacheStore: Sendable {
    func load() async throws -> WatchCacheState
    func transact<T: Sendable>(
        _ body: @Sendable (inout WatchCacheState) throws -> T
    ) async throws -> T
}
