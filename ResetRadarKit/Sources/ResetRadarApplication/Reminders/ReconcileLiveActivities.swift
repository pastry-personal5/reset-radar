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

    public func afterCommit(_ event: CommitEvent) async {
        await run()
    }

    public func run() async {
        let enabled = await controller.areActivitiesEnabled()
        // An unreadable store leaves the running activities alone.
        let snapshot: UsageSnapshot?
        do { snapshot = try await visible.load() } catch { return }
        let now = clock.now
        for activity in await controller.list() {
            guard enabled, let live = Self.live(activity.accountWindow, snapshot, now),
                live.content.windowID == activity.windowID
            else {
                await controller.end(accountWindow: activity.accountWindow)
                continue
            }
            await controller.update(
                accountWindow: activity.accountWindow, content: live.content,
                staleDate: live.staleDate)
        }
    }

    /// Starts the activity for an account window from a foreground Account Details action only.
    public func start(accountWindow: AccountWindow) async -> ActivityStartOutcome {
        // Two overlapping taps must not both pass the running check below.
        guard starting.insert(accountWindow).inserted else { return .alreadyRunning }
        defer { starting.remove(accountWindow) }
        guard accountWindow.window == .fiveHour, await controller.areActivitiesEnabled(),
            let live = Self.live(accountWindow, await visible.current(), clock.now)
        else { return .unavailable }
        if await controller.list().contains(where: { $0.accountWindow == accountWindow }) {
            return .alreadyRunning
        }
        do {
            try await controller.start(
                accountWindow: accountWindow, content: live.content,
                staleDate: live.staleDate)
            return .started
        } catch {
            return .failed
        }
    }

    private struct Live {
        let content: ActivityContent
        let staleDate: Date
    }

    /// Content for a standard account window that is present, observed, and not yet reset.
    /// `staleDate` is
    /// the earlier of the observation's current-data expiry and the reset.
    private static func live(
        _ accountWindow: AccountWindow, _ snap: UsageSnapshot?, _ now: Date
    ) -> Live? {
        guard let snap else { return nil }
        let (resolution, _) = AccountWindowResolver.resolve(
            accountWindow, in: snap, now: now)
        guard case .window(let window) = resolution, let observation = window.observation,
            let resetsAt = window.resetsAt, resetsAt > now
        else { return nil }
        let expiry = observation.observedAt.addingTimeInterval(
            CurrentDataWindow.seconds(for: window.product))
        return Live(
            content: ActivityContent(
                windowID: window.id, usedPercent: observation.usedPercent, resetsAt: resetsAt,
                observedAt: observation.observedAt),
            staleDate: min(expiry, resetsAt))
    }
}
