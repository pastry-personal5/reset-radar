/// iOS reader state under a cross-process lock.
///
/// `transact` is the atomic boundary: the adapter takes its lock, reads the bundle, runs `body`
/// synchronously, and replaces the whole bundle in one write. `body` never performs I/O. A
/// throwing `body` leaves the bundle unchanged.
public protocol ReaderStore: Sendable {
    func load() async throws -> ReaderState
    func transact<T: Sendable>(
        _ body: @Sendable (inout ReaderState) throws -> T
    ) async throws -> T
}
