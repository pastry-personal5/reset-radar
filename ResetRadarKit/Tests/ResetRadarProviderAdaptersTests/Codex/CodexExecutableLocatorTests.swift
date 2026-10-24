import Foundation
import ResetRadarProviderAdapters
import ResetRadarTestSupport
import Testing

private final class ScriptedLocatorRunner: CodexCommandRunning, @unchecked Sendable {
    private let commandsState = Locked<[CodexCommand]>([])
    private let result: Result<CodexCommandResult, CodexCommandError>

    init(_ result: Result<CodexCommandResult, CodexCommandError>) {
        self.result = result
    }

    var commands: [CodexCommand] { commandsState.snapshot }

    func run(_ command: CodexCommand) async throws -> CodexCommandResult {
        commandsState.withLock { $0.append(command) }
        return try result.get()
    }
}

@Suite("Codex executable locator")
struct CodexExecutableLocatorTests {
    @Test("explicit selection precedes login-shell discovery and canonical duplicates collapse")
    func discoveryOrderAndDeduplication() async throws {
        try await withDirectory { directory in
            let target = try executable(named: "codex-target", in: directory)
            let link = directory.appending(path: "codex-link")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
            let runner = ScriptedLocatorRunner(
                .success(
                    CodexCommandResult(
                        standardOutput: Data("\(target.path)\n".utf8), exitStatus: 0)))
            let results = try await CodexExecutableLocator(runner: runner).discover(
                explicitPath: link.path, loginShellURL: URL(fileURLWithPath: "/bin/zsh"),
                environment: environment(path: directory.path), workingDirectoryURL: directory)

            #expect(results.first?.executable.invocationPath == link.path)
            #expect(
                results.filter { $0.executable.executable.canonicalPath == target.path }.count == 1)
            #expect(runner.commands.first?.arguments == ["-lc", "command -v codex"])
            #expect(runner.commands.first?.maximumOutputBytes == 4_096)
            #expect(runner.commands.first?.timeout == .seconds(5))
        }
    }

    @Test("preview contains the exact allowlisted environment including optional CODEX_HOME")
    func previewEnvironment() async throws {
        try await withDirectory { directory in
            let codex = try executable(named: "codex", in: directory)
            var values = environment(path: directory.path)
            values["CODEX_HOME"] = "/private/tmp/codex-home"
            let results = try await CodexExecutableLocator(
                runner: ScriptedLocatorRunner(.failure(.launchFailed))
            ).discover(
                explicitPath: codex.path, loginShellURL: nil, environment: values,
                workingDirectoryURL: directory)
            let candidate = try #require(results.first)
            #expect(candidate.option.product == .codex)
            #expect(candidate.option.launch.executablePath == codex.path)
            #expect(
                Dictionary(
                    uniqueKeysWithValues: candidate.option.launch.environment.map {
                        ($0.key.rawValue, $0.value)
                    }) == values)
        }
    }

    @Test("multiline, relative, failed, and oversized shell results are never evaluated")
    func invalidShellOutput() async throws {
        try await withDirectory { directory in
            let codex = try executable(named: "codex", in: directory)
            for output in ["\(codex.path)\n/other\n", "relative/codex\n", "\(codex.path)\rtext\n"] {
                let runner = ScriptedLocatorRunner(
                    .success(
                        CodexCommandResult(
                            standardOutput: Data(output.utf8), exitStatus: 0)))
                let results = try await CodexExecutableLocator(runner: runner).discover(
                    explicitPath: nil, loginShellURL: URL(fileURLWithPath: "/bin/zsh"),
                    environment: environment(path: directory.path),
                    workingDirectoryURL: directory)
                #expect(!results.contains { $0.executable.invocationPath == codex.path })
            }
            let failed = try await CodexExecutableLocator(
                runner: ScriptedLocatorRunner(.failure(.timedOut))
            ).discover(
                explicitPath: nil, loginShellURL: URL(fileURLWithPath: "/bin/zsh"),
                environment: environment(path: directory.path), workingDirectoryURL: directory)
            #expect(!failed.contains { $0.executable.invocationPath == codex.path })
        }
    }

    @Test("an invalid explicit selection and unsafe environment fail instead of falling back")
    func explicitAndEnvironmentFailures() async throws {
        try await withDirectory { directory in
            let locator = CodexExecutableLocator(
                runner: ScriptedLocatorRunner(.failure(.launchFailed)))
            await #expect(throws: CodexExecutableLocatorError.invalidExplicitSelection) {
                try await locator.discover(
                    explicitPath: directory.appending(path: "missing").path,
                    loginShellURL: nil, environment: environment(path: directory.path),
                    workingDirectoryURL: directory)
            }
            await #expect(throws: CodexExecutableLocatorError.unsafeEnvironment) {
                try await locator.discover(
                    explicitPath: nil, loginShellURL: nil,
                    environment: environment(path: ":relative"),
                    workingDirectoryURL: directory)
            }
        }
    }

    private func environment(path: String) -> [String: String] {
        [
            "HOME": "/private/tmp/home", "USER": "owner", "LANG": "en_US.UTF-8", "PATH": path,
        ]
    }

    private func withDirectory(
        _ body: (URL) async throws -> Void
    ) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "reset-radar-locator-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(directory)
    }

    private func executable(named name: String, in directory: URL) throws -> URL {
        let url = directory.appending(path: name)
        try Data("native".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }
}
