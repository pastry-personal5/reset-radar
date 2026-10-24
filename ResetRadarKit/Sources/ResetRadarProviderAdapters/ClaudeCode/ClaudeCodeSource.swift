import Foundation
import ResetRadarApplication
import ResetRadarDomain

/// Collects Claude Code usage from the per-session records the status-line helper writes. It
/// never starts a Claude Code turn: freshness comes only from what the helper recorded.
public actor ClaudeCodeSource: UsageSource {
    /// The safe version carried before any valid observation exists.
    public static let unobservedVersion = "unknown"
    public static let coalescingInterval: TimeInterval = 2

    public nonisolated let accountID: AccountID
    public nonisolated let product = ProductID.claudeCode
    public nonisolated let updates: AsyncStream<SourceSnapshot>

    let file: SessionRecordFile
    let watchFactory: any DirectoryWatchFactory
    let probe: any ClaudeCodeInstallationProbing
    let diagnostics: any DiagnosticsSink
    let clock: any AppClock
    let updateContinuation: AsyncStream<SourceSnapshot>.Continuation

    var started = false
    var terminallyStopped = false
    /// Setup is absent; only a configuration change or explicit refresh re-probes.
    var awaitingConfiguration = false
    var generation: UInt64 = 0
    var watch: (any DirectoryWatchSession)?
    var watchTask: Task<Void, Never>?
    var scanTask: Task<ReadReceipt, Never>?
    var coalesceTask: Task<Void, Never>?
    var retryTask: Task<Void, Never>?
    var trailingScanNeeded = false
    var schedule = ClaudeCodeRevalidationSchedule()
    var retryDeadline: Date?
    var lastEmitted: SourceSnapshot?
    var lastVersion = ClaudeCodeSource.unobservedVersion
    /// Physical scans performed, for tests and diagnostics of coalescing.
    var scanCount = 0

    public init(
        accountID: AccountID, file: SessionRecordFile,
        watchFactory: any DirectoryWatchFactory = DispatchDirectoryWatchFactory(),
        probe: any ClaudeCodeInstallationProbing, diagnostics: any DiagnosticsSink,
        clock: any AppClock
    ) {
        let pair = AsyncStream<SourceSnapshot>.makeStream()
        self.accountID = accountID
        self.file = file
        self.watchFactory = watchFactory
        self.probe = probe
        self.diagnostics = diagnostics
        self.clock = clock
        updates = pair.stream
        updateContinuation = pair.continuation
    }

    deinit {
        watchTask?.cancel()
        scanTask?.cancel()
        coalesceTask?.cancel()
        retryTask?.cancel()
        watch?.cancel()
        updateContinuation.finish()
    }

    public func start() async throws {
        guard !terminallyStopped else { throw ClaudeCodeSourceError.stopped }
        guard !started else { return }
        started = true
        await activate()
    }

    /// Re-probes setup after the owner installed, restored, or repaired the status line.
    public func configurationChanged() async {
        guard started, !terminallyStopped else { return }
        retryDeadline = nil
        schedule.reset()
        await activate()
    }

    public func refresh() async -> ReadReceipt {
        guard started, !terminallyStopped else { return .unavailable(sourceState: .unavailable) }
        if awaitingConfiguration {
            await activate()
            if awaitingConfiguration { return .unavailable(sourceState: .unavailable) }
        }
        if let retryDeadline, retryDeadline > clock.now {
            return .deferred(retryAt: retryDeadline, sourceState: .sourceOffline)
        }
        if watch == nil, retryDeadline != nil {
            await revalidate()
            if let retryDeadline {
                return .deferred(retryAt: retryDeadline, sourceState: .sourceOffline)
            }
        }
        return await scanNow()
    }

    public func stop() async {
        guard !terminallyStopped else { return }
        terminallyStopped = true
        generation &+= 1
        coalesceTask?.cancel()
        retryTask?.cancel()
        scanTask?.cancel()
        watchTask?.cancel()
        watch?.cancel()
        coalesceTask = nil
        retryTask = nil
        scanTask = nil
        watchTask = nil
        watch = nil
        updateContinuation.finish()
    }
}
