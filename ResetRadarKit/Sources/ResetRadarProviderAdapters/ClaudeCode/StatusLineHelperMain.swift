import Darwin
import Foundation

/// Public version of the helper binary; the installer compares it with the installed copy.
public enum StatusLineHelperVersion {
    public static let current = "1"
}

public struct StatusLineHelperConfiguration: Sendable {
    public let rootDirectory: URL
    public let homeDirectory: URL
    /// Forwarded to a composed child without being persisted or logged.
    public let environment: [String: String]
    public let workingDirectory: URL?

    /// The app and its embedded helper must select the same per-build data namespace.
    public static func applicationSupportRoot(
        homeDirectory: URL, isDevelopmentBuild: Bool
    ) -> URL {
        homeDirectory
            .appending(path: "Library/Application Support", directoryHint: .isDirectory)
            .appending(
                path: isDevelopmentBuild ? "ResetRadar.dev" : "ResetRadar",
                directoryHint: .isDirectory)
    }

    public init(
        rootDirectory: URL, homeDirectory: URL, environment: [String: String],
        workingDirectory: URL? = nil
    ) {
        self.rootDirectory = rootDirectory
        self.homeDirectory = homeDirectory
        self.environment = environment
        self.workingDirectory = workingDirectory
    }
}

/// Lets the composition root terminate the one child when Claude Code cancels the status line.
public final class StatusLineHelperCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var runner: ComposedCommandRunner?
    private var cancelled = false

    public init() {}

    func register(_ runner: ComposedCommandRunner) {
        lock.lock()
        self.runner = runner
        let already = cancelled
        lock.unlock()
        if already { runner.terminate() }
    }

    public func cancel() {
        lock.lock()
        cancelled = true
        let runner = runner
        lock.unlock()
        runner?.terminate()
    }
}

/// The helper's one invocation: pump stdin once, record locally, optionally run one approved
/// existing command with the identical bytes. It prints nothing of its own.
public enum StatusLineHelperMain {
    public static func run(
        arguments: [String], standardInput: Int32, standardOutput: FileHandle,
        standardError: FileHandle, configuration: StatusLineHelperConfiguration,
        clock: @escaping @Sendable () -> Date = { Date() },
        cancellation: StatusLineHelperCancellation = StatusLineHelperCancellation()
    ) -> Int32 {
        if arguments.dropFirst().first == "--version" {
            standardOutput.write(Data((StatusLineHelperVersion.current + "\n").utf8))
            return 0
        }
        let runner: ComposedCommandRunner?
        do {
            runner = try launchComposedCommand(
                configuration: configuration, standardOutput: standardOutput,
                standardError: standardError, cancellation: cancellation)
        } catch {
            // Quiet but nonzero: no Reset Radar text, and the child never ran.
            return 1
        }

        var capture = BoundedStatusCapture()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        var forwarding = runner != nil
        while true {
            let count = read(standardInput, &buffer, buffer.count)
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { break }
            let chunk = Data(buffer.prefix(count))
            capture.append(chunk)
            if forwarding, let runner { forwarding = runner.write(chunk) }
        }
        runner?.closeStandardInput()

        let recorded = record(capture: capture, configuration: configuration, clock: clock)
        if let runner { return runner.waitForExit() }
        return recorded ? 0 : 1
    }

    private static func launchComposedCommand(
        configuration: StatusLineHelperConfiguration, standardOutput: FileHandle,
        standardError: FileHandle, cancellation: StatusLineHelperCancellation
    ) throws -> ComposedCommandRunner? {
        let store = ComposeRecordStore(rootDirectory: configuration.rootDirectory)
        guard let record = try store.load() else { return nil }
        let launched = try ComposedCommandRunner(
            executablePath: record.executablePath,
            validator: ExecutableIdentityValidator(homeDirectory: configuration.homeDirectory),
            environment: configuration.environment,
            workingDirectory: configuration.workingDirectory,
            standardOutput: standardOutput, standardError: standardError)
        cancellation.register(launched)
        return launched
    }

    private static func record(
        capture: BoundedStatusCapture, configuration: StatusLineHelperConfiguration,
        clock: @escaping @Sendable () -> Date
    ) -> Bool {
        guard let input = capture.completeInput else { return false }
        do {
            let decoded = try StatusLineDecoder.decode(input)
            let file = SessionRecordFile(rootDirectory: configuration.rootDirectory)
            try StatusLineRecorder(file: file, clock: clock).record(decoded)
            return true
        } catch {
            return false
        }
    }
}
