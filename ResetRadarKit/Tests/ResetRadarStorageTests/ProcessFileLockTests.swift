import Foundation
import Testing

@testable import ResetRadarStorage

private final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    func append(_ event: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(event)
    }
    var events: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

struct ProcessFileLockTests {
    private struct Injected: Error {}

    @Test func twoLocksOverOneFileSerialize() async throws {
        let directory = TemporaryDirectory()
        let file = directory.url.appending(path: "gate.lock")
        let log = EventLog()
        let first = ProcessFileLock(lockFile: file)
        let second = ProcessFileLock(lockFile: file)
        let holding = Task {
            try await first.withLock {
                log.append("first-start")
                Thread.sleep(forTimeInterval: 0.2)
                log.append("first-end")
            }
        }
        while !log.events.contains("first-start") { try await Task.sleep(for: .milliseconds(5)) }
        try await second.withLock { log.append("second") }
        try await holding.value
        #expect(log.events == ["first-start", "first-end", "second"])
    }

    @Test func heldLockTimesOut() async throws {
        let directory = TemporaryDirectory()
        let file = directory.url.appending(path: "gate.lock")
        let log = EventLog()
        let holder = ProcessFileLock(lockFile: file)
        let waiter = ProcessFileLock(lockFile: file, timeout: .milliseconds(100))
        let holding = Task {
            try await holder.withLock {
                log.append("held")
                Thread.sleep(forTimeInterval: 0.4)
            }
        }
        while !log.events.contains("held") { try await Task.sleep(for: .milliseconds(5)) }
        await #expect(throws: StorageError.lockTimeout) { try await waiter.withLock { 1 } }
        try await holding.value
    }

    @Test func releasesWhenTheBodyThrows() async throws {
        let directory = TemporaryDirectory()
        let lock = ProcessFileLock(
            lockFile: directory.url.appending(path: "gate.lock"), timeout: .milliseconds(200))
        await #expect(throws: Injected.self) { try await lock.withLock { throw Injected() } }
        #expect(try await lock.withLock { 7 } == 7)
    }

    @Test func cancellingTheWaiterStopsPolling() async throws {
        let directory = TemporaryDirectory()
        let file = directory.url.appending(path: "gate.lock")
        let log = EventLog()
        let holder = ProcessFileLock(lockFile: file)
        let waiter = ProcessFileLock(lockFile: file, timeout: .seconds(30))
        let holding = Task {
            try await holder.withLock {
                log.append("held")
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
        while !log.events.contains("held") { try await Task.sleep(for: .milliseconds(5)) }
        let waiting = Task { try await waiter.withLock { log.append("ran") } }
        try await Task.sleep(for: .milliseconds(50))
        waiting.cancel()
        await #expect(throws: CancellationError.self) { try await waiting.value }
        try await holding.value
        #expect(!log.events.contains("ran"))
    }

    @Test func cancelledTaskDoesNotRunTheBodyWhenTheLockIsFree() async throws {
        let directory = TemporaryDirectory()
        let log = EventLog()
        let lock = ProcessFileLock(lockFile: directory.url.appending(path: "gate.lock"))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await lock.withLock { log.append("ran") }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(log.events.isEmpty)
    }

    @Test func missingDirectoryIsCreated() async throws {
        let directory = TemporaryDirectory()
        let lock = ProcessFileLock(lockFile: directory.url.appending(path: "new/gate.lock"))
        #expect(try await lock.withLock { 1 } == 1)
    }

    /// A separate process holding `/usr/bin/lockf` blocks us, so `lockf` takes `flock(2)` on the
    /// same file and the contention here is the real cross-process mechanism.
    #if os(macOS)
        @Test func childProcessHoldingTheLockBlocksUsUntilItExits() async throws {
            let directory = TemporaryDirectory()
            try FileManager.default.createDirectory(
                at: directory.url, withIntermediateDirectories: true)
            let file = directory.url.appending(path: "gate.lock")
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/lockf")
            process.arguments = ["-k", file.path, "/bin/sleep", "1"]
            try process.run()
            defer { if process.isRunning { process.terminate() } }
            try await Task.sleep(for: .milliseconds(300))
            let impatient = ProcessFileLock(lockFile: file, timeout: .milliseconds(100))
            await #expect(throws: StorageError.lockTimeout) { try await impatient.withLock { 1 } }
            process.terminate()
            process.waitUntilExit()
            let afterExit = ProcessFileLock(lockFile: file, timeout: .seconds(2))
            #expect(try await afterExit.withLock { 2 } == 2)
        }
    #endif
}
