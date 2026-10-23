import Foundation

/// One stage that runs after a snapshot commits: reminders, Live Activities, or the Watch.
public protocol AfterCommitStep: Sendable {
    func afterCommit(_ event: CommitEvent) async
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
            await notifications.afterCommit(event)
        case .app:
            await runAll(event)
            try? await reader.transact { $0.needsAppReconcile = false }
        }
    }

    /// Repeats the whole pipeline for the committed snapshot when a widget commit left work.
    public func reconcilePending() async {
        guard let state = try? await reader.load(), state.needsAppReconcile,
            let snapshot = state.snapshot
        else { return }
        await run(CommitEvent(snapshot: snapshot, process: .app))
    }

    /// A transport-status change with no new snapshot still reaches widgets and the Watch.
    public func statusChanged(_ event: CommitEvent) async {
        reloader.reloadWidgets()
        await watch?.afterCommit(event)
    }

    private func runAll(_ event: CommitEvent) async {
        reloader.reloadWidgets()
        await notifications.afterCommit(event)
        await liveActivities.afterCommit(event)
        await watch?.afterCommit(event)
    }
}
