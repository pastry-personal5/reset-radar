import ResetRadarDomain

public enum UpdateAccountAliasError: Error, Equatable, Sendable {
    case invalidAlias(AccountAliasError)
    case accountNotFound
}

public struct AccountAliasUpdate: Sendable, Equatable {
    public let account: AccountMetadata
    public let snapshot: UsageSnapshot?
    public let change: ChangeClass
}

/// Applies the Mac-authoritative alias and mirrors it into the encrypted local snapshot.
public actor UpdateAccountAlias {
    private let catalogStore: any AccountCatalogStore
    private let snapshots: any LocalSnapshotCommitting
    private let clock: any AppClock

    public init(
        catalogStore: any AccountCatalogStore, snapshots: any LocalSnapshotCommitting,
        clock: any AppClock
    ) {
        self.catalogStore = catalogStore
        self.snapshots = snapshots
        self.clock = clock
    }

    public func update(accountID: AccountID, input: String) async throws -> AccountAliasUpdate {
        let alias: AccountAlias?
        if input.isEmpty {
            alias = nil
        } else {
            do {
                alias = try AccountAlias(validating: input)
            } catch let error {
                throw UpdateAccountAliasError.invalidAlias(error)
            }
        }
        let catalog = try await catalogStore.setAlias(accountID: accountID, alias: alias)
        guard let account = catalog.account(id: accountID) else {
            throw UpdateAccountAliasError.accountNotFound
        }
        guard let previous = try await snapshots.load() else {
            return AccountAliasUpdate(account: account, snapshot: nil, change: .transition)
        }
        let updated = try UsageSnapshot(
            publisherID: previous.publisherID, generatedAt: clock.now,
            heartbeatSeconds: previous.heartbeatSeconds, accounts: catalog.accounts,
            sources: previous.sources, windows: previous.windows,
            diagnostics: previous.diagnostics,
            manualRefreshResults: previous.manualRefreshResults)
        try await snapshots.commitLocal(updated)
        return AccountAliasUpdate(account: account, snapshot: updated, change: .transition)
    }
}
