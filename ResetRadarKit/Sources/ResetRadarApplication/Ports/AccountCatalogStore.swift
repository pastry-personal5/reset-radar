import ResetRadarDomain

/// Owner-only account metadata. Implementations serialize updates under their storage lock.
public protocol AccountCatalogStore: Sendable {
    func loadCatalog() async throws -> AccountCatalog
    func setAlias(accountID: AccountID, alias: AccountAlias?) async throws -> AccountCatalog
}
