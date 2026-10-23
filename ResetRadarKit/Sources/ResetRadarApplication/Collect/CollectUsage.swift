import Foundation
import ResetRadarDomain

public struct CollectResult: Sendable, Equatable {
    public let snapshot: UsageSnapshot
    public let change: ChangeClass
}

/// Merges source reports into the authoritative snapshot and commits it locally. It never
/// assigns a relay sequence: `PublishSnapshot` owns that.
public actor CollectUsage {
    private let snapshots: any LocalSnapshotCommitting
    private let diagnostics: any DiagnosticsSink
    private let clock: any AppClock
    private let publisherID: PublisherID
    private let heartbeatSeconds: Int

    public init(
        snapshots: any LocalSnapshotCommitting, diagnostics: any DiagnosticsSink,
        clock: any AppClock, publisherID: PublisherID, heartbeatSeconds: Int
    ) {
        self.snapshots = snapshots
        self.diagnostics = diagnostics
        self.clock = clock
        self.publisherID = publisherID
        self.heartbeatSeconds = heartbeatSeconds
    }

    public func ingest(_ report: SourceSnapshot) async throws -> CollectResult {
        try await collect([report])
    }

    /// Restamps the committed snapshot so the Mac still reads as publishing, and expires
    /// retained windows, without any new report.
    public func heartbeat() async throws -> CollectResult {
        try await collect([])
    }

    private func collect(_ reports: [SourceSnapshot]) async throws -> CollectResult {
        let previous = try await snapshots.load()
        let reduced = try SnapshotReducer.reduce(
            previous: previous, reports: reports, publisherID: publisherID,
            heartbeatSeconds: heartbeatSeconds, now: clock.now)
        try await snapshots.commitLocal(reduced.snapshot)
        for event in reduced.snapshot.diagnostics { await diagnostics.record(event) }
        return CollectResult(snapshot: reduced.snapshot, change: reduced.change)
    }
}
