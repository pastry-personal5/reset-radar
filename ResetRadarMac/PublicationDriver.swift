import Foundation
import ResetRadarApplication
import ResetRadarDomain

actor PublicationDriver {
    typealias LoadSnapshot = @Sendable () async throws -> UsageSnapshot?
    typealias Publish =
        @Sendable (UsageSnapshot, ChangeClass, PublishTrigger) async -> PublishOutcome

    private let clock: any AppClock
    private let loadSnapshot: LoadSnapshot
    private let publish: Publish
    private var timer: Task<Void, Never>?
    private(set) var scheduledDate: Date?
    private var suspended = false
    private var lastChange = ChangeClass.none

    init(clock: any AppClock, loadSnapshot: @escaping LoadSnapshot, publish: @escaping Publish) {
        self.clock = clock
        self.loadSnapshot = loadSnapshot
        self.publish = publish
    }

    func collected(_ result: CollectResult) async {
        lastChange = max(lastChange, result.change)
        await attempt(snapshot: result.snapshot, change: result.change, trigger: .change)
    }

    func trigger(_ trigger: PublishTrigger) async {
        guard !suspended, let snapshot = try? await loadSnapshot() else { return }
        await attempt(snapshot: snapshot, change: lastChange, trigger: trigger)
    }

    func setSuspended(_ value: Bool) {
        suspended = value
        if value { cancelTimer() }
    }

    func stop() {
        suspended = true
        cancelTimer()
    }

    private func attempt(
        snapshot: UsageSnapshot, change: ChangeClass, trigger: PublishTrigger
    ) async {
        guard !suspended else { return }
        let outcome = await publish(snapshot, change, trigger)
        switch outcome {
        case .notDue(let next):
            if let next { arm(for: next) }
        case .backoff(let until):
            arm(for: until)
        case .published:
            lastChange = .none
            arm(for: clock.now.addingTimeInterval(PublicationPolicy.heartbeat))
        case .paused, .secretsUnavailable, .envelopeTooLarge, .stopped:
            cancelTimer()
        }
    }

    private func arm(for date: Date) {
        cancelTimer()
        scheduledDate = date
        let seconds = max(0, date.timeIntervalSince(clock.now))
        timer = Task { [weak self, clock] in
            try? await clock.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await self?.timerFired(date)
        }
    }

    private func timerFired(_ date: Date) async {
        guard scheduledDate == date else { return }
        timer = nil
        scheduledDate = nil
        await trigger(.heartbeat)
    }

    private func cancelTimer() {
        timer?.cancel()
        timer = nil
        scheduledDate = nil
    }
}
