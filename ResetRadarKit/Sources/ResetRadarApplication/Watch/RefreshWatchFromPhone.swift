import Foundation
import ResetRadarDomain

/// Runs the policy-governed relay ingest for an interactive Watch request while guaranteeing that
/// the reply is taken from the latest permitted committed cache before WatchConnectivity's own
/// timeout. A late ingest remains useful: its ordinary after-commit pipeline updates application
/// context after this bounded reply has completed.
public actor RefreshWatchFromPhone {
    public static let replyDeadline: Duration = .seconds(10)

    private let ingest: IngestRelaySnapshot
    private let forward: ForwardToWatch
    private let clock: any AppClock

    public init(
        ingest: IngestRelaySnapshot, forward: ForwardToWatch, clock: any AppClock
    ) {
        self.ingest = ingest
        self.forward = forward
        self.clock = clock
    }

    public func request() async -> WatchPayload? {
        let work = Task { await ingest.run(trigger: .watchRequest, inAppProcess: true) }
        await FirstCompletion.wait(for: work, clock: clock, deadline: Self.replyDeadline)
        return await forward.currentPayload()
    }
}

private enum FirstCompletion {
    static func wait<Value: Sendable>(
        for work: Task<Value, Never>, clock: any AppClock, deadline: Duration
    ) async {
        let gate = CompletionGate()
        await withCheckedContinuation { continuation in
            gate.install(continuation)
            Task {
                _ = await work.value
                gate.finish()
            }
            Task {
                try? await clock.sleep(for: deadline)
                gate.finish()
            }
        }
    }
}

private final class CompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var finished = false

    func install(_ continuation: CheckedContinuation<Void, Never>) {
        let resume = lock.withLock {
            guard !finished else { return true }
            self.continuation = continuation
            return false
        }
        if resume { continuation.resume() }
    }

    func finish() {
        let continuation = lock.withLock {
            finished = true
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume()
    }
}
