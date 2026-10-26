import Foundation
import ResetRadarDomain

public enum ActivityStartOutcome: Sendable, Equatable {
    case started
    case alreadyRunning
    /// Disabled by the user, a weekly account window, or no live window to show.
    case unavailable
    case failed
}

/// Keeps at most one Reset Live Activity per five-hour account window. `run` only updates and
/// ends; an activity starts solely from the foreground `start` action.
public actor ReconcileLiveActivities: AfterCommitStep {
    private let visible: VisibleSnapshot
    private var starting: Set<AccountWindow> = []
    private let controller: any LiveActivityController
    private let clock: any AppClock

    public init(
        visible: VisibleSnapshot, controller: any LiveActivityController, clock: any AppClock
    ) {
        self.visible = visible
        self.controller = controller
        self.clock = clock
    }

    public func afterCommitOutcome(_ event: CommitEvent) async -> AfterCommitOutcome {
        await reconcile()
    }

    public func run() async {
        _ = await reconcile()
    }

    private func reconcile() async -> AfterCommitOutcome {
        let enabled = await controller.areActivitiesEnabled()
        // An unreadable store leaves the running activities alone.
        let snapshot: UsageSnapshot?
        do { snapshot = try await visible.load() } catch { return .retryable }
        let now = clock.now
        let running = await controller.list()
        guard enabled else {
            for activity in running {
                await controller.end(accountWindow: activity.accountWindow)
            }
            return .complete
        }
        var valid: [(RunningActivity, Live)] = []
        for activity in running {
            guard
                let live = Self.live(
                    activity.accountWindow, snapshot, now, startedAt: activity.startedAt),
                live.content.windowID == activity.windowID,
                live.content.resetsAt <= activity.startedAt.addingTimeInterval(8 * 60 * 60)
            else {
                await controller.end(accountWindow: activity.accountWindow)
                continue
            }
            valid.append((activity, live))
        }
        let numbers = Dictionary(
            uniqueKeysWithValues: (snapshot?.accounts ?? []).map { ($0.id, $0.number) })
        valid.sort {
            if $0.1.content.resetsAt != $1.1.content.resetsAt {
                return $0.1.content.resetsAt < $1.1.content.resetsAt
            }
            return (numbers[$0.0.accountWindow.accountID] ?? Int.max)
                < (numbers[$1.0.accountWindow.accountID] ?? Int.max)
        }
        for (index, item) in valid.enumerated() {
            let activity = item.0
            let live = item.1
            await controller.update(
                accountWindow: activity.accountWindow,
                content: Self.content(live.content, relevanceScore: Double(valid.count - index)),
                staleDate: live.staleDate)
        }
        return .complete
    }

    /// Starts the activity for an account window from a foreground Account Details action only.
    public func start(accountWindow: AccountWindow) async -> ActivityStartOutcome {
        // Two overlapping taps must not both pass the running check below.
        guard starting.insert(accountWindow).inserted else { return .alreadyRunning }
        defer { starting.remove(accountWindow) }
        let now = clock.now
        guard accountWindow.window == .fiveHour, await controller.areActivitiesEnabled(),
            let live = Self.live(accountWindow, await visible.current(), now, startedAt: now)
        else { return .unavailable }
        // A newly started activity must be based on current data and fit ActivityKit's active
        // lifetime. Existing activities intentionally remain visible as stale until their known
        // reset, where a later app execution ends them.
        guard live.isCurrent,
            live.content.resetsAt <= now.addingTimeInterval(8 * 60 * 60)
        else { return .unavailable }
        if await controller.list().contains(where: { $0.accountWindow == accountWindow }) {
            return .alreadyRunning
        }
        do {
            try await controller.start(
                accountWindow: accountWindow, content: live.content,
                staleDate: live.staleDate)
            _ = await reconcile()
            return .started
        } catch {
            return .failed
        }
    }

    /// Foreground Account Details stop action. The controller owns the framework dismissal.
    public func stop(accountWindow: AccountWindow) async {
        await controller.end(accountWindow: accountWindow)
    }

    public func isRunning(accountWindow: AccountWindow) async -> Bool {
        await controller.list().contains { $0.accountWindow == accountWindow }
    }

    private struct Live {
        let content: ActivityContent
        let staleDate: Date
        let isCurrent: Bool
    }

    /// Content for a standard account window that is present, observed, and not yet reset.
    /// `staleDate` is
    /// the earlier of the observation's current-data expiry and the reset.
    private static func live(
        _ accountWindow: AccountWindow, _ snap: UsageSnapshot?, _ now: Date, startedAt: Date
    ) -> Live? {
        guard let snap,
            let account = snap.accounts.first(where: { $0.id == accountWindow.accountID }),
            let source = snap.source(for: accountWindow.accountID), source.state != .incompatible
        else { return nil }
        let (resolution, _) = AccountWindowResolver.resolve(
            accountWindow, in: snap, now: now)
        guard case .window(let window) = resolution, let observation = window.observation,
            let resetsAt = window.resetsAt, resetsAt > now
        else { return nil }
        let expiry = observation.observedAt.addingTimeInterval(
            CurrentDataWindow.seconds(for: window.product))
        let presentation = PresentationPolicy.derive(window: window, source: source, now: now)
        return Live(
            content: ActivityContent(
                windowID: window.id, usedPercent: observation.usedPercent, resetsAt: resetsAt,
                observedAt: observation.observedAt, startedAt: startedAt,
                accountLabel: account.effectiveDisplayLabel, product: account.product,
                window: .standard(accountWindow.window), sourceState: source.state,
                fractionDigits: observation.fractionDigits),
            staleDate: min(expiry, resetsAt), isCurrent: presentation.state == .current)
    }

    private static func content(
        _ content: ActivityContent, relevanceScore: Double
    ) -> ActivityContent {
        ActivityContent(
            windowID: content.windowID, usedPercent: content.usedPercent,
            resetsAt: content.resetsAt, observedAt: content.observedAt,
            startedAt: content.startedAt, accountLabel: content.accountLabel,
            product: content.product, window: content.window, sourceState: content.sourceState,
            fractionDigits: content.fractionDigits, relevanceScore: relevanceScore)
    }
}
