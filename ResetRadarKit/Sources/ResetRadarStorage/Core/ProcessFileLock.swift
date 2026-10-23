import Foundation

/// A cross-process exclusive lock: `flock` on a dedicated file. `flock` belongs to the open file
/// description, so two descriptors in one process contend exactly as two processes do, and the
/// kernel frees the lock when its holder exits, however it exits.
public final class ProcessFileLock: Sendable {
    private let lockFile: URL
    private let timeout: Duration
    private let pollInterval: Duration
    private let protection: ProtectionPolicy

    public init(
        lockFile: URL, timeout: Duration = .seconds(5),
        pollInterval: Duration = .milliseconds(10),
        protection: ProtectionPolicy = .forCurrentPlatform()
    ) {
        self.lockFile = lockFile
        self.timeout = timeout
        self.pollInterval = pollInterval
        self.protection = protection
    }

    /// Polls with `LOCK_NB` instead of blocking a thread, so a stuck holder cannot starve the
    /// cooperative pool. Throws `lockTimeout` after `timeout`, or `CancellationError` if the
    /// waiting task is cancelled. The lock is released on every exit path of `body`.
    public func withLock<T: Sendable>(_ body: @Sendable () throws -> T) async throws -> T {
        let descriptor = try acquire()
        defer {
            _ = flock(descriptor, LOCK_UN)
            close(descriptor)
        }
        return try await wait(for: descriptor, body)
    }

    private func acquire() throws -> Int32 {
        do {
            try FileManager.default.createDirectory(
                at: lockFile.deletingLastPathComponent(), withIntermediateDirectories: true,
                attributes: protection.directoryAttributes)
        } catch {
            throw StorageError.io(code: AtomicFileWriter.code(of: error))
        }
        let descriptor = open(
            lockFile.path(percentEncoded: false), O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw StorageError.io(code: Int(errno)) }
        return descriptor
    }

    private func wait<T: Sendable>(
        for descriptor: Int32, _ body: @Sendable () throws -> T
    ) async throws -> T {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            let code = errno
            guard code == EWOULDBLOCK || code == EINTR else {
                throw StorageError.io(code: Int(code))
            }
            guard ContinuousClock.now < deadline else { throw StorageError.lockTimeout }
            try await Task.sleep(for: pollInterval)
        }
        return try body()
    }
}
