import Foundation
import ResetRadarApplication

/// A settable clock whose `sleep` returns once the clock is advanced past its deadline.
public final class FakeAppClock: AppClock, @unchecked Sendable {
    private struct Sleeper {
        let id: UUID
        let deadline: Date
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var current: Date
        var sleepers: [Sleeper] = []
    }

    private let state: Locked<State>

    public init(start: Date = Date(timeIntervalSinceReferenceDate: 800_000_000)) {
        state = Locked(State(current: start))
    }

    public var now: Date { state.withLock { $0.current } }
    public var sleeperCount: Int { state.withLock { $0.sleepers.count } }

    public func set(_ date: Date) {
        let due = state.withLock { state -> [Sleeper] in
            state.current = date
            return Self.takeDue(&state)
        }
        for sleeper in due { sleeper.continuation.resume() }
    }

    public func advance(by seconds: TimeInterval) {
        set(now.addingTimeInterval(seconds))
    }

    public func sleep(for duration: Duration) async throws {
        let id = UUID()
        let seconds =
            Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let outcome = state.withLock { state -> Result<Void, any Error>? in
                    if Task.isCancelled { return .failure(CancellationError()) }
                    if seconds <= 0 { return .success(()) }
                    state.sleepers.append(
                        Sleeper(
                            id: id, deadline: state.current.addingTimeInterval(seconds),
                            continuation: continuation))
                    return nil
                }
                if let outcome { continuation.resume(with: outcome) }
            }
        } onCancel: {
            let cancelled = state.withLock { state -> Sleeper? in
                guard let index = state.sleepers.firstIndex(where: { $0.id == id }) else {
                    return nil
                }
                return state.sleepers.remove(at: index)
            }
            cancelled?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Suspends until at least `count` tasks are sleeping, so a test advances only after the
    /// code under test is waiting.
    public func waitForSleepers(_ count: Int = 1) async {
        for _ in 0..<5_000 where sleeperCount < count {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    private static func takeDue(_ state: inout State) -> [Sleeper] {
        let due = state.sleepers.filter { $0.deadline <= state.current }
        state.sleepers.removeAll { $0.deadline <= state.current }
        return due
    }
}
