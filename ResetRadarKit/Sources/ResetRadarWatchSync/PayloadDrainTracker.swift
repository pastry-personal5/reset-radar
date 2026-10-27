import Foundation

/// Tracks framework-delivered payload work across the synchronous WatchConnectivity delegate and
/// the asynchronous durable commit. A watchOS background task waits here before returning.
public final class PayloadDrainTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    public func begin() { lock.withLock { pending += 1 } }

    public func finish() {
        let ready: [CheckedContinuation<Void, Never>] = lock.withLock {
            pending = max(0, pending - 1)
            guard pending == 0 else { return [] }
            let ready = waiters
            waiters.removeAll()
            return ready
        }
        for continuation in ready {
            continuation.resume()
        }
    }

    public func waitUntilDrained() async {
        if lock.withLock({ pending == 0 }) { return }
        await withCheckedContinuation { continuation in
            let resumeImmediately = lock.withLock {
                guard pending > 0 else { return true }
                waiters.append(continuation)
                return false
            }
            if resumeImmediately { continuation.resume() }
        }
    }
}
