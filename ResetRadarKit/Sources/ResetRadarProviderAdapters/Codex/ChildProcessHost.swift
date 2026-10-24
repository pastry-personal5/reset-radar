import Darwin
import Foundation

public enum ChildProcessHostError: Error, Equatable, Sendable {
    case unsafeLaunchConfiguration
    case executableUnavailable
    case launchFailed
    case standardInputClosed
}

public struct CodexProcessLaunchConfiguration: Equatable, Sendable {
    public static let requiredEnvironment = Set(["HOME", "USER", "LANG", "PATH"])
    public static let allowedEnvironment = requiredEnvironment.union(["CODEX_HOME"])

    public let executableURL: URL
    public let environment: [String: String]
    public let workingDirectoryURL: URL

    public init(
        executableURL: URL, environment: [String: String], workingDirectoryURL: URL
    ) throws {
        guard executableURL.path.hasPrefix("/"), workingDirectoryURL.path.hasPrefix("/"),
            Set(environment.keys).isSubset(of: Self.allowedEnvironment),
            Self.requiredEnvironment.isSubset(of: Set(environment.keys)),
            environment.values.allSatisfy({ !$0.contains("\0") }),
            let home = environment["HOME"], home.hasPrefix("/"),
            let user = environment["USER"], !user.isEmpty,
            let language = environment["LANG"], !language.isEmpty,
            let path = environment["PATH"], Self.isSafePath(path),
            environment["CODEX_HOME"].map({ $0.hasPrefix("/") }) ?? true
        else { throw ChildProcessHostError.unsafeLaunchConfiguration }
        self.executableURL = executableURL
        self.environment = environment
        self.workingDirectoryURL = workingDirectoryURL
    }

    private static func isSafePath(_ value: String) -> Bool {
        let components = value.split(separator: ":", omittingEmptySubsequences: false)
        return !components.isEmpty
            && components.allSatisfy { component in
                !component.isEmpty && component.hasPrefix("/")
            }
    }
}

public final class ChildProcessSession: JSONRPCTransport, @unchecked Sendable {
    public let stdoutChunks: AsyncStream<Data>
    public let exits: AsyncStream<Int32>

    private struct State {
        var standardInputClosed = false
        var terminated = false
    }

    private let process: Process
    private let standardInput: FileHandle
    private let standardOutput: FileHandle
    private let standardError: FileHandle
    private let stdoutContinuation: AsyncStream<Data>.Continuation
    private let exitContinuation: AsyncStream<Int32>.Continuation
    private let lock = NSLock()
    private var state = State()

    fileprivate init(
        process: Process,
        standardInput: FileHandle,
        standardOutput: FileHandle,
        standardError: FileHandle,
        stdoutStream: AsyncStream<Data>,
        stdoutContinuation: AsyncStream<Data>.Continuation,
        exitStream: AsyncStream<Int32>,
        exitContinuation: AsyncStream<Int32>.Continuation
    ) {
        self.process = process
        self.standardInput = standardInput
        // A write to an exited child must fail with EPIPE, not raise SIGPIPE in the host app.
        _ = fcntl(standardInput.fileDescriptor, F_SETNOSIGPIPE, 1)
        self.standardOutput = standardOutput
        self.standardError = standardError
        stdoutChunks = stdoutStream
        self.stdoutContinuation = stdoutContinuation
        exits = exitStream
        self.exitContinuation = exitContinuation
    }

    deinit {
        standardOutput.readabilityHandler = nil
        standardError.readabilityHandler = nil
        stdoutContinuation.finish()
        exitContinuation.finish()
    }

    public func write(_ data: Data) async throws {
        try lock.withLock {
            guard !state.standardInputClosed, !state.terminated else {
                throw ChildProcessHostError.standardInputClosed
            }
            try standardInput.write(contentsOf: data)
        }
    }

    public func closeStandardInput() {
        lock.withLock {
            guard !state.standardInputClosed else { return }
            state.standardInputClosed = true
            try? standardInput.close()
        }
    }

    public func terminate() async {
        let shouldTerminate = lock.withLock {
            guard !state.terminated else { return false }
            state.terminated = true
            if !state.standardInputClosed {
                state.standardInputClosed = true
                try? standardInput.close()
            }
            return process.isRunning
        }
        guard shouldTerminate else { return }
        process.terminate()
        let child = process
        Task.detached {
            try? await Task.sleep(for: .seconds(2))
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        }
    }

    public func stop(grace: Duration = .seconds(5)) async {
        closeStandardInput()
        let deadline = ContinuousClock.now.advanced(by: grace)
        while process.isRunning, ContinuousClock.now < deadline {
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch { break }
        }
        guard process.isRunning else { return }
        await terminate()
    }

    fileprivate func installHandlers() {
        standardOutput.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                self?.stdoutContinuation.finish()
                return
            }
            guard let self else { return }
            // A consumer that stops reading must not grow memory without bound: fail closed.
            if case .dropped = self.stdoutContinuation.yield(data) {
                Task { await self.terminate() }
            }
        }
        standardError.readabilityHandler = { handle in
            if handle.availableData.isEmpty { handle.readabilityHandler = nil }
        }
        process.terminationHandler = { [weak self] process in
            guard let self else { return }
            self.exitContinuation.yield(process.terminationStatus)
            self.exitContinuation.finish()
        }
    }
}

public struct ChildProcessHost: Sendable {
    public static let arguments = [
        "app-server", "--strict-config", "-c", "analytics.enabled=false", "--listen", "stdio://",
    ]

    private let appWorkingDirectoryURL: URL

    public init(appWorkingDirectoryURL: URL) {
        self.appWorkingDirectoryURL = appWorkingDirectoryURL.standardizedFileURL
    }

    public func launch(
        _ configuration: CodexProcessLaunchConfiguration
    ) throws -> ChildProcessSession {
        guard configuration.workingDirectoryURL.standardizedFileURL == appWorkingDirectoryURL else {
            throw ChildProcessHostError.unsafeLaunchConfiguration
        }
        var isDirectory = ObjCBool(false)
        guard
            FileManager.default.fileExists(
                atPath: configuration.executableURL.path, isDirectory: &isDirectory),
            !isDirectory.boolValue,
            FileManager.default.isExecutableFile(atPath: configuration.executableURL.path)
        else { throw ChildProcessHostError.executableUnavailable }
        guard
            FileManager.default.fileExists(
                atPath: appWorkingDirectoryURL.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else { throw ChildProcessHostError.unsafeLaunchConfiguration }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let standardErrorPipe = Pipe()
        process.executableURL = configuration.executableURL
        process.arguments = Self.arguments
        process.environment = configuration.environment
        process.currentDirectoryURL = appWorkingDirectoryURL
        process.standardInput = input
        process.standardOutput = output
        process.standardError = standardErrorPipe

        let stdout = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingOldest(64))
        let exits = AsyncStream<Int32>.makeStream()
        let session = ChildProcessSession(
            process: process,
            standardInput: input.fileHandleForWriting,
            standardOutput: output.fileHandleForReading,
            standardError: standardErrorPipe.fileHandleForReading,
            stdoutStream: stdout.stream,
            stdoutContinuation: stdout.continuation,
            exitStream: exits.stream,
            exitContinuation: exits.continuation)
        session.installHandlers()
        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            standardErrorPipe.fileHandleForReading.readabilityHandler = nil
            throw ChildProcessHostError.launchFailed
        }
        return session
    }
}
