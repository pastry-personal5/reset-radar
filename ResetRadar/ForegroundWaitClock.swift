import Foundation
import ResetRadarApplication

/// The manual-refresh clock: the 45-second wait sleeps through it, so leaving the foreground
/// ends the wait at a sleep boundary while any relay read in progress completes normally.
final class ForegroundWaitClock: AppClock, @unchecked Sendable {
    private struct State {
        var cancelled = false
        var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
        var finished: Set<UUID> = []
    }

    private let base: any AppClock
    private let lock = NSLock()
    private var state = State()

    init(base: any AppClock) {
        self.base = base
    }

    var now: Date { base.now }

    var waitsCancelled: Bool { lock.withLock { state.cancelled } }

    func begin() {
        lock.withLock { state.cancelled = false }
    }

    func cancelWaits() {
        let waiters = lock.withLock {
            state.cancelled = true
            defer { state.waiters = [:] }
            return Array(state.waiters.values)
        }
        for waiter in waiters { waiter.resume() }
    }

    func sleep(for duration: Duration) async throws {
        if waitsCancelled { throw CancellationError() }
        let id = UUID()
        try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask {
                try await self.base.sleep(for: duration)
                return true
            }
            group.addTask {
                await self.untilCancelled(id)
                return false
            }
            let slept: Bool
            do {
                slept = try await group.next() ?? false
            } catch {
                group.cancelAll()
                release(id)
                throw error
            }
            group.cancelAll()
            release(id)
            if !slept { throw CancellationError() }
        }
    }

    private func untilCancelled(_ id: UUID) async {
        await withCheckedContinuation { continuation in
            let resume = lock.withLock {
                if state.cancelled || state.finished.remove(id) != nil { return true }
                state.waiters[id] = continuation
                return false
            }
            if resume { continuation.resume() }
        }
    }

    /// Ends the cancellation watcher of a finished sleep, whether or not it registered yet.
    private func release(_ id: UUID) {
        let waiter = lock.withLock {
            if let waiter = state.waiters.removeValue(forKey: id) { return Optional(waiter) }
            // A cancelled watcher resumes on its own and never registers.
            if !state.cancelled { state.finished.insert(id) }
            return nil
        }
        waiter?.resume()
    }
}
