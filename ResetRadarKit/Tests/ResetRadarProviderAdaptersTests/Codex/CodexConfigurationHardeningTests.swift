import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarProviderAdapters
import ResetRadarTestSupport
import Testing

extension CodexConfigurationTests {
    @Test("a corrupt launch file does not block removing its account")
    func corruptLaunchFileRemoval() async throws {
        try await withConfigurationDirectory { root, executable in
            let store = ProviderAccountCatalogStore(directoryURL: root)
            let id = accountID(0xF1)
            _ = try await store.addCodexAccount(
                id: id, revision: ConfigurationPreviewRevision(),
                executable: try validation(of: executable),
                environment: environment(executable.deletingLastPathComponent().path))
            let launchFile = root.appending(path: "codex-\(id.hex).json")
            try Data(repeating: 0x20, count: 70_000).write(to: launchFile)
            try await store.removeCodexAccount(accountID: id)
            #expect(try await store.loadCatalog().accounts.isEmpty)
        }
    }

    @Test("a default label that repeats an alias is a typed conflict")
    func defaultLabelConflict() async throws {
        try await withConfigurationDirectory { root, executable in
            let store = ProviderAccountCatalogStore(directoryURL: root)
            let validated = try validation(of: executable)
            let env = environment(executable.deletingLastPathComponent().path)
            let first = accountID(0xF2)
            _ = try await store.addCodexAccount(
                id: first, revision: ConfigurationPreviewRevision(), executable: validated,
                environment: env)
            _ = try await store.setAlias(
                accountID: first, alias: try AccountAlias(validating: "Account #2"))
            await #expect(throws: ProviderAccountCatalogStoreError.labelConflict) {
                _ = try await store.addCodexAccount(
                    id: accountID(0xF3), revision: ConfigurationPreviewRevision(),
                    executable: validated, environment: env)
            }
        }
    }

    @Test("applying the same preview twice adds one account")
    func doubleApply() async throws {
        try await withConfigurationDirectory { root, executable in
            let runner = ConfigurationCommandRunner()
            let store = ProviderAccountCatalogStore(directoryURL: root)
            let context = CodexDiscoveryContext(
                explicitExecutablePath: executable.path, loginShellURL: nil,
                environment: environment(executable.deletingLastPathComponent().path),
                workingDirectoryURL: root)
            let configurator = CodexConfigurator(
                contexts: FixedCodexDiscoveryContexts([context]),
                locator: CodexExecutableLocator(runner: runner),
                metadataReader: CodexExecutableMetadataReader(runner: runner), store: store,
                identifiers: SequenceAccountIDGenerator([accountID(0xF4), accountID(0xF5)]))
            let option = try #require(try await configurator.discover().first)
            let preview = try await configurator.preview(optionID: option.id, intent: .add)
            let first = Task { try await configurator.apply(preview) }
            let second = Task { try await configurator.apply(preview) }
            let outcomes = [await first.result, await second.result]
            #expect(outcomes.filter { (try? $0.get()) != nil }.count == 1)
            #expect(try await store.loadCatalog().accounts.count == 1)
        }
    }
}
