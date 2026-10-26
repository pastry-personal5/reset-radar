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

    public func afterCommitOutcome(_ event: CommitEvent) async -> AfterCommitOutcome {
        await run(onIOS: gate != nil) == .reconciled ? .complete : .retryable
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
        let authorization = await scheduler.authorization()
        let maySchedule = authorization == .authorized || authorization == .provisional
        let pending = Dictionary(
            await scheduler.pending().map { ($0.selection, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let configured = Self.configuredSelections(snapshot)
        let ownedBefore = await scheduler.ownedPendingIdentifiers()
        let result = await apply(
            configured: configured, snapshot: snapshot, now: now, maySchedule: maySchedule,
            pending: pending)
        await removeObsolete(
            configured: Set(configured), pending: pending, ownedBefore: ownedBefore)
        return await verifiedOutcome(expected: result.expected, initial: result.outcome)
    }

    private static func configuredSelections(_ snapshot: UsageSnapshot?) -> [WindowSelection] {
        let standards = AccountDisplayOrder.sorted(snapshot?.accounts ?? []).flatMap { account in
            AccountWindow.StandardWindow.allCases.map {
                WindowSelection.standard(
                    AccountWindow(accountID: account.id, window: $0))
            }
        }
        let additional = (snapshot?.windows ?? []).filter { !$0.isDefaultLimit }.map {
            WindowSelection.additional($0.id)
        }
        return standards + additional
    }

    private func apply(
        configured: [WindowSelection], snapshot: UsageSnapshot?, now: Date, maySchedule: Bool,
        pending: [WindowSelection: ResetRequest]
    ) async -> (expected: [WindowSelection: ResetRequest], outcome: ReconcileOutcome) {
        var expected: [WindowSelection: ResetRequest] = [:]
        var outcome = ReconcileOutcome.reconciled
        for selection in configured {
            let desired = await desiredRequest(selection, snapshot: snapshot, now: now)
            if let desired, maySchedule {
                expected[selection] = desired
                guard pending[selection] != desired else { continue }
                do {
                    try await scheduler.schedule(desired)
                } catch {
                    outcome = .retryable  // the remaining slots still reconcile
                }
            } else if pending[selection] != nil {
                await scheduler.cancel(selection: selection)
            }
        }
        return (expected, outcome)
    }

    private func removeObsolete(
        configured: Set<WindowSelection>, pending: [WindowSelection: ResetRequest],
        ownedBefore: Set<String>
    ) async {
        for removed in Set(pending.keys).subtracting(configured) {
            await scheduler.cancel(selection: removed)
        }
        // The typed view intentionally excludes malformed owned requests. Remove those by their
        // reserved identifier while leaving all other app notifications untouched.
        let typedIdentifiers = Set(pending.values.map(\.identifier))
        for identifier in ownedBefore.subtracting(typedIdentifiers) {
            await scheduler.cancel(identifier: identifier)
        }
    }

    private func verifiedOutcome(
        expected: [WindowSelection: ResetRequest], initial: ReconcileOutcome
    ) async -> ReconcileOutcome {
        // `removePending...` has no completion callback. Read back once so a failed removal is
        // retained as durable retry work rather than being reported as reconciled.
        let typedAfter = Dictionary(
            await scheduler.pending().map { ($0.selection, $0) },
            uniquingKeysWith: { first, _ in first })
        let remaining = await scheduler.ownedPendingIdentifiers()
        if typedAfter != expected || remaining != Set(expected.values.map(\.identifier)) {
            return .retryable
        }
        return initial
    }

    private func desiredRequest(
        _ selection: WindowSelection, snapshot: UsageSnapshot?, now: Date
    ) async -> ResetRequest? {
        guard await preferences.notificationOptIn(selection) == true, let snapshot,
            let account = snapshot.accounts.first(where: { $0.id == selection.accountID }),
            let source = snapshot.source(for: selection.accountID), source.state != .incompatible
        else { return nil }
        let (resolution, _) = WindowSelectionResolver.resolve(selection, in: snapshot, now: now)
        guard case .window(let window) = resolution, let resetsAt = window.resetsAt,
            resetsAt > now
        else { return nil }
        let descriptor: WindowDisplayDescriptor
        switch selection {
        case .standard(let accountWindow):
            descriptor = .standard(accountWindow.window)
        case .additional:
            descriptor = .additional(
                label: Self.bounded(window.label), durationMinutes: window.durationMinutes)
        }
        return ResetRequest(
            selection: selection, fireAt: resetsAt, accountLabel: account.effectiveDisplayLabel,
            product: account.product, window: descriptor, sourceState: source.state,
            fractionDigits: window.observation?.fractionDigits)
    }

    private static func bounded(_ value: String?, utf8Limit: Int = 96) -> String? {
        guard let value, !value.isEmpty else { return nil }
        var result = ""
        for character in value {
            let candidate = result + String(character)
            guard candidate.utf8.count <= utf8Limit else { break }
            result = candidate
        }
        return result.isEmpty ? nil : result
    }
}
