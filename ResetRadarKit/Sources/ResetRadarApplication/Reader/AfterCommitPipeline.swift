import Foundation

/// One stage that runs after a snapshot commits: reminders, Live Activities, or the Watch.
public protocol AfterCommitStep: Sendable {
    func afterCommitOutcome(_ event: CommitEvent) async -> AfterCommitOutcome
}

public enum AfterCommitOutcome: Sendable, Equatable {
    case complete
    case retryable
}

/// Runs the stages in order: widget reload, reset notifications, Live Activities, Watch. The
/// iPad omits the Watch stage. A widget-process commit reconciles notifications only, from the
/// already granted opt-in state; the persisted `needsAppReconcile` flag makes the next app run
/// do the rest.
public struct AfterCommitPipeline: Sendable {
    private let reader: any ReaderStore
    private let reloader: any SurfaceReloader
    private let notifications: any AfterCommitStep
    private let liveActivities: any AfterCommitStep
    private let watch: (any AfterCommitStep)?

    public init(
        reader: any ReaderStore, reloader: any SurfaceReloader,
        notifications: any AfterCommitStep, liveActivities: any AfterCommitStep,
        watch: (any AfterCommitStep)?
    ) {
        self.reader = reader
        self.reloader = reloader
        self.notifications = notifications
        self.liveActivities = liveActivities
        self.watch = watch
    }

    public func run(_ event: CommitEvent) async {
        switch event.process {
        case .widget:
            _ = await notifications.afterCommitOutcome(event)
        case .app:
            let outcome = await runAll(event)
            guard outcome == .complete else { return }
            // A widget commit during the run sets the flag for a newer snapshot; keep it then.
            _ = try? await reader.transact { state in
                let isCurrent =
                    state.snapshot?.publisherID == event.publisherID
                    && state.committedSequence == event.relaySequence
                if isCurrent {
                    state.needsAppReconcile = false
                }
            }
        }
    }

    /// Repeats the whole pipeline for the committed snapshot when a widget commit left work.
    public func reconcilePending() async {
        guard let state = try? await reader.load(), state.needsAppReconcile,
            let snapshot = state.snapshot
        else { return }
        await run(
            CommitEvent(
                snapshot: snapshot, process: .app, relaySequence: state.committedSequence ?? 0))
    }

    /// Reconciles the currently committed cache on an app activation. This catches permission,
    /// clock, and time-zone changes even when no new relay snapshot arrives.
    public func reconcileCurrent() async {
        guard let state = try? await reader.load(), let snapshot = state.snapshot else { return }
        await run(
            CommitEvent(
                snapshot: snapshot, process: .app, relaySequence: state.committedSequence ?? 0))
    }

    /// A transport-status change with no new snapshot still reaches widgets and the Watch.
    public func statusChanged(_ event: CommitEvent) async {
        reloader.reloadWidgets()
        _ = await watch?.afterCommitOutcome(event)
    }

    private func runAll(_ event: CommitEvent) async -> AfterCommitOutcome {
        reloader.reloadWidgets()
        guard await notifications.afterCommitOutcome(event) == .complete else { return .retryable }
        guard await liveActivities.afterCommitOutcome(event) == .complete else { return .retryable }
        guard await watch?.afterCommitOutcome(event) != .retryable else { return .retryable }
        return .complete
    }
}
