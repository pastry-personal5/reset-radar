import ResetRadarApplication
import ResetRadarDomain

/// The Mac's committed snapshot. `commitLocal` replaces it without assigning a relay sequence;
/// the publisher store owns the sequence when the snapshot is published.
public final class FileSnapshotStore: LocalSnapshotCommitting {
    private struct Stored: Codable, Sendable {
        var snapshot: UsageSnapshot?
    }

    private let file: TransactionalFile<Stored>

    public init(locations: StorageLocations, writer: AtomicFileWriter = AtomicFileWriter()) {
        file = TransactionalFile(
            locations: locations, name: "snapshot", writer: writer,
            makeDefault: { Stored(snapshot: nil) })
    }

    public func load() async throws -> UsageSnapshot? {
        try await file.load().snapshot
    }

    public func clear() async throws {
        try await file.transact { $0.snapshot = nil }
    }

    public func commitLocal(_ snapshot: UsageSnapshot) async throws {
        try await file.transact { $0.snapshot = snapshot }
    }
}
