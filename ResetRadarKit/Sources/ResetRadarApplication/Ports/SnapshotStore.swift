import ResetRadarDomain

/// The committed snapshot. The iOS facade shares one atomic bundle with `ReaderStore`.
public protocol SnapshotStore: Sendable {
    func load() async throws -> UsageSnapshot?
    func clear() async throws
}

/// Mac collection: replaces the collected snapshot without assigning a relay sequence.
public protocol LocalSnapshotCommitting: SnapshotStore {
    func commitLocal(_ snapshot: UsageSnapshot) async throws
    /// Atomically changes one alias against the latest committed snapshot when supported.
    func updateAccountAlias(_ id: AccountID, to alias: AccountAlias?) async throws -> UsageSnapshot?
}
