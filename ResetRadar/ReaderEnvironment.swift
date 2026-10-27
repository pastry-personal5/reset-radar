import BackgroundTasks
// This object intentionally owns the full iOS scene, refresh, pairing, and scheduling
// composition. Its private state is tightly coupled and tested through the single environment.
// swiftlint:disable file_length
import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarScheduling
import ResetRadarUI
import ResetRadarWatchSync
import UIKit

@MainActor
private struct ReaderScheduling {
    let notifications: any NotificationScheduler
    let activities: any LiveActivityController
    let setNotificationOptIn: SetNotificationOptIn
    let liveActivities: ReconcileLiveActivities
    let afterCommit: AfterCommitPipeline

    init(
        dependencies: ReaderDependencies, visible: VisibleSnapshot, reloader: any SurfaceReloader,
        watch: (any AfterCommitStep)?
    ) {
        let notifications = SystemNotificationScheduler()
        let activities: any LiveActivityController
        if dependencies.hasWatchStage, #available(iOS 16.1, *) {
            activities = SystemLiveActivityController()
        } else {
            activities = UnavailableLiveActivityController()
        }
        let reminders = ReconcileResetNotifications(
            visible: visible, preferences: dependencies.preferences, scheduler: notifications,
            gate: dependencies.notificationGate, clock: dependencies.clock)
        let liveActivities = ReconcileLiveActivities(
            visible: visible, controller: activities, clock: dependencies.clock)
        self.notifications = notifications
        self.activities = activities
        self.setNotificationOptIn = SetNotificationOptIn(
            preferences: dependencies.preferences, scheduler: notifications,
            reconcile: reminders)
        self.liveActivities = liveActivities
        afterCommit = AfterCommitPipeline(
            reader: dependencies.reader, reloader: reloader, notifications: reminders,
            liveActivities: liveActivities, watch: watch)
    }
}

// The iOS process's object graph and its scene, ticker, and manual-refresh drivers. Policy
// stays in the use cases: this type only routes events and publishes their read models.
@MainActor
// swiftlint:disable:next type_body_length
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
    @Published private(set) var backgroundRefreshAvailable = true
    @Published private(set) var selectedAccountID: AccountID?
    @Published private(set) var readerProfile: ReaderProfileState?
    @Published var proposedDeviceName = UIDevice.current.name

    let hasWatchStage: Bool

    private let clock: any AppClock
    private let reader: any ReaderStore
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
    private let reportProfile: ReportReaderProfile
    private let preferences: any PreferenceStore
    private let notifications: any NotificationScheduler
    private let setNotificationOptIn: SetNotificationOptIn
    private let liveActivities: ReconcileLiveActivities
    private let afterCommit: AfterCommitPipeline
    private let watchBridge: WCSessionBridge?
    private let watchForward: ForwardToWatch?
    private let confirmWatchErase: ConfirmWatchErase?
    private let exportDiagnostics: ExportDiagnostics
    private var preview: PairingPreview?
    private var activation: Task<Void, Never>?
    private var ticker: Task<Void, Never>?
    private var changeReload: Task<Void, Never>?
    private var systemChangeTasks: [Task<Void, Never>] = []
    private var refreshTask: Task<Void, Never>?
    /// Pull-to-refresh callers, resumed once the request is accepted or the Refresh ends.
    private var acceptanceWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    /// Advanced by Forget Mac, so a refresh that outlives it reports nothing.
    private var refreshGeneration = 0
    private var active = false

    init(dependencies: ReaderDependencies) {
        let deps = dependencies
        reader = deps.reader
        clock = deps.clock
        refreshClock = ForegroundWaitClock(base: deps.clock)
        system = deps.system
        selection = deps.selection
        preferences = deps.preferences
        hasWatchStage = deps.hasWatchStage
        let reloader = WidgetCenterReloader()
        let visible = VisibleSnapshot(snapshots: deps.snapshots, reader: deps.reader)
        let (bridge, forward) = Self.makeWatchComponents(deps)
        let scheduling = ReaderScheduling(
            dependencies: deps, visible: visible, reloader: reloader, watch: forward)
        notifications = scheduling.notifications
        setNotificationOptIn = scheduling.setNotificationOptIn
        // Scheduling replaces the notification and Live Activity steps; WatchSync adds the
        // Watch stage.
        liveActivities = scheduling.liveActivities
        afterCommit = scheduling.afterCommit
        watchBridge = bridge
        watchForward = forward
        let ingest = IngestRelaySnapshot(
            reader: deps.reader, secrets: deps.secrets, cipher: deps.cipher, relay: deps.relay,
            random: deps.random, clock: deps.clock, diagnostics: deps.diagnostics,
            afterCommit: scheduling.afterCommit)
        self.ingest = ingest
        loadHome = LoadHome(visible: visible, clock: deps.clock)
        loadDetails = LoadUsageDetails(visible: visible, clock: deps.clock)
        loadPairing = LoadPairingStatus(reader: deps.reader, hasWatchStage: deps.hasWatchStage)
        requestRefresh = RequestMacRefresh(
            reader: deps.reader, secrets: deps.secrets, relay: deps.relay, random: deps.random,
            clock: refreshClock, ingest: ingest)
        acceptPairing = AcceptPairing(
            reader: deps.reader, secrets: deps.secrets, relay: deps.relay, cipher: deps.cipher,
            codec: deps.codec, clock: deps.clock, afterCommit: scheduling.afterCommit)
        forgetMac = ForgetMac(
            reader: deps.reader, secrets: deps.secrets,
            notifications: scheduling.notifications, activities: scheduling.activities,
            reloader: reloader, watch: bridge.map { PhoneSideWatchLink(session: $0) })
        reportProfile = ReportReaderProfile(
            reader: deps.reader, secrets: deps.secrets, relay: deps.relay,
            cipher: deps.profileCipher)
        let confirmation = ConfirmWatchErase(
            reader: deps.reader, clock: deps.clock, forward: forward)
        confirmWatchErase = confirmation
        exportDiagnostics = ExportDiagnostics(diagnostics: deps.diagnostics, clock: deps.clock)
        selectedAccountID = deps.selection.load()
        backgroundRefreshAvailable = BackgroundRefreshDriver.register(environment: self)
        startWatch(bridge: bridge, forward: forward, ingest: ingest, confirmation: confirmation)
        observeSystemTimeChanges()
    }

    private static func makeWatchComponents(
        _ dependencies: ReaderDependencies
    ) -> (WCSessionBridge?, ForwardToWatch?) {
        let bridge = dependencies.hasWatchStage ? WCSessionBridge() : nil
        let forward = bridge.map {
            ForwardToWatch(
                reader: dependencies.reader, preferences: dependencies.preferences,
                watch: PhoneSideWatchLink(session: $0), clock: dependencies.clock)
        }
        return (bridge, forward)
    }

    private func startWatch(
        bridge: WCSessionBridge?, forward: ForwardToWatch?, ingest: IngestRelaySnapshot,
        confirmation: ConfirmWatchErase
    ) {
        guard let bridge else { return }
        let refreshWatch = forward.map {
            RefreshWatchFromPhone(ingest: ingest, forward: $0, clock: clock)
        }
        bridge.installRefreshHandler {
            guard let payload = await refreshWatch?.request() else { return .empty }
            return .payload(payload)
        }
        let receipts = bridge.incomingReceipts()
        let activations = bridge.activations()
        Task { [weak self] in
            await bridge.activate()
            for await receipt in receipts {
                _ = await confirmation.confirm(receipt)
                await self?.reload()
            }
        }
        Task {
            for await _ in activations {
                _ = await forward?.reconcileCurrent()
            }
        }
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

    func notificationOptIn(_ selection: WindowSelection) async -> Bool? {
        await preferences.notificationOptIn(selection)
    }

    func setNotificationOptIn(_ selection: WindowSelection, enabled: Bool) async -> OptInOutcome {
        let outcome = await setNotificationOptIn.set(selection, enabled: enabled)
        notificationAuthorization = await notifications.authorization()
        return outcome
    }

    func liveActivityRunning(_ accountWindow: AccountWindow) async -> Bool {
        await liveActivities.isRunning(accountWindow: accountWindow)
    }

    func toggleLiveActivity(_ accountWindow: AccountWindow) async -> ActivityStartOutcome? {
        if await liveActivities.isRunning(accountWindow: accountWindow) {
            await liveActivities.stop(accountWindow: accountWindow)
            return nil
        }
        return await liveActivities.start(accountWindow: accountWindow)
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
                await refreshAutomaticProfileIfNeeded()
                await watchForward?.activate()
                await afterCommit.reconcilePending()
                await afterCommit.reconcileCurrent()
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
        Task { await scheduleBackgroundRefresh() }
    }

    func runBackgroundRefresh(_ task: any BackgroundRefreshTask) async {
        await runBackgroundRefresh(task) { [weak self] in
            await self?.scheduleBackgroundRefresh()
        }
    }

    /// The injected resubmission boundary keeps expiration/completion behavior deterministic in
    /// tests without simulating `BGTaskScheduler` itself.
    func runBackgroundRefresh(
        _ task: any BackgroundRefreshTask,
        resubmit: @escaping @MainActor @Sendable () async -> Void
    ) async {
        let work = Task { [ingest] in
            await ingest.run(trigger: .backgroundTask, inAppProcess: true)
        }
        task.expirationHandler = { work.cancel() }
        let outcome = await work.value
        await resubmit()
        task.setTaskCompleted(success: outcome == .committed || outcome == .unchanged)
    }

    private func scheduleBackgroundRefresh() async {
        let state = try? await reader.load()
        let nextReset = state?.snapshot?.windows.compactMap(\.resetsAt).filter { $0 > clock.now }
            .min()
        backgroundRefreshAvailable = BackgroundRefreshDriver.submit(
            earliestBeginDate: ReaderRefreshPolicy.nextBackgroundRequest(
                lastSuccess: state?.lastSuccessAt, nextReset: nextReset, now: clock.now))
    }

    private func observeSystemTimeChanges() {
        let names: [Notification.Name] = [
            UIApplication.significantTimeChangeNotification,
            .NSSystemTimeZoneDidChange,
            .NSSystemClockDidChange,
        ]
        systemChangeTasks = names.map { name in
            Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: name) {
                    guard let self else { return }
                    await afterCommit.reconcileCurrent()
                    await reload()
                }
            }
        }
    }

    func reload() async {
        home = await loadHome.load()
        details = await loadDetails.load()
        pairing = await loadPairing.load()
        readerProfile = (try? await reader.load())?.readerProfile
        notificationAuthorization = await notifications.authorization()
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
            proposedDeviceName = UIDevice.current.name
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
        let name: ReaderProfileName
        do { name = try ReaderProfileName(validating: proposedDeviceName) } catch {
            pairingMessage = "Enter a visible device name up to 64 UTF-8 bytes."
            return
        }
        pairingStep = .saving
        let deviceClass: ReaderDeviceClass =
            UIDevice.current.userInterfaceIdiom == .pad
            ? .tablet : .phone
        let mode: ReaderNamingMode =
            proposedDeviceName == UIDevice.current.name
            ? .automatic : .custom
        let outcome = await acceptPairing.accept(
            preview, confirmed: true,
            profile: ReaderProfileState(
                name: name, namingMode: mode, deviceClass: deviceClass))
        self.preview = nil
        pairingStep = .entry
        pairingMessage = PairingSyncText.pairingOutcome(outcome)
        await reload()
        if outcome == .paired || outcome == .awaitingActivation {
            if outcome == .paired { _ = await reportProfile.retry() }
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
            _ = await reportProfile.retry()
            _ = await ingest.run(trigger: .foregroundActivation, inAppProcess: true)
            await reload()
        }
    }

    func saveDeviceName(_ value: String) async {
        let deviceClass: ReaderDeviceClass =
            UIDevice.current.userInterfaceIdiom == .pad
            ? .tablet : .phone
        let outcome = await reportProfile.update(
            name: value, namingMode: .custom, deviceClass: deviceClass)
        pairingMessage = profileMessage(outcome)
        await reload()
    }

    func useDeviceName() async {
        proposedDeviceName = UIDevice.current.name
        let deviceClass: ReaderDeviceClass =
            UIDevice.current.userInterfaceIdiom == .pad
            ? .tablet : .phone
        let outcome = await reportProfile.update(
            name: UIDevice.current.name, namingMode: .automatic, deviceClass: deviceClass)
        pairingMessage = profileMessage(outcome)
        await reload()
    }

    func retryDeviceProfile() async {
        pairingMessage = profileMessage(await reportProfile.retry())
        await reload()
    }

    private func refreshAutomaticProfileIfNeeded() async {
        guard let state = try? await reader.load(), let profile = state.readerProfile else {
            return
        }
        if profile.namingMode == .automatic, profile.name.value != UIDevice.current.name {
            let deviceClass: ReaderDeviceClass =
                UIDevice.current.userInterfaceIdiom == .pad
                ? .tablet : .phone
            _ = await reportProfile.update(
                name: UIDevice.current.name, namingMode: .automatic, deviceClass: deviceClass)
        } else {
            _ = await reportProfile.retry()
        }
    }

    private func profileMessage(_ outcome: ReaderProfileUpdateOutcome) -> String? {
        switch outcome {
        case .available: "Device name is available to the Mac."
        case .waiting: "Device name is saved and waiting to share."
        case .failed: "Device name is saved locally but couldn’t be shared."
        case .notPaired: nil
        case .invalidName: "Enter a visible device name up to 64 UTF-8 bytes."
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
