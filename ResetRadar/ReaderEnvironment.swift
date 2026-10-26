import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarUI

/// The iOS process's object graph and its scene, ticker, and manual-refresh drivers. Policy
/// stays in the use cases: this type only routes events and publishes their read models.
@MainActor
final class ReaderEnvironment: ObservableObject {
    enum PairingStep: Equatable {
        case entry
        /// The decoded package's code is shown; nothing has been saved or sent.
        case confirm(code: String)
        case saving
    }

    @Published private(set) var home = HomeReadModel(accounts: [], nextChange: nil)
    @Published private(set) var details = UsageDetailsReadModel(
        accounts: [], macLive: nil, transport: .notPaired)
    /// `nil` before the first load or while the local store cannot be read.
    @Published private(set) var pairing: PairingStatusReadModel?
    @Published private(set) var loaded = false
    @Published private(set) var refresh: RefreshActivity?
    @Published private(set) var pairingStep = PairingStep.entry
    @Published private(set) var pairingMessage: String?
    @Published private(set) var forgetMessage: String?
    @Published private(set) var notificationAuthorization = NotificationAuthorization.notDetermined
    @Published private(set) var liveActivitiesEnabled: Bool?
    @Published private(set) var selectedAccountID: AccountID?

    let hasWatchStage: Bool

    private let clock: any AppClock
    private let refreshClock: ForegroundWaitClock
    private let system: any ReaderSystemStatus
    private let selection: any AccountSelectionStore
    private let loadHome: LoadHome
    private let loadDetails: LoadUsageDetails
    private let loadPairing: LoadPairingStatus
    /// Internal so tests can drive one ingest exactly as the scene and ticker drivers do.
    let ingest: IngestRelaySnapshot
    private let requestRefresh: RequestMacRefresh
    private let acceptPairing: AcceptPairing
    private let forgetMac: ForgetMac
    private let exportDiagnostics: ExportDiagnostics
    private var preview: PairingPreview?
    private var activation: Task<Void, Never>?
    private var ticker: Task<Void, Never>?
    private var changeReload: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    /// Pull-to-refresh callers, resumed once the request is accepted or the Refresh ends.
    private var acceptanceWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    /// Advanced by Forget Mac, so a refresh that outlives it reports nothing.
    private var refreshGeneration = 0
    private var active = false

    init(dependencies: ReaderDependencies) {
        let deps = dependencies
        clock = deps.clock
        refreshClock = ForegroundWaitClock(base: deps.clock)
        system = deps.system
        selection = deps.selection
        hasWatchStage = deps.hasWatchStage
        let reloader = PendingSchedulingReloader()
        // Scheduling replaces the notification and Live Activity steps; WatchSync adds the
        // Watch stage.
        let afterCommit = AfterCommitPipeline(
            reader: deps.reader, reloader: reloader, notifications: PendingSchedulingStep(),
            liveActivities: PendingSchedulingStep(), watch: nil)
        let visible = VisibleSnapshot(snapshots: deps.snapshots, reader: deps.reader)
        let ingest = IngestRelaySnapshot(
            reader: deps.reader, secrets: deps.secrets, cipher: deps.cipher, relay: deps.relay,
            random: deps.random, clock: deps.clock, diagnostics: deps.diagnostics,
            afterCommit: afterCommit)
        self.ingest = ingest
        loadHome = LoadHome(visible: visible, clock: deps.clock)
        loadDetails = LoadUsageDetails(visible: visible, clock: deps.clock)
        loadPairing = LoadPairingStatus(reader: deps.reader, hasWatchStage: deps.hasWatchStage)
        requestRefresh = RequestMacRefresh(
            reader: deps.reader, secrets: deps.secrets, relay: deps.relay, random: deps.random,
            clock: refreshClock, ingest: ingest)
        acceptPairing = AcceptPairing(
            reader: deps.reader, secrets: deps.secrets, relay: deps.relay, cipher: deps.cipher,
            codec: deps.codec, clock: deps.clock, afterCommit: afterCommit)
        // Until WatchConnectivity is wired there is no link: a saved clear stays pending.
        forgetMac = ForgetMac(
            reader: deps.reader, secrets: deps.secrets,
            notifications: PendingNotificationScheduler(),
            activities: PendingLiveActivityController(), reloader: reloader, watch: nil)
        exportDiagnostics = ExportDiagnostics(diagnostics: deps.diagnostics, clock: deps.clock)
        selectedAccountID = deps.selection.load()
    }

    var setupStep: ReaderSetupStep? {
        guard loaded else { return nil }
        return ReaderSetupStep.derive(
            pairing: pairing, transport: details.transport,
            hasVisibleSnapshot: details.macLive != nil, sources: home.accounts.map(\.source))
    }

    func accountDetails(_ accountID: AccountID) -> AccountDetails? {
        details.accounts.first { $0.account.id == accountID }
    }

    // MARK: scene

    /// Launch recovery, then the foreground read, then the 60-second ticker. Overlapping
    /// activations share one run, so a launch never sends two activation requests.
    func sceneBecameActive() async {
        active = true
        if activation == nil {
            activation = Task {
                await acceptPairing.recoverStaging()
                // Only an unfinished Forget Mac is retried: without its marker, `retryCleanup`
                // would treat an intact pairing as a forget that never ran.
                if await loadPairing.load()?.cleanupPending == true {
                    _ = await forgetMac.retryCleanup()
                }
                _ = await acceptPairing.resumeActivation()
                await reload()
                _ = await ingest.run(trigger: .foregroundActivation, inAppProcess: true)
                await reload()
                activation = nil
            }
        }
        await activation?.value
        if active { startTicker() }
    }

    /// Stops foreground work at its next wait. An in-flight relay read finishes, so leaving the
    /// foreground never turns into a false offline status or a repeated request.
    func sceneBecameInactive() {
        active = false
        ticker?.cancel()
        ticker = nil
        changeReload?.cancel()
        changeReload = nil
        if refresh?.isRunning == true { refreshClock.cancelWaits() }
    }

    func reload() async {
        home = await loadHome.load()
        details = await loadDetails.load()
        pairing = await loadPairing.load()
        notificationAuthorization = await system.notificationAuthorization()
        liveActivitiesEnabled = await system.liveActivitiesEnabled()
        loaded = true
        resolveSelection()
        scheduleChangeReload()
    }

    func foregroundTick() async {
        _ = await ingest.run(trigger: .foregroundTick, inAppProcess: true)
        await reload()
    }

    private func startTicker() {
        guard ticker == nil else { return }
        ticker = Task { [clock] in
            while !Task.isCancelled {
                do {
                    try await clock.sleep(for: .seconds(ReaderRefreshPolicy.tickInterval))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                // Unstructured, so cancelling the ticker never cancels a read mid-flight.
                await Task { await self.foregroundTick() }.value
            }
        }
    }

    /// Reloads at the next presentation change, so stale and post-reset states appear on time.
    private func scheduleChangeReload() {
        changeReload?.cancel()
        changeReload = nil
        guard active else { return }
        let instants =
            [home.nextChange]
            + details.accounts.flatMap(\.windows).map(\.nextChange)
        guard let next = instants.compactMap({ $0 }).filter({ $0 > clock.now }).min() else {
            return
        }
        let delay = next.timeIntervalSince(clock.now)
        changeReload = Task { [clock] in
            do {
                try await clock.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self.reload()
        }
    }

    // MARK: selection

    func select(_ accountID: AccountID?) {
        selectedAccountID = accountID
        selection.save(accountID)
    }

    private func resolveSelection() {
        let resolved = AccountSelection.resolve(
            current: selectedAccountID, stored: selection.load(),
            ordered: home.accounts.map(\.account.id))
        if resolved != selectedAccountID { select(resolved) }
    }

    // MARK: refresh

    /// Home Refresh: one `allCodex` request when Codex is configured, and the ordinary relay
    /// read that can update Claude Code.
    func refreshHome() async {
        let products = Set(home.accounts.map(\.source.product))
        await runRefresh(.home) { refresh, progress in
            await refresh.run(scope: products, codexTarget: .allCodex, progress: progress)
        }
    }

    /// Account Details Refresh: a Codex account targets only its opaque ID; a Claude Code
    /// account performs the ordinary relay read without posting.
    func refreshAccount(_ accountID: AccountID) async {
        guard let account = accountDetails(accountID) else { return }
        let product = account.source.product
        await runRefresh(.account(accountID)) { refresh, progress in
            await refresh.run(
                scope: [product], codexTarget: .account(accountID), progress: progress)
        }
    }

    /// Pull to refresh: returns once the relay was read and any Mac request was accepted, so the
    /// system spinner never stands in for the Mac's 45-second wait. The Refresh continues and
    /// reports its result in the account feedback.
    func pullToRefresh(account: AccountID? = nil) async {
        if case .waitingForMac = refresh?.phase { return }
        let id = UUID()
        await withCheckedContinuation { (accepted: CheckedContinuation<Void, Never>) in
            acceptanceWaiters[id] = accepted
            Task {
                if let account {
                    await refreshAccount(account)
                } else {
                    await refreshHome()
                }
                // Only this call's waiter: a later pull may already wait on a newer Refresh.
                acceptanceWaiters.removeValue(forKey: id)?.resume()
            }
        }
    }

    private func resumeAcceptanceWaiters() {
        let waiters = acceptanceWaiters.values
        acceptanceWaiters = [:]
        for waiter in waiters { waiter.resume() }
    }

    private func runRefresh(
        _ scope: RefreshActivity.Scope,
        _ operation:
            @escaping @Sendable (
                RequestMacRefresh, @escaping @Sendable (MacRefreshProgress) async -> Void
            ) async -> MacRefreshOutcome
    ) async {
        if let running = refreshTask {
            await running.value
            return
        }
        refresh = RefreshActivity(scope: scope)
        refreshClock.begin()
        let generation = refreshGeneration
        let task = Task { [requestRefresh] in
            let outcome = await operation(requestRefresh) { step in
                await self.report(step, scope: scope, generation: generation)
            }
            await self.finish(outcome, scope: scope, generation: generation)
        }
        refreshTask = task
        await task.value
    }

    private func report(
        _ step: MacRefreshProgress, scope: RefreshActivity.Scope, generation: Int
    ) {
        guard generation == refreshGeneration, refresh?.scope == scope,
            refresh?.isRunning == true
        else { return }
        switch step {
        case .relayContacted: refresh?.phase = .relayContacted
        case .waitingForMac(let deadline):
            refresh?.phase = .waitingForMac(deadline: deadline)
            resumeAcceptanceWaiters()
        }
    }

    private func finish(
        _ outcome: MacRefreshOutcome, scope: RefreshActivity.Scope, generation: Int
    ) async {
        refreshTask = nil
        resumeAcceptanceWaiters()
        if generation == refreshGeneration {
            let cancelled = refreshClock.waitsCancelled && outcome == .timedOut
            refresh = RefreshActivity(
                scope: scope, phase: cancelled ? .cancelled : .finished(outcome))
        }
        await reload()
    }
}

extension ReaderEnvironment {
    // MARK: pairing

    /// Decodes a scanned or owner-pasted package without saving or sending anything.
    func previewPairing(_ text: String) {
        let package = text.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let decoded = try acceptPairing.preview(package)
            preview = decoded
            pairingStep = .confirm(code: decoded.confirmationCode)
            pairingMessage = nil
        } catch {
            cancelPairing()
            pairingMessage = PairingSyncText.pairingError(error)
        }
    }

    func reportCameraUnavailable() {
        pairingMessage = "Camera scanning is unavailable. Paste the Pairing Package instead."
    }

    func cancelPairing() {
        preview = nil
        pairingStep = .entry
        pairingMessage = nil
    }

    /// The owner confirmed that both devices show the same code.
    func confirmPairing() async {
        guard let preview, pairingStep != .saving else { return }
        pairingStep = .saving
        let outcome = await acceptPairing.accept(preview, confirmed: true)
        self.preview = nil
        pairingStep = .entry
        pairingMessage = PairingSyncText.pairingOutcome(outcome)
        await reload()
        if outcome == .paired || outcome == .awaitingActivation {
            _ = await ingest.run(trigger: .foregroundActivation, inAppProcess: true)
            await reload()
        }
    }

    /// Retries a saved pairing's activation; a rejection returns the device to setup.
    func retryActivation() async {
        let outcome = await acceptPairing.resumeActivation()
        if outcome != .failed(.nothingToResume) {
            pairingMessage = PairingSyncText.pairingOutcome(outcome)
        }
        await reload()
        if outcome == .paired {
            _ = await ingest.run(trigger: .foregroundActivation, inAppProcess: true)
            await reload()
        }
    }

    // MARK: forget

    func forget() async {
        cancelPairing()
        refreshGeneration += 1
        refreshClock.cancelWaits()
        forgetMessage = PairingSyncText.forgetOutcome(await forgetMac.forget())
        refresh = nil
        await reload()
    }

    func retryCleanup() async {
        forgetMessage = PairingSyncText.forgetOutcome(await forgetMac.retryCleanup())
        await reload()
    }

    // MARK: diagnostics

    /// Writes the owner-confirmed redacted export to a temporary file for sharing.
    func exportDiagnosticsFile() async throws -> URL {
        let export = try await exportDiagnostics.export(confirmed: true)
        let url = FileManager.default.temporaryDirectory.appending(
            path: "ResetRadar-diagnostics.json")
        try export.encoded().write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }
}
