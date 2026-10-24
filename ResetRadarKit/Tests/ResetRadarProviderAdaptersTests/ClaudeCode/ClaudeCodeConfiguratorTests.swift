import Darwin
import Foundation
import ResetRadarApplication
import ResetRadarDomain
import Testing

@testable import ResetRadarProviderAdapters

private struct SetupRig {
    let home: URL
    let root: URL
    let settings: URL
    let catalog: ProviderAccountCatalogStore
    let installer: StatusLineHelperInstaller
    let configurator: ClaudeCodeConfigurator

    init(
        _ home: URL, environment: [String: String] = ["PATH": "/usr/bin:/bin"],
        managed: URL? = nil, installHelper: Bool = true
    ) throws {
        self.home = home
        root = home.appending(path: "ResetRadar")
        precondition(mkdir(root.path, 0o700) == 0)
        precondition(mkdir(home.appending(path: ".claude").path, 0o700) == 0)
        settings = home.appending(path: ".claude/settings.json")
        let embedded = try writeExecutable(
            "#!/bin/sh\nprintf '\(StatusLineHelperVersion.current)\\n'\n",
            at: home.appending(path: "embedded"))
        installer = StatusLineHelperInstaller(embeddedHelper: embedded, rootDirectory: root)
        if installHelper { try installer.install() }
        catalog = ProviderAccountCatalogStore(directoryURL: root)
        let paths = ClaudeCodeConfiguratorPaths(
            homeDirectory: home, rootDirectory: root, settingsURL: settings,
            managedSettingsURL: managed, environment: environment)
        configurator = ClaudeCodeConfigurator(paths: paths, installer: installer, catalog: catalog)
    }

    func write(_ text: String) throws {
        try Data(text.utf8).write(to: settings)
        precondition(chmod(settings.path, 0o600) == 0)
    }

    func text() throws -> String { try String(contentsOf: settings, encoding: .utf8) }

    func install() async throws -> ConfigurationPreview {
        let option = try #require(try await configurator.discover().first)
        let preview = try await configurator.preview(optionID: option.id, intent: .add)
        try await configurator.apply(preview)
        return preview
    }

    var restoreFileExists: Bool {
        FileManager.default.fileExists(
            atPath: root.appending(path: "claude-setup/\(StatusLineRestoreRecord.fileName)").path)
    }
    var composeFileExists: Bool {
        FileManager.default.fileExists(atPath: root.appending(path: ComposeRecord.fileName).path)
    }
}

@Suite("Claude Code configurator")
struct ClaudeCodeConfiguratorTests {
    @Test func absentSettingInstallsRestoresAndReinstallsKeepingTheRow() async throws {
        try await withAsyncTrustedHome { home in
            let rig = try SetupRig(home)
            #expect(await rig.configurator.inspect(accountID: nil) == .notConfigured)
            let option = try #require(try await rig.configurator.discover().first)
            #expect(option.launch.executablePath == rig.installer.installedURL.path)
            let preview = try await rig.configurator.preview(optionID: option.id, intent: .add)
            let detail = try #require(preview.statusLine)
            #expect(detail.changeKind == .add)
            #expect(detail.settingsPath == rig.settings.path)
            #expect(detail.helperPath == rig.installer.installedURL.path)
            #expect(detail.existingExecutablePath == nil)
            try await rig.configurator.apply(preview)
            let installed = try rig.text()
            #expect(installed.contains(rig.installer.installedURL.path))
            #expect(await rig.configurator.inspect(accountID: nil) == .configured)
            #expect(!rig.composeFileExists)
            let row = try #require(try await rig.catalog.loadCatalog().accounts.first)
            #expect(row.product == .claudeCode)
            // Reapplying after install is refused as already configured.
            await #expect(throws: ClaudeCodeConfiguratorError.alreadyConfigured) {
                try await rig.configurator.preview(optionID: option.id, intent: .add)
            }
            try await rig.configurator.restore()
            #expect(
                try ClaudeCodeSettingsEditor.snapshot(of: Data(try rig.text().utf8)).statusLine
                    == .absent)
            #expect(!rig.restoreFileExists)
            #expect(await rig.configurator.inspect(accountID: nil) == .notConfigured)
            #expect(try await rig.catalog.loadCatalog().accounts == [row])
            // Reinstall reuses the row, its number, and its alias.
            let alias = try AccountAlias(validating: "Mine")
            _ = try await rig.catalog.setAlias(accountID: row.id, alias: alias)
            _ = try await rig.install()
            let again = try #require(try await rig.catalog.loadCatalog().accounts.first)
            #expect(again.id == row.id && again.number == row.number && again.alias == alias)
        }
    }

    @Test func existingCommandIsComposedAndRestoredByteForByte() async throws {
        try await withAsyncTrustedHome { home in
            let rig = try SetupRig(home)
            let line = try writeExecutable(
                "#!/bin/sh\ncat >/dev/null\nprintf 'LINE'\n", at: home.appending(path: "line"))
            let original = """
                {"theme": "dark",\t"statusLine": {"type": "command", "command": "\(line.path)",
                  "padding": 3, "refreshInterval": 9}, "n": 1e400}
                """
            try rig.write(original)
            #expect(await rig.configurator.inspect(accountID: nil) == .notConfigured)
            let option = try #require(try await rig.configurator.discover().first)
            let preview = try await rig.configurator.preview(optionID: option.id, intent: .add)
            let detail = try #require(preview.statusLine)
            #expect(detail.changeKind == .replaceCommand)
            #expect(detail.existingExecutablePath == ExecutableIdentityValidator.resolve(line.path))
            try await rig.configurator.apply(preview)
            let installed = try rig.text()
            #expect(installed.contains("\"padding\": 3, \"refreshInterval\": 9}, \"n\": 1e400}"))
            #expect(rig.composeFileExists)
            #expect(await rig.configurator.inspect(accountID: nil) == .configured)
            let compose = try ComposeRecordStore(rootDirectory: rig.root).load()
            #expect(compose?.executablePath == ExecutableIdentityValidator.resolve(line.path))
            try await rig.configurator.restore()
            #expect(try rig.text() == original)
            #expect(!rig.composeFileExists && !rig.restoreFileExists)
        }
    }

    @Test func unsafeOrUnprovableCommandsChangeNothing() async throws {
        try await withAsyncTrustedHome { home in
            let rig = try SetupRig(home)
            let line = try writeExecutable("#!/bin/sh\n", at: home.appending(path: "line"))
            let cases = [
                "{\"statusLine\":{\"type\":\"command\",\"command\":\"\(line.path) --flag\"}}",
                "{\"statusLine\":{\"type\":\"command\",\"command\":\"TOKEN=abc \(line.path)\"}}",
                "{\"statusLine\":{\"type\":\"command\",\"command\":\"/usr/bin/true\"}}",
                "{\"statusLine\":{\"type\":\"command\",\"command\":\"\(home.path)/missing\"}}",
                "{\"statusLine\":\"string form\"}",
                settingsJSON(command: "~\(line.lastPathComponent)"),
            ]
            for original in cases {
                try rig.write(original)
                #expect(await rig.configurator.inspect(accountID: nil) == .unsafe, "\(original)")
                let option = try #require(try await rig.configurator.discover().first)
                await #expect(throws: ConfigureSourcesError.unsafeExistingConfiguration) {
                    try await rig.configurator.preview(optionID: option.id, intent: .add)
                }
                #expect(try rig.text() == original)
                #expect(!rig.restoreFileExists && !rig.composeFileExists)
            }
            #expect(try await rig.catalog.loadCatalog().accounts.isEmpty)
        }
    }

    @Test func aChangedSettingsFileOrExecutableNeedsAFreshPreview() async throws {
        try await withAsyncTrustedHome { home in
            let rig = try SetupRig(home)
            let line = try writeExecutable(
                "#!/bin/sh\ncat >/dev/null\n", at: home.appending(path: "line"))
            let original = "{\"statusLine\":{\"type\":\"command\",\"command\":\"\(line.path)\"}}"
            try rig.write(original)
            let option = try #require(try await rig.configurator.discover().first)
            var preview = try await rig.configurator.preview(optionID: option.id, intent: .add)
            let changed = original.replacingOccurrences(of: "}}", with: "},\"extra\":1}")
            try rig.write(changed)
            await #expect(throws: ClaudeCodeConfiguratorError.stalePreview) {
                try await rig.configurator.apply(preview)
            }
            #expect(try rig.text() == changed)
            #expect(!rig.restoreFileExists && !rig.composeFileExists)
            // The same preview cannot be reused.
            await #expect(throws: ClaudeCodeConfiguratorError.stalePreview) {
                try await rig.configurator.apply(preview)
            }
            preview = try await rig.configurator.preview(optionID: option.id, intent: .add)
            try Data("#!/bin/sh\ncat >/dev/null\nprintf swapped\n".utf8).write(to: line)
            await #expect(throws: ClaudeCodeConfiguratorError.stalePreview) {
                try await rig.configurator.apply(preview)
            }
            #expect(try rig.text() == changed)
            #expect(!rig.restoreFileExists && !rig.composeFileExists)
        }
    }

    @Test func aCommandWhoseOutputDiffersWhenComposedIsRefused() async throws {
        try await withAsyncTrustedHome { home in
            let rig = try SetupRig(home)
            let counter = home.appending(path: "counter")
            try Data().write(to: counter)
            // Appends a byte per run and prints the running size: the two runs cannot match.
            let line = try writeExecutable(
                "#!/bin/sh\ncat >/dev/null\nprintf x >> '\(counter.path)'\n"
                    + "wc -c < '\(counter.path)'\n",
                at: home.appending(path: "line"))
            let original = "{\"statusLine\":{\"type\":\"command\",\"command\":\"\(line.path)\"}}"
            try rig.write(original)
            let option = try #require(try await rig.configurator.discover().first)
            let preview = try await rig.configurator.preview(optionID: option.id, intent: .add)
            await #expect(throws: ClaudeCodeConfiguratorError.compositionMismatch) {
                try await rig.configurator.apply(preview)
            }
            #expect(try rig.text() == original)
            #expect(!rig.restoreFileExists && !rig.composeFileExists)
            #expect(try await rig.catalog.loadCatalog().accounts.isEmpty)
        }
    }

    @Test func aTimedOutCommandIsRefusedAndNothingIsWritten() async throws {
        try await withAsyncTrustedHome { home in
            let rig = try SetupRig(home)
            let line = try writeExecutable(
                "#!/bin/sh\nexec sleep 30\n", at: home.appending(path: "line"))
            let original = "{\"statusLine\":{\"type\":\"command\",\"command\":\"\(line.path)\"}}"
            try rig.write(original)
            let check = SyntheticCompositionCheck(
                validator: ExecutableIdentityValidator(homeDirectory: home), homeDirectory: home,
                environment: ["PATH": "/usr/bin:/bin"], timeout: 0.3)
            #expect(throws: SyntheticCompositionError.timedOut) {
                try check.verify(executablePath: ExecutableIdentityValidator.resolve(line.path)!)
            }
            let loud = try writeExecutable(
                "#!/bin/sh\ncat >/dev/null\nhead -c 70000 /dev/zero | tr '\\0' o\n",
                at: home.appending(path: "loud"))
            #expect(throws: SyntheticCompositionError.outputTooLarge) {
                try SyntheticCompositionCheck(
                    validator: ExecutableIdentityValidator(homeDirectory: home),
                    homeDirectory: home, environment: ["PATH": "/usr/bin:/bin"]
                ).verify(executablePath: ExecutableIdentityValidator.resolve(loud.path)!)
            }
            #expect(try rig.text() == original)
        }
    }
}

@Suite("Claude Code configurator restore and guards")
struct ClaudeCodeConfiguratorRestoreTests {
    @Test func restoreRefusesAConflictingEditAndKeepsSiblingEdits() async throws {
        try await withAsyncTrustedHome { home in
            let rig = try SetupRig(home)
            let line = try writeExecutable(
                "#!/bin/sh\ncat >/dev/null\n", at: home.appending(path: "line"))
            try rig.write(
                "{\"statusLine\":{\"type\":\"command\",\"command\":\"\(line.path)\",\"padding\":1}}"
            )
            _ = try await rig.install()
            // A later sibling edit and unrelated change survive a restore.
            try rig.write(
                try rig.text().replacingOccurrences(
                    of: "\"padding\":1", with: "\"padding\":7,\"x\":2"))
            try await rig.configurator.restore()
            let restored = settingsJSON(command: line.path, extra: ",\"padding\":7,\"x\":2")
            #expect(try rig.text() == restored)
            _ = try await rig.install()
            // The owner replaced the command afterwards: a conflict, nothing changed.
            let theirs = try rig.text().replacingOccurrences(
                of: rig.installer.installedURL.path, with: "/Users/o/their-command")
            try rig.write(theirs)
            await #expect(throws: SourceConfigurationError.restoreConflict) {
                try await rig.configurator.restore()
            }
            #expect(try rig.text() == theirs)
            #expect(rig.restoreFileExists && rig.composeFileExists)
        }
    }

    @Test func absentPriorRestoreRequiresTheExactMinimalObject() async throws {
        try await withAsyncTrustedHome { home in
            let rig = try SetupRig(home)
            try rig.write("{\"a\":1}")
            _ = try await rig.install()
            let extended = try rig.text().replacingOccurrences(
                of: "\"command\":", with: "\"padding\": 1, \"command\":")
            try rig.write(extended)
            await #expect(throws: SourceConfigurationError.restoreConflict) {
                try await rig.configurator.restore()
            }
            #expect(try rig.text() == extended)
            #expect(rig.restoreFileExists)
        }
    }

    @Test func removalIsRefusedWhileInstalledThenDeletesTheRow() async throws {
        try await withAsyncTrustedHome { home in
            let rig = try SetupRig(home)
            _ = try await rig.install()
            let row = try #require(try await rig.catalog.loadCatalog().accounts.first)
            let before = try rig.text()
            await #expect(throws: SourceConfigurationError.installationActive) {
                try await rig.configurator.remove(accountID: row.id)
            }
            #expect(try rig.text() == before)
            try await rig.configurator.restore()
            try await rig.configurator.remove(accountID: row.id)
            #expect(try await rig.catalog.loadCatalog().accounts.isEmpty)
        }
    }

    @Test func aRetryCompletesAnInterruptedInstallOrDropsStaleArtifacts() async throws {
        try await withAsyncTrustedHome { home in
            let rig = try SetupRig(home)
            let option = try #require(try await rig.configurator.discover().first)
            _ = option
            // Interrupted after the settings write: pending record plus our command in place.
            _ = try await rig.install()
            let store = StatusLineRestoreStore(directory: rig.root.appending(path: "claude-setup"))
            var record = try #require(try store.load())
            record.state = .pending
            try store.save(record)
            #expect(await rig.configurator.inspect(accountID: nil) == .incompatible)
            let option2 = try #require(try await rig.configurator.discover().first)
            let preview = try await rig.configurator.preview(optionID: option2.id, intent: .add)
            try await rig.configurator.apply(preview)
            #expect(try store.load()?.state == .installed)
            #expect(await rig.configurator.inspect(accountID: nil) == .configured)
            // A restore still returns the prior (absent) state exactly.
            try await rig.configurator.restore()
            #expect(
                try ClaudeCodeSettingsEditor.snapshot(of: Data(try rig.text().utf8)).statusLine
                    == .absent)
        }
    }

    @Test func relocatedRootAndManagedOverridesAreReportedUnavailable() async throws {
        try await withAsyncTrustedHome { home in
            let custom = try SetupRig(
                home, environment: ["PATH": "/usr/bin:/bin", "CLAUDE_CONFIG_DIR": "/Users/o/alt"])
            #expect(try await custom.configurator.discover().isEmpty)
            #expect(await custom.configurator.inspect(accountID: nil) == .incompatible)
        }
        try await withAsyncTrustedHome { home in
            let managed = home.appending(path: "managed.json")
            try Data("{\"statusLine\":{\"type\":\"command\",\"command\":\"/m\"}}".utf8).write(
                to: managed)
            let rig = try SetupRig(home, managed: managed)
            #expect(try await rig.configurator.discover().isEmpty)
            #expect(!rig.restoreFileExists)
            #expect(!FileManager.default.fileExists(atPath: rig.settings.path))
        }
        try await withAsyncTrustedHome { home in
            let managed = home.appending(path: "managed.json")
            try Data("{\"theme\":\"dark\"}".utf8).write(to: managed)
            let rig = try SetupRig(home, managed: managed)
            #expect(try await rig.configurator.discover().count == 1)
        }
    }

    @Test func aMissingOrMismatchedHelperBlocksPreviewAndReplaceIsNotOffered() async throws {
        try await withAsyncTrustedHome { home in
            let rig = try SetupRig(home, installHelper: false)
            let option = try #require(try await rig.configurator.discover().first)
            await #expect(throws: ClaudeCodeConfiguratorError.helperNotCurrent) {
                try await rig.configurator.preview(optionID: option.id, intent: .add)
            }
            try rig.installer.install()
            await #expect(throws: ClaudeCodeConfiguratorError.invalidIntent) {
                try await rig.configurator.preview(
                    optionID: option.id,
                    intent: .replace(AccountID(data: Data(repeating: 1, count: 16))!))
            }
            await #expect(throws: ClaudeCodeConfiguratorError.unknownOption) {
                try await rig.configurator.preview(optionID: ConfigurationOptionID(), intent: .add)
            }
            try Data("#!/bin/sh\nprintf stale\n".utf8).write(to: rig.installer.installedURL)
            await #expect(throws: ClaudeCodeConfiguratorError.helperNotCurrent) {
                try await rig.configurator.preview(optionID: option.id, intent: .add)
            }
        }
    }

    @Test func restoreRecordsHoldNoSiblingFieldOrSettingsContent() async throws {
        try await withAsyncTrustedHome { home in
            let rig = try SetupRig(home)
            let line = try writeExecutable(
                "#!/bin/sh\ncat >/dev/null\n", at: home.appending(path: "line"))
            try rig.write(
                "{\"env\":{\"API_KEY\":\"SENTINEL-secret\"},\"statusLine\":"
                    + "{\"type\":\"command\",\"command\":\"\(line.path)\",\"padding\":424242}}"
            )
            _ = try await rig.install()
            for name in [StatusLineRestoreRecord.fileName, "../\(ComposeRecord.fileName)"] {
                let url = rig.root.appending(path: "claude-setup/\(name)")
                let text = try String(contentsOf: url, encoding: .utf8)
                #expect(!text.contains("SENTINEL"))
                #expect(!text.contains("API_KEY"))
                #expect(!text.contains("424242"))
            }
        }
    }
}
