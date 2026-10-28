import Foundation
import ResetRadarDomain
import Testing

@Suite("Account catalog")
struct AccountCatalogTests {
    @Test("aliases enforce the safe Unicode profile and preserve accepted spelling")
    func aliases() throws {
        #expect(try AccountAlias(validating: "  Team ① ⚡ ").value == "  Team ① ⚡ ")
        #expect(try AccountAlias(validating: "e\u{301}").value == "e\u{301}")
        #expect(throws: AccountAliasError.empty) { try AccountAlias(validating: "") }
        #expect(throws: AccountAliasError.noVisibleContent) {
            try AccountAlias(validating: " \u{301}")
        }
        #expect(throws: AccountAliasError.unsafeScalar) {
            try AccountAlias(validating: "name\u{00a0}")
        }
        #expect(throws: AccountAliasError.unsafeScalar) {
            try AccountAlias(validating: "name\u{200d}")
        }
        #expect(
            try AccountAlias(validating: String(repeating: "a", count: 32)).value.utf8.count == 32)
        #expect(throws: AccountAliasError.tooLong) {
            try AccountAlias(validating: String(repeating: "a", count: 33))
        }
    }

    @Test("label uniqueness compares exact scalars, not canonical equivalents")
    func exactLabels() throws {
        let composed = metadata(
            byte: 1, product: .codex, number: 1, alias: try AccountAlias(validating: "\u{e9}"))
        let decomposed = metadata(
            byte: 2, product: .claudeCode, number: 2,
            alias: try AccountAlias(validating: "e\u{301}"))
        _ = try AccountCatalog(validating: [composed, decomposed])
    }

    @Test("catalog enforces identity, numbering, labels, and the Claude Code product cap")
    func invariants() throws {
        let first = metadata(byte: 1, product: .codex, number: 1)
        let second = metadata(byte: 2, product: .codex, number: 3)
        let claude = metadata(byte: 3, product: .claudeCode, number: 4)
        let third = metadata(byte: 4, product: .codex, number: 5)
        let catalog = try AccountCatalog(validating: [first, second, claude, third])
        #expect(catalog.smallestUnusedNumber == 2)
        #expect(catalog.account(id: first.id) == first)
        #expect(catalog.accounts.filter { $0.product == .codex }.count == 3)

        #expect(throws: AccountCatalogError.duplicateID) {
            try AccountCatalog(
                validating: [first, metadata(byte: 1, product: .claudeCode, number: 2)])
        }
        #expect(throws: AccountCatalogError.duplicateNumber) {
            try AccountCatalog(
                validating: [first, metadata(byte: 2, product: .claudeCode, number: 1)])
        }
        #expect(throws: AccountCatalogError.duplicateDisplayLabel) {
            try AccountCatalog(
                validating: [
                    first.replacingAlias(try AccountAlias(validating: "shared")),
                    metadata(
                        byte: 2, product: .claudeCode, number: 2,
                        alias: try AccountAlias(validating: "shared")),
                ])
        }
        #expect(throws: AccountCatalogError.tooManyClaudeCodeAccounts) {
            try AccountCatalog(
                validating: [
                    claude, metadata(byte: 5, product: .claudeCode, number: 6),
                ])
        }
    }

    @Test("account window durations are exact")
    func accountWindows() {
        #expect(AccountWindow.StandardWindow.fiveHour.durationMinutes == 300)
        #expect(AccountWindow.StandardWindow.weekly.durationMinutes == 10_080)
    }

    private func metadata(
        byte: UInt8, product: ProductID, number: Int, alias: AccountAlias? = nil
    ) -> AccountMetadata {
        AccountMetadata(
            id: AccountID(data: Data(repeating: byte, count: AccountID.byteCount))!,
            product: product,
            number: number,
            alias: alias)
    }
}
