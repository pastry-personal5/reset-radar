import Foundation
import ResetRadarApplication
import ResetRadarDomain

extension ProviderAccountCatalogStore {
    /// Creates the one Claude Code row, or returns the existing row unchanged so a reinstall after
    /// a restore keeps its number and alias.
    public func ensureClaudeCodeAccount(
        id: AccountID, revision: ConfigurationPreviewRevision
    ) throws -> AccountMetadata {
        try files.withLock {
            var index = try loadIndex()
            guard let current = index.catalog else {
                throw ProviderAccountCatalogStoreError.incompatibleCatalog
            }
            if let existing = current.accounts.first(where: { $0.product == .claudeCode }) {
                return existing
            }
            guard !index.accounts.contains(where: { $0.metadata.id == id }) else {
                throw ProviderAccountCatalogStoreError.accountAlreadyExists
            }
            let metadata = AccountMetadata(
                id: id, product: .claudeCode, number: current.smallestUnusedNumber)
            index.accounts.append(
                StoredAccountEntry(metadata: metadata, configurationRevision: revision))
            guard index.catalog != nil else {
                throw ProviderAccountCatalogStoreError.labelConflict
            }
            try saveIndex(index)
            return metadata
        }
    }

    public func removeClaudeCodeAccount(accountID: AccountID) throws {
        try files.withLock {
            var index = try loadIndex()
            guard let offset = index.accounts.firstIndex(where: { $0.metadata.id == accountID }),
                index.accounts[offset].metadata.product == .claudeCode
            else { throw ProviderAccountCatalogStoreError.accountNotFound }
            index.accounts.remove(at: offset)
            try saveIndex(index)
        }
    }
}
