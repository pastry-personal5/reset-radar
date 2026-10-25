import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarProviderAdapters
import Testing

@Suite("Claude Code account row")
struct ClaudeCodeCatalogTests {
    private func id(_ byte: UInt8) -> AccountID {
        AccountID(data: Data(repeating: byte, count: 16))!
    }

    @Test func rowIsCreatedOnceWithTheSmallestUnusedNumberAndSurvivesReinstall() async throws {
        try await withAsyncTemporaryDirectory { root in
            let store = ProviderAccountCatalogStore(directoryURL: root.appending(path: "catalog"))
            let first = try await store.ensureClaudeCodeAccount(
                id: id(0xC1), revision: ConfigurationPreviewRevision())
            #expect(first.product == .claudeCode)
            #expect(first.number == 1)
            let alias = try AccountAlias(validating: "Claude")
            _ = try await store.setAlias(accountID: first.id, alias: alias)
            // A reinstall reuses the row, its number, and its alias; the new ID is ignored.
            let again = try await store.ensureClaudeCodeAccount(
                id: id(0xC2), revision: ConfigurationPreviewRevision())
            #expect(again.id == first.id)
            #expect(again.number == 1)
            #expect(again.alias == alias)
            #expect(try await store.loadCatalog().accounts.count == 1)
            #expect(try await store.loadClaudeCodeAccount() == again)
            #expect(try await store.claudeCodeConfigurationState(accountID: nil) == .configured)
            #expect(
                try await store.claudeCodeConfigurationState(accountID: again.id) == .configured)
            #expect(
                try await store.claudeCodeConfigurationState(accountID: id(0xEE))
                    == .notConfigured)
        }
    }

    @Test func removalDeletesOnlyTheClaudeRowAndFreesItsNumber() async throws {
        try await withAsyncTemporaryDirectory { root in
            let store = ProviderAccountCatalogStore(directoryURL: root.appending(path: "catalog"))
            let row = try await store.ensureClaudeCodeAccount(
                id: id(0xC1), revision: ConfigurationPreviewRevision())
            await #expect(throws: ProviderAccountCatalogStoreError.accountNotFound) {
                try await store.removeClaudeCodeAccount(accountID: id(0xEE))
            }
            try await store.removeClaudeCodeAccount(accountID: row.id)
            #expect(try await store.loadCatalog().accounts.isEmpty)
            #expect(
                try await store.claudeCodeConfigurationState(accountID: nil) == .notConfigured)
            await #expect(throws: ProviderAccountCatalogStoreError.accountNotFound) {
                try await store.loadClaudeCodeAccount()
            }
            let recreated = try await store.ensureClaudeCodeAccount(
                id: id(0xC3), revision: ConfigurationPreviewRevision())
            #expect(recreated.number == 1)
            #expect(recreated.id == id(0xC3))
        }
    }
}
