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
    private let codexSources: [AccountID: any UsageSource]
    private let codexOrder: [AccountID]
    private let publishing: PublishSnapshot
    private let secrets: any SecretStore
    private let relay: any RelayGateway
    private let clock: any AppClock
    private var lastForcedRead: Date?

    public init(
        publisher: any PublisherStore, snapshots: any LocalSnapshotCommitting,
        collector: CollectUsage, sources: [any UsageSource], publishing: PublishSnapshot,
        secrets: any SecretStore, relay: any RelayGateway, clock: any AppClock
    ) {
        self.publisher = publisher
        self.snapshots = snapshots
        self.collector = collector
        let codex = sources.filter { $0.product == .codex }
        self.codexSources = Dictionary(
            codex.map { ($0.accountID, $0) }, uniquingKeysWith: { first, _ in first })
        self.codexOrder = codex.reduce(into: []) { order, source in
            if !order.contains(source.accountID) { order.append(source.accountID) }
        }
        self.publishing = publishing
        self.secrets = secrets
        self.relay = relay
        self.clock = clock
    }

    public func handle(pending: [PendingRefreshRequest]) async -> HandleOutcome {
        let observedAt = clock.now
        let live = pending.filter { $0.expiresAt > observedAt }
        guard !live.isEmpty, let state = try? await publisher.load() else { return .idle }
        let fresh = live.filter { state.handledRequests[$0.id] == nil }
        if !fresh.isEmpty {
            let targets = targetAccountIDs(for: fresh)
            if !targets.isEmpty, let wait = throttleDeadline(now: observedAt) {
                return .waiting(until: wait)
            }
            let outcomes = await read(targets, observedAt: observedAt)
            let results = makeResults(fresh, outcomes: outcomes, now: clock.now)
            guard await record(fresh, results: results, now: clock.now) else { return .idle }
        }
        return await publishAndAcknowledge(live)
    }

    private func throttleDeadline(now: Date) -> Date? {
        guard let last = lastForcedRead else { return nil }
        let next = last.addingTimeInterval(Self.forcedReadInterval)
        return now < next ? next : nil
    }

    private func read(
        _ accountIDs: [AccountID], observedAt: Date
    ) async -> [AccountID: ManualRefreshAccountResult.Outcome] {
        guard !accountIDs.isEmpty else { return [:] }
        lastForcedRead = clock.now
        let receipts = await withTaskGroup(of: (AccountID, ReadReceipt).self) { group in
            for accountID in accountIDs {
                guard let source = codexSources[accountID] else { continue }
                group.addTask {
                    var receipt = await source.refresh()
                    if !receipt.performedAfter(observedAt) { receipt = await source.refresh() }
                    return (accountID, receipt)
                }
            }
            var values: [AccountID: ReadReceipt] = [:]
            for await (accountID, receipt) in group { values[accountID] = receipt }
            return values
        }
        var outcomes: [AccountID: ManualRefreshAccountResult.Outcome] = [:]
        for accountID in accountIDs {
            guard let receipt = receipts[accountID] else {
                outcomes[accountID] = .accountUnavailable
                continue
            }
            if let report = receipt.report {
                do {
                    _ = try await collector.ingest(report)
                } catch {
                    outcomes[accountID] = .sourceUnavailable
                    continue
                }
            }
            outcomes[accountID] = receipt.performedSuccessfully ? .codexRead : .sourceUnavailable
        }
        return outcomes
    }

    /// Commits the results to the local snapshot, then persists the handled IDs. If the commit
    /// fails nothing is marked handled, so the requests are retried instead of being
    /// acknowledged with no result. A crash between the two steps repeats one read at worst.
    private func record(
        _ requests: [PendingRefreshRequest], results: [ManualRefreshResult], now: Date
    ) async -> Bool {
        let until = now.addingTimeInterval(Self.resultRetention)
        let ids = requests.map(\.id)
        do {
            try await collector.addManualResults(results)
            try await publisher.transact { state in
                state.handledRequests = state.handledRequests.filter { $0.value > now }
                for id in ids { state.handledRequests[id] = until }
            }
            return true
        } catch {
            return false
        }
    }

    private func targetAccountIDs(for requests: [PendingRefreshRequest]) -> [AccountID] {
        let requested = requests.reduce(into: Set<AccountID>()) { result, request in
            switch request.target {
            case .account(let accountID):
                if codexSources[accountID] != nil { result.insert(accountID) }
            case .allCodex:
                result.formUnion(codexSources.keys)
            }
        }
        return codexOrder.filter(requested.contains)
    }

    private func makeResults(
        _ requests: [PendingRefreshRequest],
        outcomes: [AccountID: ManualRefreshAccountResult.Outcome], now: Date
    ) -> [ManualRefreshResult] {
        requests.compactMap { request in
            let accountResults: [ManualRefreshAccountResult]
            switch request.target {
            case .account(let accountID):
                accountResults = [
                    ManualRefreshAccountResult(
                        accountID: accountID,
                        outcome: outcomes[accountID] ?? .accountUnavailable)
                ]
            case .allCodex:
                accountResults = codexOrder.compactMap { accountID in
                    outcomes[accountID].map {
                        ManualRefreshAccountResult(accountID: accountID, outcome: $0)
                    }
                }
            }
            return try? ManualRefreshResult(
                readerID: request.readerID, requestID: request.id, completedAt: now,
                target: request.target, accountResults: accountResults)
        }
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
