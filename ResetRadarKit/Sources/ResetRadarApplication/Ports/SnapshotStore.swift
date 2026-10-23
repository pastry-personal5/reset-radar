import ResetRadarDomain

/// The committed snapshot. The iOS facade shares one atomic bundle with `ReaderStore`.
public protocol SnapshotStore: Sendable {
    func load() async throws -> UsageSnapshot?
    func clear() async throws
}

/// Mac collection: replaces the collected snapshot without assigning a relay sequence.
public protocol LocalSnapshotCommitting: SnapshotStore {
    func commitLocal(_ snapshot: UsageSnapshot) async throws
}
