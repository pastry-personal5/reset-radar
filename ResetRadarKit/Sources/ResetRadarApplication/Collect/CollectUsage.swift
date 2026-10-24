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
    private let catalogStore: any AccountCatalogStore
    private let publisherID: PublisherID
    private let heartbeatSeconds: Int
    private var gate = SerialGate()

    public init(
        snapshots: any LocalSnapshotCommitting, diagnostics: any DiagnosticsSink,
        clock: any AppClock, catalogStore: any AccountCatalogStore, publisherID: PublisherID,
        heartbeatSeconds: Int
    ) {
        self.snapshots = snapshots
        self.diagnostics = diagnostics
        self.clock = clock
        self.catalogStore = catalogStore
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

    /// Adds finished manual-refresh results to the committed snapshot through the same serial
    /// section as every other write, so a concurrent report cannot drop them.
    public func addManualResults(_ added: [ManualRefreshResult]) async throws {
        await acquire()
        defer { release() }
        let now = clock.now
        let reduced = try SnapshotReducer.reduce(
            previous: try await snapshots.load(), reports: [],
            context: try await context(now: now))
        let base = reduced.snapshot
        let results = ManualRefreshResults.retained(base.manualRefreshResults + added, now: now)
        try await snapshots.commitLocal(
            try UsageSnapshot(
                publisherID: base.publisherID, generatedAt: now,
                heartbeatSeconds: base.heartbeatSeconds, accounts: base.accounts,
                sources: base.sources,
                windows: base.windows, diagnostics: base.diagnostics,
                manualRefreshResults: results))
    }

    /// Load, reduce, and commit run one at a time: overlapping reports would otherwise reduce
    /// from the same base and the last commit would drop the other's merge.
    private func acquire() async {
        await withCheckedContinuation { gate.enterOrQueue($0) }
    }

    private func release() {
        gate.leave()
    }

    private func collect(_ reports: [SourceSnapshot]) async throws -> CollectResult {
        await acquire()
        defer { release() }
        let previous = try await snapshots.load()
        let reduced = try SnapshotReducer.reduce(
            previous: previous, reports: reports, context: try await context(now: clock.now))
        try await snapshots.commitLocal(reduced.snapshot)
        for event in reduced.snapshot.diagnostics { await diagnostics.record(event) }
        return CollectResult(snapshot: reduced.snapshot, change: reduced.change)
    }

    private func context(now: Date) async throws -> SnapshotAssemblyContext {
        let catalog = try await catalogStore.loadCatalog()
        return SnapshotAssemblyContext(
            accounts: catalog.accounts, publisherID: publisherID,
            heartbeatSeconds: heartbeatSeconds,
            now: now)
    }
}
