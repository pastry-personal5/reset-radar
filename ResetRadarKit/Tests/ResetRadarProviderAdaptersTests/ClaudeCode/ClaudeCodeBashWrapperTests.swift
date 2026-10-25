import Darwin
import Foundation
import ResetRadarApplication
import ResetRadarDomain
import Testing

@testable import ResetRadarProviderAdapters

@Suite("Claude Code Bash wrapper")
struct ClaudeCodeBashWrapperTests {
    @Test func ownerBashScriptIsComposedAndOriginalCommandIsRestored() async throws {
        try await withAsyncTrustedHome { home in
            let rig = try SetupRig(home)
            let line = try writeExecutable(
                "#!/bin/bash\ncat >/dev/null\nprintf 'LINE'\n",
                at: home.appending(path: "line.sh"))
            let command = "bash $HOME/line.sh"
            let original = settingsJSON(command: command)
            try rig.write(original)
            #expect(await rig.configurator.inspect(accountID: nil) == .notConfigured)
            let preview = try #require(try await rig.configurator.discover().first)
            let prepared = try await rig.configurator.preview(optionID: preview.id, intent: .add)
            let canonical = try #require(ExecutableIdentityValidator.resolve(line.path))
            #expect(prepared.statusLine?.existingExecutablePath == canonical)
            try await rig.configurator.apply(prepared)
            #expect(await rig.configurator.inspect(accountID: nil) == .configured)
            #expect(
                try ComposeRecordStore(rootDirectory: rig.root).load()?.executablePath == canonical)
            try await rig.configurator.restore()
            #expect(try rig.text() == original)
        }
    }

    @Test func bashWrapperWithoutBashShebangIsLeftUntouched() async throws {
        try await withAsyncTrustedHome { home in
            let rig = try SetupRig(home)
            _ = try writeExecutable("#!/bin/sh\n", at: home.appending(path: "line.sh"))
            let original = settingsJSON(command: "bash $HOME/line.sh")
            try rig.write(original)
            let option = try #require(try await rig.configurator.discover().first)
            await #expect(throws: ConfigureSourcesError.unsafeExistingConfiguration) {
                try await rig.configurator.preview(optionID: option.id, intent: .add)
            }
            #expect(try rig.text() == original)
            #expect(!rig.restoreFileExists)
        }
    }

    @Test func bashWrapperWithDifferentVisibleOutputIsLeftUntouched() async throws {
        try await withAsyncTrustedHome { home in
            let bin = home.appending(path: "bin")
            #expect(mkdir(bin.path, 0o700) == 0)
            _ = try writeExecutable(
                "#!/bin/sh\nprintf 'DIFFERENT'\n", at: bin.appending(path: "bash"))
            let rig = try SetupRig(
                home, environment: ["PATH": "\(bin.path):/usr/bin:/bin", "HOME": home.path])
            _ = try writeExecutable(
                "#!/bin/bash\ncat >/dev/null\nprintf 'LINE'\n",
                at: home.appending(path: "line.sh"))
            let original = settingsJSON(command: "bash $HOME/line.sh")
            try rig.write(original)
            let option = try #require(try await rig.configurator.discover().first)
            let preview = try await rig.configurator.preview(optionID: option.id, intent: .add)
            await #expect(throws: ClaudeCodeConfiguratorError.compositionMismatch) {
                try await rig.configurator.apply(preview)
            }
            #expect(try rig.text() == original)
            #expect(!rig.restoreFileExists && !rig.composeFileExists)
        }
    }
}
