import Foundation
import ResetRadarProviderAdapters
import ResetRadarTestSupport
import Testing

private final class FakeCodexCommandRunner: CodexCommandRunning, @unchecked Sendable {
    private struct State {
        var commands: [CodexCommand] = []
        var result: Result<CodexCommandResult, CodexCommandError>
    }

    private let state: Locked<State>

    init(result: Result<CodexCommandResult, CodexCommandError>) {
        state = Locked(State(result: result))
    }

    var commands: [CodexCommand] { state.withLock { $0.commands } }

    func run(_ command: CodexCommand) async throws -> CodexCommandResult {
        try state.withLock {
            $0.commands.append(command)
            return try $0.result.get()
        }
    }
}

@Suite("Codex bounded command runner")
struct CodexCommandRunnerTests {
    @Test("runner uses exact arguments, environment, and working directory")
    func exactLaunch() async throws {
        try await withDirectory { directory in
            let fixture = try executable(
                named: "fixture",
                script: """
                    #!/bin/sh
                    printf '%s|%s|%s\\n' "$HOME" "${EXTRA-unset}" "$*"
                    pwd
                    """,
                in: directory)
            let command = try CodexCommand(
                executableURL: fixture, arguments: ["one", "two"],
                environment: ["HOME": "/private/tmp/owner", "PATH": "/usr/bin:/bin"],
                workingDirectoryURL: directory, timeout: .seconds(5), maximumOutputBytes: 1_024)
            let result = try await FoundationCodexCommandRunner(clock: FakeAppClock()).run(command)
            let output = try #require(String(data: result.standardOutput, encoding: .utf8))
            #expect(result.exitStatus == 0)
            #expect(output.contains("/private/tmp/owner|unset|one two"))
            #expect(output.contains(directory.path))
        }
    }

    @Test("runner enforces an injected timeout")
    func timeout() async throws {
        try await withDirectory { directory in
            let fixture = try executable(
                named: "fixture", script: "#!/bin/sh\nwhile :; do :; done\n", in: directory)
            let clock = FakeAppClock()
            let command = try CodexCommand(
                executableURL: fixture, arguments: [], environment: [:],
                workingDirectoryURL: directory, timeout: .seconds(2), maximumOutputBytes: 16)
            let task = Task {
                try await FoundationCodexCommandRunner(clock: clock).run(command)
            }
            await clock.waitForSleepers()
            clock.advance(by: 2)
            await #expect(throws: CodexCommandError.timedOut) { try await task.value }
        }
    }

    @Test("runner bounds both output streams without returning their contents")
    func outputBound() async throws {
        try await withDirectory { directory in
            let fixture = try executable(
                named: "fixture",
                script: "#!/bin/sh\nprintf '01234567890'\nprintf 'abcdefghijk' >&2\n",
                in: directory)
            let command = try CodexCommand(
                executableURL: fixture, arguments: [], environment: [:],
                workingDirectoryURL: directory, timeout: .seconds(5), maximumOutputBytes: 10)
            await #expect(throws: CodexCommandError.outputTooLarge) {
                try await FoundationCodexCommandRunner(clock: FakeAppClock()).run(command)
            }
        }
    }

    @Test("metadata accepts only the bounded public version grammar")
    func versionGrammar() {
        #expect(
            CodexExecutableMetadataReader.normalizeVersion("codex-cli 0.164.0\n") == "codex 0.164.0"
        )
        #expect(
            CodexExecutableMetadataReader.normalizeVersion("codex 1.2.3-beta.1\r\n")
                == "codex 1.2.3-beta.1")
        for rejected in [
            "codex 1.2", "codex 1.2.3\nextra", "/tmp/codex 1.2.3", "codex 1.2.3/path",
            "future 1.2.3", "codex 1.2.3 ", "codex 1.2.3-",
        ] {
            #expect(CodexExecutableMetadataReader.normalizeVersion(rejected) == nil)
        }
    }

    @Test("metadata reader uses fixed version arguments and normalizes its result")
    func metadataReader() async throws {
        try await withDirectory { directory in
            let fixture = try executable(
                named: "codex", script: "#!/usr/bin/env node\n", in: directory)
            let node = try executable(named: "node", script: "native", in: directory)
            let validated = try CodexExecutableValidator().validate(
                invocationPath: fixture.path, pathEnvironment: directory.path)
            #expect(validated.node?.canonicalPath == node.path)
            let runner = FakeCodexCommandRunner(
                result: .success(
                    CodexCommandResult(
                        standardOutput: Data("codex-cli 0.164.0\n".utf8), exitStatus: 0)))
            let result = try await CodexExecutableMetadataReader(runner: runner).read(
                executable: validated, environment: ["PATH": directory.path],
                workingDirectoryURL: directory)
            #expect(result.publicVersion == "codex 0.164.0")
            #expect(runner.commands.first?.arguments == ["--version"])
            #expect(runner.commands.first?.timeout == .seconds(5))
        }
    }

    private func withDirectory(
        _ body: (URL) async throws -> Void
    ) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "reset-radar-command-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(directory)
    }

    private func executable(named name: String, script: String, in directory: URL) throws -> URL {
        let url = directory.appending(path: name)
        try Data(script.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }
}
