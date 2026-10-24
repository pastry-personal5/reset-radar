import Foundation

public enum CodexExecutableMetadataError: Error, Equatable, Sendable {
    case commandFailed
    case invalidVersion
}

public struct CodexExecutableMetadata: Codable, Equatable, Sendable {
    public let executable: CodexValidatedExecutable
    public let publicVersion: String

    public init(executable: CodexValidatedExecutable, publicVersion: String) {
        self.executable = executable
        self.publicVersion = publicVersion
    }
}

public struct CodexExecutableMetadataReader: Sendable {
    public static let maximumVersionBytes = 4_096

    private let runner: any CodexCommandRunning

    public init(runner: any CodexCommandRunning) {
        self.runner = runner
    }

    public func read(
        executable: CodexValidatedExecutable, environment: [String: String],
        workingDirectoryURL: URL
    ) async throws -> CodexExecutableMetadata {
        let command = try CodexCommand(
            executableURL: URL(fileURLWithPath: executable.invocationPath),
            arguments: ["--version"], environment: environment,
            workingDirectoryURL: workingDirectoryURL, timeout: .seconds(5),
            maximumOutputBytes: Self.maximumVersionBytes)
        let result: CodexCommandResult
        do {
            result = try await runner.run(command)
        } catch {
            throw CodexExecutableMetadataError.commandFailed
        }
        guard result.exitStatus == 0,
            let output = String(data: result.standardOutput, encoding: .utf8),
            let version = Self.normalizeVersion(output)
        else { throw CodexExecutableMetadataError.invalidVersion }
        return CodexExecutableMetadata(executable: executable, publicVersion: version)
    }

    public static func normalizeVersion(_ output: String) -> String? {
        var bytes = Array(output.utf8)
        if bytes.suffix(2) == [UInt8(ascii: "\r"), UInt8(ascii: "\n")] {
            bytes.removeLast(2)
        } else if bytes.last == UInt8(ascii: "\n") {
            bytes.removeLast()
        }
        guard let line = String(bytes: bytes, encoding: .utf8) else { return nil }
        guard !line.isEmpty, !line.contains("\n"), !line.contains("\r"),
            !line.contains("/"), !line.contains("\\")
        else { return nil }
        let parts = line.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0] == "codex" || parts[0] == "codex-cli",
            validSemanticVersion(parts[1])
        else { return nil }
        return "codex \(parts[1])"
    }

    private static func validSemanticVersion(_ value: Substring) -> Bool {
        let pieces = value.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard let core = pieces.first else { return false }
        let numbers = core.split(separator: ".", omittingEmptySubsequences: false)
        guard numbers.count == 3,
            numbers.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) })
        else { return false }
        if pieces.count == 2 {
            let suffix = pieces[1]
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
            return !suffix.isEmpty && suffix.unicodeScalars.allSatisfy(allowed.contains)
        }
        return true
    }
}
