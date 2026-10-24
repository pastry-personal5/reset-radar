import Darwin
import Foundation
import ResetRadarApplication
import ResetRadarDomain
import Testing

@testable import ResetRadarProviderAdapters

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
