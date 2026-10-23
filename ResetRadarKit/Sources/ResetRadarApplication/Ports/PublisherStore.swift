/// Mac relay metadata. `nextSequence` persists the incremented value before returning it.
public protocol PublisherStore: Sendable {
    func load() async throws -> PublisherState
    func transact<T: Sendable>(
        _ body: @Sendable (inout PublisherState) throws -> T
    ) async throws -> T
    func nextSequence() async throws -> UInt64
}
