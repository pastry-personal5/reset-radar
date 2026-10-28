import ResetRadarApplication
import ResetRadarDomain
import ResetRadarTestSupport
import Testing

@Suite("Update account alias")
struct UpdateAccountAliasTests {
    @Test("preserves spelling, commits metadata immediately, and never advances observations")
    func updatesMetadataOnly() async throws {
        let original = snapshot(windows: [window(observedAt: at(10))], generatedAt: at(20))
        let store = FakeSnapshotStore(snapshot: original)
        let catalog = FakeAccountCatalogStore(accounts: original.accounts)
        let clock = FakeAppClock(start: at(30))
        let useCase = UpdateAccountAlias(
            catalogStore: catalog, snapshots: store, clock: clock)

        let result = try await useCase.update(accountID: codexAccountID, input: "  Work ⚡ ")

        #expect(result.account.alias?.value == "  Work ⚡ ")
        #expect(result.change == .metadataOnly)
        #expect(result.snapshot?.generatedAt == at(20))
        #expect(result.snapshot?.windows.first?.observation?.observedAt == at(10))
        #expect(store.commits.last == result.snapshot)

        let collector = CollectUsage(
            snapshots: store, diagnostics: FakeDiagnosticsSink(), clock: clock,
            catalogStore: catalog, publisherID: publisher, heartbeatSeconds: 300)
        let collected = try await collector.ingest(report(windows: [window(observedAt: at(10))]))
        #expect(collected.snapshot.accounts.first?.alias?.value == "  Work ⚡ ")
    }

    @Test("empty input restores the stable default label")
    func removesAlias() async throws {
        let aliased = AccountMetadata(
            id: codexAccountID, product: .codex, number: 1,
            alias: try AccountAlias(validating: "Work"))
        let store = FakeSnapshotStore()
        let catalog = FakeAccountCatalogStore(accounts: [aliased])
        let useCase = UpdateAccountAlias(
            catalogStore: catalog, snapshots: store, clock: FakeAppClock(start: at(0)))
        let result = try await useCase.update(accountID: codexAccountID, input: "")
        #expect(result.account.alias == nil)
        #expect(result.account.effectiveDisplayLabel == "Account #1")
        #expect(result.snapshot == nil)
        #expect(result.change == .metadataOnly)
    }

    @Test("unsafe and duplicate aliases fail without a snapshot commit")
    func rejectsInvalidAliases() async throws {
        let accounts = [
            AccountMetadata(id: codexAccountID, product: .codex, number: 1),
            AccountMetadata(
                id: claudeAccountID, product: .claudeCode, number: 2,
                alias: try AccountAlias(validating: "Shared")),
        ]
        let store = FakeSnapshotStore()
        let catalog = FakeAccountCatalogStore(accounts: accounts)
        let useCase = UpdateAccountAlias(
            catalogStore: catalog, snapshots: store, clock: FakeAppClock(start: at(0)))
        await #expect(throws: UpdateAccountAliasError.invalidAlias(.noVisibleContent)) {
            try await useCase.update(accountID: codexAccountID, input: " \u{301}")
        }
        await #expect(throws: UpdateAccountAliasError.duplicateDisplayLabel) {
            try await useCase.update(accountID: codexAccountID, input: "Shared")
        }
        #expect(store.commits.isEmpty)
    }
}
