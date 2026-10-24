import Foundation
import ResetRadarDomain

/// Keeps exactly one reset reminder per opted-in account window. It never requests authorization.
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
            await scheduler.pending().map { ($0.accountWindow, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let configured = AccountDisplayOrder.sorted(snapshot?.accounts ?? []).flatMap { account in
            AccountWindow.StandardWindow.allCases.map {
                AccountWindow(accountID: account.id, window: $0)
            }
        }
        let configuredSet = Set(configured)
        var outcome = ReconcileOutcome.reconciled
        for accountWindow in configured {
            let desired = await desiredRequest(accountWindow, snapshot: snapshot, now: now)
            if let desired, authorized {
                guard pending[accountWindow]?.fireAt != desired.fireAt else { continue }
                do {
                    try await scheduler.schedule(desired)
                } catch {
                    outcome = .retryable  // the remaining slots still reconcile
                }
            } else if pending[accountWindow] != nil {
                await scheduler.cancel(accountWindow: accountWindow)
            }
        }
        for removed in Set(pending.keys).subtracting(configuredSet) {
            await scheduler.cancel(accountWindow: removed)
        }
        return outcome
    }

    private func desiredRequest(
        _ accountWindow: AccountWindow, snapshot: UsageSnapshot?, now: Date
    ) async -> ResetRequest? {
        guard await preferences.notificationOptIn(accountWindow) == true, let snapshot,
            snapshot.source(for: accountWindow.accountID)?.state != .incompatible
        else { return nil }
        let (resolution, _) = AccountWindowResolver.resolve(accountWindow, in: snapshot, now: now)
        guard case .window(let window) = resolution, let resetsAt = window.resetsAt,
            resetsAt > now
        else { return nil }
        return ResetRequest(accountWindow: accountWindow, fireAt: resetsAt)
    }
}
