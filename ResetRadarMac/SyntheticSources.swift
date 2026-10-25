import ResetRadarApplication
import ResetRadarDomain
import ResetRadarProviderAdapters

actor SyntheticCatalogStore: AccountCatalogStore {
    let catalog: AccountCatalog

    init(account: AccountMetadata) throws {
        catalog = try AccountCatalog(validating: [account])
    }

    func loadCatalog() -> AccountCatalog { catalog }
    func setAlias(accountID: AccountID, alias: AccountAlias?) throws -> AccountCatalog {
        guard accountID == catalog.accounts[0].id else {
            throw ProviderAccountCatalogStoreError.accountNotFound
        }
        return try AccountCatalog(validating: [catalog.accounts[0].replacingAlias(alias)])
    }
}

actor SyntheticUsageSource: UsageSource {
    nonisolated let accountID: AccountID
    nonisolated let product = ProductID.codex
    nonisolated let updates: AsyncStream<SourceSnapshot>
    private let continuation: AsyncStream<SourceSnapshot>.Continuation
    private let clock: any AppClock
    private var stopped = false

    init(accountID: AccountID, clock: any AppClock) {
        self.accountID = accountID
        self.clock = clock
        let pair = AsyncStream<SourceSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        updates = pair.stream
        continuation = pair.continuation
    }

    func start() async throws { _ = await refresh() }

    func refresh() -> ReadReceipt {
        let now = clock.now
        guard !stopped else { return .unavailable(sourceState: .unavailable) }
        let report = SourceSnapshot(
            source: AccountSource(
                accountID: accountID, product: .codex, kind: .codexAppServer,
                version: "synthetic", state: .reporting),
            windows: [], isCompleteReport: true)
        continuation.yield(report)
        return ReadReceipt(startedAt: now, finishedAt: now, succeeded: true, report: report)
    }

    func stop() {
        stopped = true
        continuation.finish()
    }
}
