import ResetRadarDomain

public enum UpdateAccountAliasError: Error, Equatable, Sendable {
    case invalidAlias(AccountAliasError)
    case accountNotFound
    case duplicateDisplayLabel
    case localSaveFailed
    case snapshotCommitFailed
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

    public init(
        catalogStore: any AccountCatalogStore, snapshots: any LocalSnapshotCommitting,
        clock: any AppClock
    ) {
        self.catalogStore = catalogStore
        self.snapshots = snapshots
        _ = clock
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
        let catalog: AccountCatalog
        do {
            catalog = try await catalogStore.setAlias(accountID: accountID, alias: alias)
        } catch AccountCatalogError.duplicateDisplayLabel {
            throw UpdateAccountAliasError.duplicateDisplayLabel
        } catch {
            throw UpdateAccountAliasError.localSaveFailed
        }
        guard let account = catalog.account(id: accountID) else {
            throw UpdateAccountAliasError.accountNotFound
        }
        let updated: UsageSnapshot?
        do {
            updated = try await snapshots.updateAccountAlias(accountID, to: alias)
        } catch {
            throw UpdateAccountAliasError.snapshotCommitFailed
        }
        return AccountAliasUpdate(account: account, snapshot: updated, change: .metadataOnly)
    }
}
