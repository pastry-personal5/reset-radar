import Darwin
import Foundation

public enum ComposedCommandError: Error, Equatable, Sendable {
    case notTrusted
    case launchFailed
    case pipeFailed
}

/// One directly launched, already-trusted existing status-line executable. It never uses a shell,
/// adds no argument, and never accumulates output: stdout/stderr go to the handles it is given.
public final class ComposedCommandRunner: @unchecked Sendable {
    private let process = Process()
    private let stdinWriteDescriptor: Int32
    private let lock = NSLock()
    private var stdinOpen = true
    private let terminationLock = NSLock()
    private var terminated = false
    private let exited = DispatchSemaphore(value: 0)

    var processIdentifier: pid_t { process.processIdentifier }

    /// Revalidates `executablePath` with `validator`, then launches it.
    public init(
        executablePath: String, validator: ExecutableIdentityValidator,
        environment: [String: String], workingDirectory: URL?, standardOutput: FileHandle,
        standardError: FileHandle
    ) throws(ComposedCommandError) {
        let canonical: String
        do {
            canonical = try validator.validatePath(executablePath)
        } catch {
            throw .notTrusted
        }
        signal(SIGPIPE, SIG_IGN)
        var descriptors: [Int32] = [0, 0]
        guard pipe(&descriptors) == 0 else { throw .pipeFailed }
        // The child must not inherit the write end, or it would never see EOF.
        _ = fcntl(descriptors[1], F_SETFD, FD_CLOEXEC)
        _ = fcntl(descriptors[0], F_SETFD, FD_CLOEXEC)
        stdinWriteDescriptor = descriptors[1]
        let reader = FileHandle(fileDescriptor: descriptors[0], closeOnDealloc: true)
        process.executableURL = URL(fileURLWithPath: canonical)
        process.arguments = []
        process.environment = environment
        if let workingDirectory { process.currentDirectoryURL = workingDirectory }
        process.standardInput = reader
        process.standardOutput = standardOutput
        process.standardError = standardError
        let exited = self.exited
        process.terminationHandler = { _ in exited.signal() }
        guard Self.launch(process) else {
            close(descriptors[1])
            throw .launchFailed
        }
        try? reader.close()
    }

    /// A just-replaced executable can be briefly busy while another thread's fork still holds a
    /// descriptor to it, so retry a few times before giving up.
    private static func launch(_ process: Process) -> Bool {
        for attempt in 0..<5 {
            if (try? process.run()) != nil { return true }
            if attempt < 4 { usleep(50_000) }
        }
        return false
    }

    /// Writes with backpressure. Returns false once the child closed its input.
    public func write(_ chunk: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard stdinOpen else { return false }
        let wrote = chunk.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return true }
            var offset = 0
            while offset < raw.count {
                let count = Darwin.write(
                    stdinWriteDescriptor, base.advanced(by: offset), raw.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { return false }
                offset += count
            }
            return true
        }
        if !wrote { closeStandardInputLocked() }
        return wrote
    }

    public func closeStandardInput() {
        lock.lock()
        closeStandardInputLocked()
        lock.unlock()
    }

    private func closeStandardInputLocked() {
        guard stdinOpen else { return }
        stdinOpen = false
        close(stdinWriteDescriptor)
    }

    /// Waits for the child and returns the status Claude Code should see.
    public func waitForExit() -> Int32 {
        exited.wait()
        exited.signal()
        return process.terminationReason == .uncaughtSignal
            ? 128 + process.terminationStatus : process.terminationStatus
    }

    /// Terminates and reaps only the child this runner created, then closes input. The child dies
    /// before the input lock is taken because `write` holds that lock while blocked on a child
    /// that is not reading; closing first would wait on that write forever.
    public func terminate(grace: TimeInterval = 1) {
        terminationLock.lock()
        let first = !terminated
        terminated = true
        terminationLock.unlock()
        guard first else { return }
        if process.isRunning {
            process.terminate()
            if exited.wait(timeout: .now() + grace) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                exited.wait()
            }
            exited.signal()
        }
        closeStandardInput()
    }
}
