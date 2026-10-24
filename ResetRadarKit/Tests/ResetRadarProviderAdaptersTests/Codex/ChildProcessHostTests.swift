import Foundation
import ResetRadarProviderAdapters
import Testing

@Suite("Codex child process host")
struct ChildProcessHostTests {
    private let executable = URL(fileURLWithPath: "/usr/bin/true")
    private let workingDirectory = URL(fileURLWithPath: "/private/tmp/reset-radar-tests")

    @Test("launch configuration admits only the complete minimal environment")
    func launchEnvironmentValidation() throws {
        let valid = environment()
        _ = try CodexProcessLaunchConfiguration(
            executableURL: executable, environment: valid,
            workingDirectoryURL: workingDirectory)

        for invalid in [
            removing("HOME", from: valid),
            replacing("HOME", with: "relative", in: valid),
            replacing("PATH", with: ":/usr/bin", in: valid),
            replacing("PATH", with: "/usr/bin:relative", in: valid),
            replacing("PATH", with: "/usr/bin:", in: valid),
            replacing("EXTRA", with: "ambient", in: valid),
            replacing("CODEX_HOME", with: "relative", in: valid),
        ] {
            #expect(throws: ChildProcessHostError.unsafeLaunchConfiguration) {
                try CodexProcessLaunchConfiguration(
                    executableURL: executable, environment: invalid,
                    workingDirectoryURL: workingDirectory)
            }
        }
    }

    @Test("host launches directly with fixed arguments, exact environment, and fixed directory")
    func directLaunch() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "reset-radar-child-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = directory.appending(path: "fixture")
        let script = """
            #!/bin/sh
            printf '%s\\n' "$*"
            printf '%s|%s|%s|%s|%s\\n' "$HOME" "$USER" "$LANG" "$PATH" "${CODEX_HOME-unset}"
            printf '%s\\n' "${RESET_RADAR_SENTINEL-unset}"
            while IFS= read -r line; do printf '%s\\n' "$line"; done
            """
        try Data(script.utf8).write(to: fixture)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: fixture.path)
        var launchEnvironment = environment()
        launchEnvironment["HOME"] = "/private/tmp/owner-home"
        launchEnvironment["CODEX_HOME"] = "/private/tmp/codex-home"
        let configuration = try CodexProcessLaunchConfiguration(
            executableURL: fixture, environment: launchEnvironment,
            workingDirectoryURL: directory)
        let session = try ChildProcessHost(appWorkingDirectoryURL: directory).launch(configuration)

        try await session.write(Data("echoed-line\n".utf8))
        session.closeStandardInput()
        var output = Data()
        for await chunk in session.stdoutChunks { output.append(chunk) }
        let text = try #require(String(data: output, encoding: .utf8))
        #expect(text.contains(ChildProcessHost.arguments.joined(separator: " ")))
        #expect(
            text.contains(
                "/private/tmp/owner-home|owner|en_US.UTF-8|/usr/bin:/bin|/private/tmp/codex-home"))
        #expect(text.contains("unset\nechoed-line\n"))
    }

    @Test("host refuses a directory other than the configured app-owned directory")
    func fixedDirectory() throws {
        let configuration = try CodexProcessLaunchConfiguration(
            executableURL: executable, environment: environment(),
            workingDirectoryURL: URL(fileURLWithPath: "/private/tmp/other"))
        #expect(throws: ChildProcessHostError.unsafeLaunchConfiguration) {
            try ChildProcessHost(appWorkingDirectoryURL: workingDirectory).launch(configuration)
        }
    }

    private func environment() -> [String: String] {
        [
            "HOME": "/private/tmp/home",
            "USER": "owner",
            "LANG": "en_US.UTF-8",
            "PATH": "/usr/bin:/bin",
        ]
    }

    private func removing(_ key: String, from environment: [String: String]) -> [String: String] {
        var result = environment
        result[key] = nil
        return result
    }

    private func replacing(
        _ key: String, with value: String, in environment: [String: String]
    ) -> [String: String] {
        var result = environment
        result[key] = value
        return result
    }
}
