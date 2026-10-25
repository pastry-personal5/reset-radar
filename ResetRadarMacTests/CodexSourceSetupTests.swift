import Darwin
import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarProviderAdapters
import ResetRadarTestSupport
import Testing

@testable import ResetRadarMac

@Suite("Codex source setup")
struct CodexSourceSetupTests {
    @MainActor
    @Test func codexDraftRejectsInvalidAliasBeforeConfiguration() async throws {
        let source = FakeSourceConfigurator(product: .codex)
        let model = SourceSetupViewModel(
            selections: CodexDiscoverySelections(
                workingDirectory: FileManager.default.temporaryDirectory),
            configure: ConfigureSources(configurators: [source]))

        model.codexHomes = [FileManager.default.temporaryDirectory.path]
        await model.discoverCodex()
        await model.prepare(try #require(model.options.first))

        #expect(!(await model.confirmPreview(alias: "Invalid\nAlias")))
        #expect(source.applied.isEmpty)
        #expect(model.preview != nil)
    }

    @MainActor
    @Test func codexDraftSavesAliasForNewAccount() async throws {
        let id = try #require(AccountID(data: Data(repeating: 8, count: AccountID.byteCount)))
        let catalog = FakeAccountCatalogStore(
            accounts: [AccountMetadata(id: id, product: .codex, number: 1)])
        let source = FakeSourceConfigurator(product: .codex)
        let model = SourceSetupViewModel(
            selections: CodexDiscoverySelections(
                workingDirectory: FileManager.default.temporaryDirectory),
            configure: ConfigureSources(configurators: [source]), catalog: catalog)

        model.codexHomes = [FileManager.default.temporaryDirectory.path]
        await model.discoverCodex()
        await model.prepare(try #require(model.options.first))

        #expect(await model.confirmPreview(alias: "Work Mac"))
        #expect(source.applied.count == 1)
        #expect(model.configuredAccounts[0].alias?.value == "Work Mac")
    }

    @Test func codexSelectionsExposeOnlyAllowlistedEnvironment() async throws {
        let selections = CodexDiscoverySelections(
            homeDirectory: URL(fileURLWithPath: "/Users/synthetic"),
            workingDirectory: URL(fileURLWithPath: "/tmp/reset-radar"))
        await selections.update([
            .init(
                codexHome: URL(fileURLWithPath: "/Users/synthetic/.codex-a"),
                executablePath: "/opt/homebrew/bin/codex"),
            .init(
                codexHome: URL(fileURLWithPath: "/Users/synthetic/.codex-b"),
                executablePath: nil),
            .init(
                codexHome: URL(fileURLWithPath: "/Users/synthetic/.codex-ignored"),
                executablePath: nil),
        ])
        let contexts = await selections.contexts()
        let context = try #require(contexts.first)
        #expect(contexts.count == AccountCatalog.maximumCodexAccounts)
        #expect(Set(context.environment.keys) == CodexProcessLaunchConfiguration.allowedEnvironment)
        #expect(context.environment["CODEX_HOME"] == "/Users/synthetic/.codex-a")
        #expect(context.explicitExecutablePath == "/opt/homebrew/bin/codex")
        let shell = try #require(getpwuid(getuid())?.pointee.pw_shell)
        #expect(context.loginShellURL?.path == String(cString: shell))
    }

    @MainActor
    @Test func codexDiscoveryRejectsWhitespaceAndMissingHomeFolders() async {
        let source = FakeSourceConfigurator(product: .codex)
        let model = SourceSetupViewModel(
            selections: CodexDiscoverySelections(
                workingDirectory: FileManager.default.temporaryDirectory),
            configure: ConfigureSources(configurators: [source]))

        model.codexHomes = [FileManager.default.temporaryDirectory.path + " "]
        await model.discoverCodex()
        #expect(model.options.isEmpty)
        #expect(model.message?.contains("whitespace") == true)

        model.codexHomes = [
            FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path
        ]
        await model.discoverCodex()
        #expect(model.options.isEmpty)
        #expect(model.message?.contains("does not exist") == true)
    }

    @MainActor
    @Test func codexHomeReplacementPreservesTheConfiguredAccount() async throws {
        let id = try #require(AccountID(data: Data(repeating: 12, count: AccountID.byteCount)))
        let account = AccountMetadata(id: id, product: .codex, number: 1)
        let catalog = FakeAccountCatalogStore(accounts: [account])
        let source = FakeSourceConfigurator(product: .codex)
        let model = SourceSetupViewModel(
            selections: CodexDiscoverySelections(
                workingDirectory: FileManager.default.temporaryDirectory),
            configure: ConfigureSources(configurators: [source]), catalog: catalog)
        model.codexHomes = [FileManager.default.temporaryDirectory.path]

        await model.discoverCodex()
        await model.prepare(try #require(model.options.first), intent: .replace(id))
        #expect(model.preview?.intent == .replace(id))
        #expect(await model.confirmPreview())
        #expect(source.applied.first?.intent == .replace(id))
        #expect(model.configuredAccounts == [account])
    }
}
