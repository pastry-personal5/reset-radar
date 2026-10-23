import Foundation
import ResetRadarDomain

/// Keeps exactly one reset reminder per opted-in Home slot. It never requests authorization.
public actor ReconcileResetNotifications: AfterCommitStep {
    private let visible: VisibleSnapshot
    private let preferences: any PreferenceStore
    private let scheduler: any NotificationScheduler
    private let gate: (any NotificationReconcileGate)?
    private let clock: any AppClock

    /// `gate` is `nil` on the Mac, which has one scheduler process.
    public init(
        visible: VisibleSnapshot, preferences: any PreferenceStore,
        scheduler: any NotificationScheduler, gate: (any NotificationReconcileGate)?,
        clock: any AppClock
    ) {
        self.visible = visible
        self.preferences = preferences
        self.scheduler = scheduler
        self.gate = gate
        self.clock = clock
    }

    public func afterCommit(_ event: CommitEvent) async {
        _ = await run(onIOS: gate != nil)
    }

    public func run(onIOS: Bool) async -> ReconcileOutcome {
        guard onIOS, let gate else { return await reconcile() }
        guard let claim = await gate.claim() else { return .retryable }
        let outcome = await reconcile()
        await gate.release(claim)
        return outcome
    }

    private func reconcile() async -> ReconcileOutcome {
        let now = clock.now
        let snapshot: UsageSnapshot?
        do { snapshot = try await visible.load() } catch { return .retryable }
        let authorized = await scheduler.authorization() == .authorized
        let pending = Dictionary(
            await scheduler.pending().map { ($0.slot, $0) }, uniquingKeysWith: { first, _ in first }
        )
        for slot in HomeSlot.allCases {
            let desired = await desiredRequest(slot, snapshot: snapshot, now: now)
            if let desired, authorized {
                guard pending[slot]?.fireAt != desired.fireAt else { continue }
                do {
                    try await scheduler.schedule(desired)
                } catch {
                    return .retryable
                }
            } else if pending[slot] != nil {
                await scheduler.cancel(slot: slot)
            }
        }
        return .reconciled
    }

    private func desiredRequest(
        _ slot: HomeSlot, snapshot: UsageSnapshot?, now: Date
    ) async -> ResetRequest? {
        guard await preferences.notificationOptIn(slot) == true, let snapshot,
            snapshot.source(for: slot.product)?.state != .incompatible
        else { return nil }
        let (resolution, _) = HomeSlotResolver.resolve(slot, in: snapshot, now: now)
        guard case .window(let window) = resolution, let resetsAt = window.resetsAt,
            resetsAt > now
        else { return nil }
        return ResetRequest(slot: slot, fireAt: resetsAt)
    }
}
