import Darwin
import Foundation
import ResetRadarApplication
import ResetRadarDomain
import Testing

@testable import ResetRadarProviderAdapters

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

    @Test func everyInterruptionPointEitherCompletesOrRestoresThePriorValue() async throws {
        try await withAsyncTrustedHome { home in
            let rig = try SetupRig(home)
            let line = try writeExecutable(
                "#!/bin/sh\ncat >/dev/null\n", at: home.appending(path: "line"))
            let original = settingsJSON(command: line.path)
            try rig.write(original)
            let store = StatusLineRestoreStore(directory: rig.root.appending(path: "claude-setup"))
            // Interrupted after the restore record but before the compose record or settings.
            _ = mkdir(rig.root.appending(path: "claude-setup").path, 0o700)
            try store.save(
                StatusLineRestoreRecord(
                    prior: .command(line.path), installedCommand: rig.configurator.helperCommand,
                    transactionID: UUID(), createdAt: Date(), state: .pending))
            #expect(await rig.configurator.inspect(accountID: nil) == .notConfigured)
            try await rig.configurator.restore()
            #expect(try rig.text() == original)
            #expect(!rig.restoreFileExists && !rig.composeFileExists)
            // Interrupted after the compose record: restore removes both artifacts, settings stay.
            try store.save(
                StatusLineRestoreRecord(
                    prior: .command(line.path), installedCommand: rig.configurator.helperCommand,
                    transactionID: UUID(), createdAt: Date(), state: .pending))
            try ComposeRecordStore(rootDirectory: rig.root).save(
                ComposeRecord(executablePath: line.path)!)
            try await rig.configurator.restore()
            #expect(try rig.text() == original)
            #expect(!rig.restoreFileExists && !rig.composeFileExists)
            // A retried install after a pre-write interruption starts a fresh transaction.
            try store.save(
                StatusLineRestoreRecord(
                    prior: .command(line.path), installedCommand: rig.configurator.helperCommand,
                    transactionID: UUID(), createdAt: Date(), state: .pending))
            _ = try await rig.install()
            #expect(try store.load()?.state == .installed)
            #expect(await rig.configurator.inspect(accountID: nil) == .configured)
            try await rig.configurator.restore()
            #expect(try rig.text() == original)
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
        try await withAsyncTrustedHome { home in
            let rig = try SetupRig(home, managed: home.appending(path: "absent.json"))
            #expect(try await rig.configurator.discover().count == 1)
        }
        try await withAsyncTrustedHome { home in
            let managed = home.appending(path: "managed.json")
            try Data("{not json".utf8).write(to: managed)
            let rig = try SetupRig(home, managed: managed)
            #expect(try await rig.configurator.discover().isEmpty)
            #expect(!rig.restoreFileExists)
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
