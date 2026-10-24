import Darwin
import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarTestSupport
import Testing

@testable import ResetRadarProviderAdapters

final class FakeWatchSession: DirectoryWatchSession, @unchecked Sendable {
    let events: AsyncStream<DirectoryWatchEvent>
    private let continuation: AsyncStream<DirectoryWatchEvent>.Continuation
    private let cancelledState = Locked(false)

    init() {
        let pair = AsyncStream<DirectoryWatchEvent>.makeStream()
        events = pair.stream
        continuation = pair.continuation
    }

    var cancelled: Bool { cancelledState.snapshot }
    func send(_ event: DirectoryWatchEvent) { continuation.yield(event) }
    func cancel() {
        cancelledState.withLock { $0 = true }
        continuation.finish()
    }
}

final class FakeWatchFactory: DirectoryWatchFactory, @unchecked Sendable {
    private struct State {
        var sessions: [FakeWatchSession] = []
        var failures: [DirectoryWatchError] = []
        var onWatch: (@Sendable () -> Void)?
    }

    private let state = Locked(State())

    var sessions: [FakeWatchSession] { state.withLock { $0.sessions } }
    var current: FakeWatchSession? { sessions.last }
    func failNext(_ errors: DirectoryWatchError...) { state.withLock { $0.failures += errors } }
    func onWatch(_ body: @escaping @Sendable () -> Void) { state.withLock { $0.onWatch = body } }

    func watch(directory: URL) throws(DirectoryWatchError) -> any DirectoryWatchSession {
        let (failure, hook) = state.withLock {
            ($0.failures.isEmpty ? nil : $0.failures.removeFirst(), $0.onWatch)
        }
        if let failure { throw failure }
        hook?()
        let session = FakeWatchSession()
        state.withLock { $0.sessions.append(session) }
        return session
    }
}

final class FakeInstallationProbe: ClaudeCodeInstallationProbing, @unchecked Sendable {
    private let value = Locked(ClaudeCodeInstallationStatus.ready)
    func set(_ status: ClaudeCodeInstallationStatus) { value.withLock { $0 = status } }
    func status() async -> ClaudeCodeInstallationStatus { value.snapshot }
}

actor UpdateCollector {
    private(set) var updates: [SourceSnapshot] = []

    init(_ stream: AsyncStream<SourceSnapshot>) {
        Task { [weak self] in
            for await update in stream { await self?.append(update) }
        }
    }

    private func append(_ update: SourceSnapshot) { updates.append(update) }

    func waitForCount(_ count: Int) async -> [SourceSnapshot] {
        for _ in 0..<2_000 where updates.count < count {
            try? await Task.sleep(for: .milliseconds(2))
        }
        return updates
    }
}

final class GatedProbe: ClaudeCodeInstallationProbing, @unchecked Sendable {
    private let gate = AsyncStream<Void>.makeStream()
    func open() { gate.continuation.yield() }

    func status() async -> ClaudeCodeInstallationStatus {
        var iterator = gate.stream.makeAsyncIterator()
        _ = await iterator.next()
        return .ready
    }
}

struct SourceRig {
    let root: URL
    let file: SessionRecordFile
    let clock = FakeAppClock(start: Date(timeIntervalSince1970: 1_000_000))
    let factory = FakeWatchFactory()
    let probe = FakeInstallationProbe()
    let sink = FakeDiagnosticsSink()
    let source: ClaudeCodeSource

    init(_ root: URL) {
        self.root = root
        file = SessionRecordFile(rootDirectory: root.appending(path: "ResetRadar"))
        source = ClaudeCodeSource(
            accountID: collectionAccount, file: file, watchFactory: factory, probe: probe,
            diagnostics: sink, clock: clock)
    }

    func record(_ percent: Double, observed: TimeInterval = 999_000, id: String = "s") throws {
        try store(
            sessionRecord(id, windows: [sessionWindow(percent: percent, observed: observed)]),
            in: file)
    }
}
