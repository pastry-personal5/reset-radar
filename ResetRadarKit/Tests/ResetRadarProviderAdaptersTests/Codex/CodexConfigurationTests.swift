import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarProviderAdapters
import ResetRadarTestSupport
import Testing

final class ConfigurationCommandRunner: CodexCommandRunning, @unchecked Sendable {
    private let commandsState = Locked<[CodexCommand]>([])
    var commands: [CodexCommand] { commandsState.snapshot }

    func run(_ command: CodexCommand) async throws -> CodexCommandResult {
        commandsState.withLock { $0.append(command) }
        return CodexCommandResult(
            standardOutput: Data("codex 0.164.0\n".utf8), exitStatus: 0)
    }
}

final class SequenceAccountIDGenerator: CodexAccountIDGenerating, @unchecked Sendable {
    private let values: Locked<[AccountID]>

    init(_ values: [AccountID]) {
        self.values = Locked(values)
    }

    func makeAccountID() throws -> AccountID {
        try values.withLock { values in
            guard !values.isEmpty else {
                throw CodexConfiguratorError.accountIDGenerationFailed
            }
            return values.removeFirst()
        }
    }
}

@Suite("Codex owner-only configuration")
struct CodexConfigurationTests {
    @Test("catalog keeps stable identity and reuses a removed smallest number")
    func catalogIdentityAndNumbering() async throws {
        try await withConfigurationDirectory { root, executable in
            let store = ProviderAccountCatalogStore(directoryURL: root)
            let validated = try validation(of: executable)
            let first = accountID(0xA1)
            let second = accountID(0xA2)
            let replacement = ConfigurationPreviewRevision()
            _ = try await store.addCodexAccount(
                id: first, revision: ConfigurationPreviewRevision(), executable: validated,
                environment: environment(executable.deletingLastPathComponent().path))
            _ = try await store.addCodexAccount(
                id: second, revision: ConfigurationPreviewRevision(), executable: validated,
                environment: environment(executable.deletingLastPathComponent().path))
            let alias = try AccountAlias(validating: " Work ")
            _ = try await store.setAlias(accountID: second, alias: alias)

            let before = try await store.loadCatalog().account(id: second)
            _ = try await store.replaceCodexAccount(
                id: second, revision: replacement, executable: validated,
                environment: environment(executable.deletingLastPathComponent().path))
            let after = try await store.loadCatalog().account(id: second)
            #expect(before == after)
            #expect(after?.number == 2)
            #expect(after?.alias == alias)

            try await store.removeCodexAccount(accountID: first)
            let third = accountID(0xA3)
            let added = try await store.addCodexAccount(
                id: third, revision: ConfigurationPreviewRevision(), executable: validated,
                environment: environment(executable.deletingLastPathComponent().path))
            #expect(added.number == 1)
        }
    }

    @Test("one corrupt launch record is incompatible without hiding its sibling")
    func corruptConfigurationIsolation() async throws {
        try await withConfigurationDirectory { root, executable in
            let store = ProviderAccountCatalogStore(directoryURL: root)
            let validated = try validation(of: executable)
            let first = accountID(0xB1)
            let second = accountID(0xB2)
            for id in [first, second] {
                _ = try await store.addCodexAccount(
                    id: id, revision: ConfigurationPreviewRevision(), executable: validated,
                    environment: environment(executable.deletingLastPathComponent().path))
            }
            let corrupt = root.appending(path: "codex-\(first.hex).json")
            try Data("{}".utf8).write(to: corrupt)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: corrupt.path)

            #expect(try await store.configurationState(accountID: first) == .incompatible)
            #expect(try await store.configurationState(accountID: second) == .configured)
            #expect(try await store.loadCodexConfiguration(accountID: second).accountID == second)
        }
    }

    @Test("store enforces owner-only directory and file modes and rejects symlinked state")
    func permissionsAndSymlinks() async throws {
        try await withConfigurationDirectory { root, executable in
            let store = ProviderAccountCatalogStore(directoryURL: root)
            let id = accountID(0xB3)
            _ = try await store.addCodexAccount(
                id: id, revision: ConfigurationPreviewRevision(),
                executable: try validation(of: executable),
                environment: environment(executable.deletingLastPathComponent().path))
            let rootAttributes = try FileManager.default.attributesOfItem(atPath: root.path)
            #expect((rootAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
            for name in try FileManager.default.contentsOfDirectory(atPath: root.path) {
                let attributes = try FileManager.default.attributesOfItem(
                    atPath: root.appending(path: name).path)
                #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
            }
        }

        let parent = FileManager.default.temporaryDirectory.appending(
            path: "reset-radar-symlink-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = parent.appending(path: "configuration", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: root.path)
        let target = parent.appending(path: "outside.json")
        try Data("{}".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(
            at: root.appending(path: "accounts.json"), withDestinationURL: target)
        let store = ProviderAccountCatalogStore(directoryURL: root)
        await #expect(throws: ProviderAccountCatalogStoreError.unsafeLocation) {
            _ = try await store.loadCatalog()
        }
    }

    @Test("configurator applies only its unchanged revalidated preview")
    func previewAndApply() async throws {
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
                identifiers: SequenceAccountIDGenerator([accountID(0xC1)]))
            let option = try #require(try await configurator.discover().first)
            let preview = try await configurator.preview(optionID: option.id, intent: .add)
            let altered = ConfigurationPreview(
                product: preview.product, optionID: preview.optionID,
                revision: preview.revision, intent: preview.intent,
                launch: ConfigurationLaunchPreview(
                    executablePath: "/substituted", environment: preview.launch.environment))
            await #expect(throws: CodexConfiguratorError.stalePreview) {
                try await configurator.apply(altered)
            }
            try await configurator.apply(preview)
            let account = try #require(try await store.loadCatalog().accounts.first)
            #expect(await configurator.inspect(accountID: account.id) == .configured)
            let stored = try await store.loadCodexConfiguration(accountID: account.id)
            #expect(stored.environment == environment(executable.deletingLastPathComponent().path))
            #expect(runner.commands.allSatisfy { $0.arguments == ["--version"] })
        }
    }

    @Test("an upgraded but still safe executable stays configured")
    func upgradeStaysConfigured() async throws {
        try await withConfigurationDirectory { root, executable in
            let runner = ConfigurationCommandRunner()
            let store = ProviderAccountCatalogStore(directoryURL: root)
            let id = accountID(0xE1)
            _ = try await store.addCodexAccount(
                id: id, revision: ConfigurationPreviewRevision(),
                executable: try validation(of: executable),
                environment: environment(executable.deletingLastPathComponent().path))
            let context = CodexDiscoveryContext(
                explicitExecutablePath: executable.path, loginShellURL: nil,
                environment: environment(executable.deletingLastPathComponent().path),
                workingDirectoryURL: root)
            let configurator = CodexConfigurator(
                contexts: FixedCodexDiscoveryContexts([context]),
                locator: CodexExecutableLocator(runner: runner),
                metadataReader: CodexExecutableMetadataReader(runner: runner), store: store)
            try Data("upgraded-native".utf8).write(to: executable)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: executable.path)
            #expect(await configurator.inspect(accountID: id) == .configured)
            try FileManager.default.removeItem(at: executable)
            #expect(await configurator.inspect(accountID: id) == .incompatible)
        }
    }

    @Test("changed executable and a third Codex account fail closed")
    func driftAndCap() async throws {
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
                identifiers: SequenceAccountIDGenerator([accountID(0xD1), accountID(0xD2)]))
            let option = try #require(try await configurator.discover().first)
            let stale = try await configurator.preview(optionID: option.id, intent: .add)
            try Data("changed-native".utf8).write(to: executable)
            await #expect(throws: CodexConfiguratorError.executableChanged) {
                try await configurator.apply(stale)
            }
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: executable.path)

            for _ in 0..<2 {
                let rediscovered = try #require(try await configurator.discover().first)
                let preview = try await configurator.preview(
                    optionID: rediscovered.id, intent: .add)
                try await configurator.apply(preview)
            }
            let third = try #require(try await configurator.discover().first)
            await #expect(throws: CodexConfiguratorError.accountLimitReached) {
                _ = try await configurator.preview(optionID: third.id, intent: .add)
            }
        }
    }

    func validation(of executable: URL) throws -> CodexValidatedExecutable {
        try CodexExecutableValidator().validate(
            invocationPath: executable.path,
            pathEnvironment: executable.deletingLastPathComponent().path)
    }

    func environment(_ path: String) -> [String: String] {
        [
            "HOME": "/private/tmp/reset-radar-home", "USER": "owner",
            "LANG": "en_US.UTF-8", "PATH": path,
        ]
    }

    func accountID(_ byte: UInt8) -> AccountID {
        AccountID(data: Data(repeating: byte, count: AccountID.byteCount))!
    }

    func withConfigurationDirectory(
        _ body: (URL, URL) async throws -> Void
    ) async throws {
        let parent = FileManager.default.temporaryDirectory.appending(
            path: "reset-radar-configuration-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: parent) }
        let executable = parent.appending(path: "codex")
        try Data("native".utf8).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let root = parent.appending(path: "configuration", directoryHint: .isDirectory)
        try await body(root, executable)
    }
}
