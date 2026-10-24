import Darwin
import Foundation
import ResetRadarApplication

public enum CodexCommandError: Error, Equatable, Sendable {
    case invalidCommand
    case launchFailed
    case timedOut
    case outputTooLarge
}

public struct CodexCommand: Equatable, Sendable {
    public let executableURL: URL
    public let arguments: [String]
    public let environment: [String: String]
    public let workingDirectoryURL: URL
    public let timeout: Duration
    public let maximumOutputBytes: Int

    public init(
        executableURL: URL, arguments: [String], environment: [String: String],
        workingDirectoryURL: URL, timeout: Duration, maximumOutputBytes: Int
    ) throws {
        guard executableURL.path.hasPrefix("/"), workingDirectoryURL.path.hasPrefix("/"),
            maximumOutputBytes > 0,
            !arguments.contains(where: { $0.contains("\0") }),
            !environment.keys.contains(where: { $0.contains("\0") }),
            !environment.values.contains(where: { $0.contains("\0") })
        else { throw CodexCommandError.invalidCommand }
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
        self.workingDirectoryURL = workingDirectoryURL
        self.timeout = timeout
        self.maximumOutputBytes = maximumOutputBytes
    }
}

public struct CodexCommandResult: Equatable, Sendable {
    public let standardOutput: Data
    public let exitStatus: Int32

    public init(standardOutput: Data, exitStatus: Int32) {
        self.standardOutput = standardOutput
        self.exitStatus = exitStatus
    }
}

public protocol CodexCommandRunning: Sendable {
    func run(_ command: CodexCommand) async throws -> CodexCommandResult
}

private final class CommandCapture: @unchecked Sendable {
    private let lock = NSLock()
    private let maximumBytes: Int
    private var standardOutput = Data()
    private var exceeded = false

    init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
    }

    func appendStandardOutput(_ data: Data) -> Bool {
        lock.withLock {
            guard !exceeded else { return false }
            guard standardOutput.count + data.count <= maximumBytes else {
                exceeded = true
                return false
            }
            standardOutput.append(data)
            return true
        }
    }

    var result: Result<Data, CodexCommandError> {
        lock.withLock { exceeded ? .failure(.outputTooLarge) : .success(standardOutput) }
    }
}

public struct FoundationCodexCommandRunner: CodexCommandRunning, Sendable {
    private struct ConfiguredCommand {
        let process: Process
        let output: Pipe
        let standardError: Pipe
        let termination: AsyncStream<Int32>
    }

    private let clock: any AppClock

    public init(clock: any AppClock) {
        self.clock = clock
    }

    public func run(_ command: CodexCommand) async throws -> CodexCommandResult {
        let capture = CommandCapture(maximumBytes: command.maximumOutputBytes)
        let configured = configure(command, capture: capture)
        let process = configured.process
        do {
            try process.run()
        } catch {
            clearHandlers(output: configured.output, standardError: configured.standardError)
            throw CodexCommandError.launchFailed
        }

        let status: Int32
        do {
            status = try await withThrowingTaskGroup(of: Int32.self) { group in
                group.addTask {
                    var iterator = configured.termination.makeAsyncIterator()
                    return await iterator.next() ?? -1
                }
                group.addTask { [clock] in
                    try await clock.sleep(for: command.timeout)
                    throw CodexCommandError.timedOut
                }
                guard let first = try await group.next() else {
                    throw CodexCommandError.launchFailed
                }
                group.cancelAll()
                return first
            }
        } catch {
            if process.isRunning { process.terminate() }
            clearHandlers(output: configured.output, standardError: configured.standardError)
            if let commandError = error as? CodexCommandError { throw commandError }
            throw CodexCommandError.launchFailed
        }
        clearHandlers(output: configured.output, standardError: configured.standardError)
        _ = capture.appendStandardOutput(
            Self.drainAvailable(
                configured.output.fileHandleForReading, limit: command.maximumOutputBytes))
        return CodexCommandResult(standardOutput: try capture.result.get(), exitStatus: status)
    }

    private func configure(
        _ command: CodexCommand, capture: CommandCapture
    ) -> ConfiguredCommand {
        let process = Process()
        let output = Pipe()
        let standardError = Pipe()
        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.environment = command.environment
        process.currentDirectoryURL = command.workingDirectoryURL
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = standardError
        output.fileHandleForReading.readabilityHandler = { handle in
            guard capture.appendStandardOutput(handle.availableData) else {
                if process.isRunning { process.terminate() }
                return
            }
        }
        standardError.fileHandleForReading.readabilityHandler = { handle in
            // Diagnostics text is never kept or counted: only drain so the child cannot block.
            if handle.availableData.isEmpty { handle.readabilityHandler = nil }
        }
        let termination = AsyncStream<Int32>.makeStream()
        process.terminationHandler = { process in
            termination.continuation.yield(process.terminationStatus)
            termination.continuation.finish()
        }
        return ConfiguredCommand(
            process: process, output: output, standardError: standardError,
            termination: termination.stream)
    }

    /// Reads what is already buffered without blocking, so a grandchild that keeps the pipe open
    /// cannot hang the caller and the result stays within the output cap.
    private static func drainAvailable(_ handle: FileHandle, limit: Int) -> Data {
        let descriptor = handle.fileDescriptor
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        var collected = Data()
        // A failed read here is EAGAIN (nothing buffered) or EOF: both end the drain.
        while collected.count <= limit {
            guard let chunk = try? handle.read(upToCount: 4_096), !chunk.isEmpty else { break }
            collected.append(chunk)
        }
        return collected
    }

    private func clearHandlers(output: Pipe, standardError: Pipe) {
        output.fileHandleForReading.readabilityHandler = nil
        standardError.fileHandleForReading.readabilityHandler = nil
    }
}
