import Foundation
import ResetRadarApplication
import ResetRadarDomain

enum PublicationStatusEvent: Sendable, Equatable {
    case blocked(PublishOutcome)
    case recovered
    case published(date: Date)
}

actor PublicationDriver {
    typealias LoadSnapshot = @Sendable () async throws -> UsageSnapshot?
    typealias Publish =
        @Sendable (UsageSnapshot, ChangeClass, PublishTrigger) async -> PublishOutcome
    typealias ReportOutcome = @Sendable (PublicationStatusEvent) async -> Void

    private struct MetadataDelivery {
        let accountID: AccountID
        let alias: AccountAlias?
        let observer: @Sendable (PublishOutcome) async -> Void
    }

    private let clock: any AppClock
    private let loadSnapshot: LoadSnapshot
    private let publish: Publish
    private let reportOutcome: ReportOutcome
    private var timer: Task<Void, Never>?
    private(set) var scheduledDate: Date?
    private var suspended = false
    private var lastChange = ChangeClass.none
    private var lastReportedBlock: PublishOutcome?
    private var metadataDeliveries = [AccountID: MetadataDelivery]()

    init(
        clock: any AppClock, loadSnapshot: @escaping LoadSnapshot, publish: @escaping Publish,
        reportOutcome: @escaping ReportOutcome = { _ in }
    ) {
        self.clock = clock
        self.loadSnapshot = loadSnapshot
        self.publish = publish
        self.reportOutcome = reportOutcome
    }

    @discardableResult
    func collected(_ result: CollectResult) async -> PublishOutcome {
        lastChange = max(lastChange, result.change)
        return await attempt(snapshot: result.snapshot, change: result.change, trigger: .change)
    }

    func trigger(_ trigger: PublishTrigger) async {
        guard !suspended, let snapshot = try? await loadSnapshot() else { return }
        _ = await attempt(snapshot: snapshot, change: lastChange, trigger: trigger)
    }

    func reportManualOutcome(_ outcome: HandleOutcome) async {
        switch outcome {
        case .publicationFailed(let failure):
            await reportBlockChange(failure)
        case .handled:
            await reportRecovery()
            await reportOutcome(.published(date: clock.now))
        case .idle, .waiting:
            break
        }
    }

    func setSuspended(_ value: Bool) {
        suspended = value
        if value { cancelTimer() }
    }

    func observeMetadataDelivery(
        account: AccountMetadata,
        _ observer: @escaping @Sendable (PublishOutcome) async -> Void
    ) {
        metadataDeliveries[account.id] = MetadataDelivery(
            accountID: account.id, alias: account.alias, observer: observer)
    }

    func stop() {
        suspended = true
        cancelTimer()
    }

    private func attempt(
        snapshot: UsageSnapshot, change: ChangeClass, trigger: PublishTrigger
    ) async -> PublishOutcome {
        guard !suspended else { return .paused }
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
        await reportBlockChange(outcome)
        if case .published = outcome {
            await reportOutcome(.published(date: clock.now))
        }
        let delivered = metadataDeliveries.values.filter { delivery in
            snapshot.accounts.contains {
                $0.id == delivery.accountID && $0.alias == delivery.alias
            }
        }
        for delivery in delivered {
            guard metadataDeliveries[delivery.accountID]?.alias == delivery.alias else { continue }
            if case .published = outcome {
                metadataDeliveries.removeValue(forKey: delivery.accountID)
            }
            await delivery.observer(outcome)
        }
        return outcome
    }

    private func reportBlockChange(_ outcome: PublishOutcome) async {
        switch outcome {
        case .paused, .secretsUnavailable, .envelopeTooLarge, .stopped:
            guard lastReportedBlock != outcome else { return }
            lastReportedBlock = outcome
            await reportOutcome(.blocked(outcome))
        case .published:
            await reportRecovery()
        case .notDue, .backoff:
            break
        }
    }

    private func reportRecovery() async {
        guard lastReportedBlock != nil else { return }
        lastReportedBlock = nil
        await reportOutcome(.recovered)
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
