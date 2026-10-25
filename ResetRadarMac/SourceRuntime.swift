import ResetRadarApplication
import ResetRadarDomain

struct AccountRefreshResult: Sendable {
    let accountID: AccountID
    let receipt: ReadReceipt
}

actor SourceRuntime {
    typealias Ingest = @Sendable (SourceSnapshot) async throws -> CollectResult
    typealias DidCollect = @Sendable (CollectResult) async -> Void

    private let sources: [any UsageSource]
    private let ingest: Ingest
    private let didCollect: DidCollect
    private let notificationHook: any ResetNotificationHook
    private var listeners: [Task<Void, Never>] = []
    private var started = false

    init(
        sources: [any UsageSource], ingest: @escaping Ingest,
        notificationHook: any ResetNotificationHook = NoOpResetNotificationHook(),
        didCollect: @escaping DidCollect
    ) {
        self.sources = sources
        self.ingest = ingest
        self.notificationHook = notificationHook
        self.didCollect = didCollect
    }

    func start() async {
        guard !started else { return }
        started = true
        for source in sources {
            listeners.append(
                Task { [weak self] in
                    for await report in source.updates {
                        await self?.receive(report)
                    }
                })
        }
        await withTaskGroup(of: Void.self) { group in
            for source in sources {
                group.addTask { try? await source.start() }
            }
        }
    }

    func refresh(_ reason: RuntimeRefreshReason) async {
        _ = await refreshAccounts(accountID: nil)
    }

    func refreshAccounts(accountID: AccountID?) async -> [AccountRefreshResult] {
        guard started else { return [] }
        return await withTaskGroup(of: AccountRefreshResult.self) { group in
            for source in sources where accountID == nil || source.accountID == accountID {
                group.addTask {
                    AccountRefreshResult(
                        accountID: source.accountID, receipt: await source.refresh())
                }
            }
            var results: [AccountRefreshResult] = []
            for await result in group { results.append(result) }
            return results
        }
    }

    func updateSources() async {
        await stop()
    }

    func stop() async {
        guard started else { return }
        started = false
        for listener in listeners { listener.cancel() }
        listeners.removeAll()
        await withTaskGroup(of: Void.self) { group in
            for source in sources { group.addTask { await source.stop() } }
        }
    }

    private func receive(_ report: SourceSnapshot) async {
        guard started, let result = try? await ingest(report) else { return }
        await notificationHook.snapshotDidCommit()
        await didCollect(result)
    }
}
