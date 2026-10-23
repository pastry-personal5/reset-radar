import Foundation
import ResetRadarDomain

/// Turns pending reader requests into one Codex read, a result-bearing publication, and then an
/// acknowledgement. It never reads Claude Code.
public actor HandleManualRefreshRequests {
    public static let forcedReadInterval: TimeInterval = 30
    public static let resultRetention: TimeInterval = ManualRefreshResults.retention

    private let publisher: any PublisherStore
    private let snapshots: any LocalSnapshotCommitting
    private let collector: CollectUsage
    private let codex: (any UsageSource)?
    private let publishing: PublishSnapshot
    private let secrets: any SecretStore
    private let relay: any RelayGateway
    private let clock: any AppClock
    private let heartbeatSeconds: Int
    private var lastForcedRead: Date?

    public init(
        publisher: any PublisherStore, snapshots: any LocalSnapshotCommitting,
        collector: CollectUsage, sources: [any UsageSource], publishing: PublishSnapshot,
        secrets: any SecretStore, relay: any RelayGateway, clock: any AppClock,
        heartbeatSeconds: Int
    ) {
        self.publisher = publisher
        self.snapshots = snapshots
        self.collector = collector
        self.codex = sources.first { $0.product == .codex }
        self.publishing = publishing
        self.secrets = secrets
        self.relay = relay
        self.clock = clock
        self.heartbeatSeconds = heartbeatSeconds
    }

    public func handle(pending: [PendingRefreshRequest]) async -> HandleOutcome {
        let observedAt = clock.now
        let live = pending.filter { $0.expiresAt > observedAt }
        guard !live.isEmpty, let state = try? await publisher.load() else { return .idle }
        let fresh = live.filter { state.handledRequests[$0.id] == nil }
        if !fresh.isEmpty {
            if let wait = throttleDeadline(now: observedAt) { return .waiting(until: wait) }
            guard let outcome = await readOnce(observedAt: observedAt) else { return .idle }
            guard await record(fresh, outcome: outcome, now: clock.now) else { return .idle }
        }
        return await publishAndAcknowledge(live)
    }

    private func throttleDeadline(now: Date) -> Date? {
        guard let last = lastForcedRead else { return nil }
        let next = last.addingTimeInterval(Self.forcedReadInterval)
        return now < next ? next : nil
    }

    /// One forced read; a second only if the first finished before the request was observed.
    private func readOnce(observedAt: Date) async -> ManualRefreshResult.Outcome? {
        guard let codex else { return nil }
        lastForcedRead = clock.now
        var receipt = await codex.refresh()
        if receipt.finishedAt < observedAt { receipt = await codex.refresh() }
        if let report = receipt.report { _ = try? await collector.ingest(report) }
        return receipt.succeeded ? .codexRead : .sourceUnavailable
    }

    /// Persists the handled IDs first, so a crash or retry never starts another read, then adds
    /// the results to the local snapshot.
    private func record(
        _ requests: [PendingRefreshRequest], outcome: ManualRefreshResult.Outcome, now: Date
    ) async -> Bool {
        let until = now.addingTimeInterval(Self.resultRetention)
        let ids = requests.map(\.id)
        do {
            try await publisher.transact { state in
                state.handledRequests = state.handledRequests.filter { $0.value > now }
                for id in ids { state.handledRequests[id] = until }
            }
            let base = try await currentSnapshot(now: now)
            let added = requests.map {
                ManualRefreshResult(
                    readerID: $0.readerID, requestID: $0.id, completedAt: now, outcome: outcome)
            }
            let results = ManualRefreshResults.retained(base.manualRefreshResults + added, now: now)
            try await snapshots.commitLocal(
                try UsageSnapshot(
                    publisherID: base.publisherID, generatedAt: now,
                    heartbeatSeconds: base.heartbeatSeconds, sources: base.sources,
                    windows: base.windows, diagnostics: base.diagnostics,
                    manualRefreshResults: results))
            return true
        } catch {
            return false
        }
    }

    private func currentSnapshot(now: Date) async throws -> UsageSnapshot {
        if let existing = try await snapshots.load() { return existing }
        let state = try await publisher.load()
        guard let publisherID = state.publisherID else { throw ManualRefreshError.notConfigured }
        return try UsageSnapshot(
            publisherID: publisherID, generatedAt: now, heartbeatSeconds: heartbeatSeconds,
            sources: [], windows: [])
    }

    private func publishAndAcknowledge(_ requests: [PendingRefreshRequest]) async -> HandleOutcome {
        guard let snapshot = try? await snapshots.load() else { return .idle }
        let outcome = await publishing.publish(snapshot, change: .transition, trigger: .change)
        guard case .published = outcome else { return .publicationFailed(outcome) }
        guard let state = try? await publisher.load(), let endpoint = state.endpoint,
            let token = try? await secrets.read(.writeToken)
        else { return .publicationFailed(.secretsUnavailable) }
        var acknowledged = 0
        for request in requests {
            let result = await relay.deleteRefreshRequest(
                request.id, endpoint: endpoint, writeToken: token)
            if result == .deleted { acknowledged += 1 }
        }
        return .handled(count: acknowledged)
    }
}

enum ManualRefreshError: Error {
    case notConfigured
}
