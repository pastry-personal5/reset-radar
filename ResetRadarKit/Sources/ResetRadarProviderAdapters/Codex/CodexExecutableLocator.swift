import Foundation
import ResetRadarApplication

public enum CodexExecutableLocatorError: Error, Equatable, Sendable {
    case unsafeEnvironment
    case invalidExplicitSelection
}

public struct CodexDiscoveryCandidate: Equatable, Sendable {
    public let option: ConfigurationOption
    public let executable: CodexValidatedExecutable

    public init(option: ConfigurationOption, executable: CodexValidatedExecutable) {
        self.option = option
        self.executable = executable
    }
}

public struct CodexExecutableLocator: Sendable {
    public static let maximumDiscoveryOutputBytes = 4_096

    private let runner: any CodexCommandRunning
    private let validator: CodexExecutableValidator

    public init(
        runner: any CodexCommandRunning,
        validator: CodexExecutableValidator = CodexExecutableValidator()
    ) {
        self.runner = runner
        self.validator = validator
    }

    public func discover(
        explicitPath: String?, loginShellURL: URL?, environment: [String: String],
        workingDirectoryURL: URL
    ) async throws -> [CodexDiscoveryCandidate] {
        try validateEnvironment(environment, workingDirectoryURL: workingDirectoryURL)
        var paths: [String] = []
        if let explicitPath {
            do {
                _ = try validator.validate(
                    invocationPath: explicitPath, pathEnvironment: environment["PATH"] ?? "")
            } catch {
                throw CodexExecutableLocatorError.invalidExplicitSelection
            }
            paths.append(explicitPath)
        }
        let shellPath = await loginShellPath(
            shellURL: loginShellURL, environment: environment,
            workingDirectoryURL: workingDirectoryURL)
        if let shellPath { paths.append(shellPath) }
        paths.append(contentsOf: ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"])

        var seen = Set<CodexExecutableFileIdentity>()
        var results: [CodexDiscoveryCandidate] = []
        for path in paths {
            guard
                let executable = try? validator.validate(
                    invocationPath: path, pathEnvironment: environment["PATH"] ?? ""),
                seen.insert(executable.executable).inserted
            else { continue }
            let launch = ConfigurationLaunchPreview(
                executablePath: executable.invocationPath,
                interpreterPath: executable.node?.canonicalPath,
                environment: Self.environmentPreview(environment))
            results.append(
                CodexDiscoveryCandidate(
                    option: ConfigurationOption(
                        id: ConfigurationOptionID(), product: .codex, launch: launch),
                    executable: executable))
        }
        return results
    }

    private func loginShellPath(
        shellURL: URL?, environment: [String: String], workingDirectoryURL: URL
    ) async -> String? {
        guard let shellURL else { return nil }
        guard
            let command = try? CodexCommand(
                executableURL: shellURL, arguments: ["-lc", "command -v codex"],
                environment: environment, workingDirectoryURL: workingDirectoryURL,
                timeout: .seconds(5), maximumOutputBytes: Self.maximumDiscoveryOutputBytes),
            let result = try? await runner.run(command), result.exitStatus == 0
        else { return nil }
        return Self.parseDiscoveryOutput(result.standardOutput)
    }

    private func validateEnvironment(
        _ environment: [String: String], workingDirectoryURL: URL
    ) throws {
        guard workingDirectoryURL.path.hasPrefix("/"),
            Set(environment.keys).isSubset(of: CodexProcessLaunchConfiguration.allowedEnvironment),
            CodexProcessLaunchConfiguration.requiredEnvironment.isSubset(of: Set(environment.keys)),
            let path = environment["PATH"],
            path.split(separator: ":", omittingEmptySubsequences: false).allSatisfy({
                !$0.isEmpty && $0.hasPrefix("/")
            }),
            let home = environment["HOME"], home.hasPrefix("/"),
            let user = environment["USER"], !user.isEmpty,
            let language = environment["LANG"], !language.isEmpty,
            environment["CODEX_HOME"].map({ $0.hasPrefix("/") }) ?? true
        else { throw CodexExecutableLocatorError.unsafeEnvironment }
    }

    private static func parseDiscoveryOutput(_ data: Data) -> String? {
        guard var output = String(data: data, encoding: .utf8) else { return nil }
        if output.hasSuffix("\r\n") {
            output.removeLast(2)
        } else if output.hasSuffix("\n") {
            output.removeLast()
        }
        guard output.hasPrefix("/"), !output.isEmpty, !output.contains("\n"),
            !output.contains("\r"), !output.contains("\0")
        else { return nil }
        return output
    }

    private static func environmentPreview(
        _ environment: [String: String]
    ) -> [ConfigurationEnvironmentValue] {
        ConfigurationEnvironmentKey.allCases.compactMap { key in
            environment[key.rawValue].map {
                ConfigurationEnvironmentValue(key: key, value: $0)
            }
        }
    }
}
