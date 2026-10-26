import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarProviderAdapters
import ResetRadarScheduling
import ResetRadarStorage

enum MacSetupStep: Equatable {
    case sources
    case relay
    case pairing
}

private func noAccountRefresh(_ accountID: AccountID?) async -> [AccountRefreshResult] { [] }

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var accounts = [AccountMetadata]()
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var message: String?
    @Published private(set) var relayLifecycle = RelayLifecycle.notConfigured
    @Published private(set) var pairedReaderCount = 0
    @Published private(set) var isRefreshing = false
    @Published private(set) var loadFailed = false
    @Published private(set) var notificationAuthorization = NotificationAuthorization.notDetermined

    private let catalog: any AccountCatalogStore
    private let snapshots: any LocalSnapshotCommitting
    private let aliases: UpdateAccountAlias
    private let publication: PublicationDriver
    private let updates: HomeSnapshotUpdates?
    private let publisher: (any PublisherStore)?
    private let refreshSources: @Sendable (AccountID?) async -> [AccountRefreshResult]
    private let preferences: any PreferenceStore
    private let scheduler: any NotificationScheduler
    private let reminders: ReconcileResetNotifications
    private let setNotificationOptIn: SetNotificationOptIn

    init(
        catalog: any AccountCatalogStore, snapshots: any LocalSnapshotCommitting,
        aliases: UpdateAccountAlias, publication: PublicationDriver,
        updates: HomeSnapshotUpdates? = nil, publisher: (any PublisherStore)? = nil,
        preferences: any PreferenceStore = DefaultsPreferenceStore(defaults: .standard),
        scheduler: any NotificationScheduler = SystemNotificationScheduler(),
        reminders: ReconcileResetNotifications? = nil,
        refreshSources: @escaping @Sendable (AccountID?) async -> [AccountRefreshResult] =
            noAccountRefresh
    ) {
        self.catalog = catalog
        self.snapshots = snapshots
        self.aliases = aliases
        self.publication = publication
        self.updates = updates
        self.publisher = publisher
        self.preferences = preferences
        self.scheduler = scheduler
        let reconciliation =
            reminders
            ?? ReconcileResetNotifications(
                visible: VisibleSnapshot(snapshots: snapshots), preferences: preferences,
                scheduler: scheduler, gate: nil, clock: SystemAppClock())
        self.reminders = reconciliation
        setNotificationOptIn = SetNotificationOptIn(
            preferences: preferences, scheduler: scheduler, reconcile: reconciliation)
        self.refreshSources = refreshSources
    }

    var setupStep: MacSetupStep? {
        if accounts.isEmpty { return .sources }
        if relayLifecycle != .active { return .relay }
        if pairedReaderCount == 0 { return .pairing }
        return nil
    }

    func load() async {
        do {
            let configured = try await catalog.loadCatalog().accounts
            let current = try await snapshots.load()
            accounts = AccountDisplayOrder.sorted(configured)
            snapshot = current
            if let publisher {
                let state = try await publisher.load()
                relayLifecycle = state.lifecycle
                pairedReaderCount = state.devices.count
            }
            notificationAuthorization = await scheduler.authorization()
            loadFailed = false
            message = nil
        } catch {
            loadFailed = true
            message = "Local collector data could not be read. Quit and reopen Reset Radar."
        }
    }

    func didCollect(_ current: UsageSnapshot) {
        accounts = AccountDisplayOrder.sorted(current.accounts)
        snapshot = current
    }

    func refreshAll() async {
        await refresh(accountID: nil)
    }

    func refreshAccount(_ accountID: AccountID) async {
        await refresh(accountID: accountID)
    }

    private func refresh(accountID: AccountID?) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        message = nil
        let results = await refreshSources(accountID)
        guard !results.isEmpty else {
            message =
                accountID == nil
                ? "No configured sources are available to refresh."
                : "This account is not available for refresh."
            return
        }
        let accountOrder = Dictionary(
            uniqueKeysWithValues: accounts.enumerated().map { ($0.element.id, $0.offset) })
        let orderedResults = results.sorted {
            let left = accountOrder[$0.accountID] ?? Int.max
            let right = accountOrder[$1.accountID] ?? Int.max
            return left == right ? $0.accountID.hex < $1.accountID.hex : left < right
        }
        message = orderedResults.map { result in
            let label =
                accounts.first(where: { $0.id == result.accountID })?
                .effectiveDisplayLabel ?? "Account"
            switch result.receipt {
            case .performed(_, _, true, _):
                return "Refreshed \(label)."
            case .performed(_, _, false, _):
                return "Could not refresh \(label). Its last reading remains visible."
            case .deferred(let retryAt, _):
                return "\(label) refresh is backing off until "
                    + retryAt.formatted(date: .omitted, time: .shortened) + "."
            case .unavailable:
                return "\(label) source is unavailable. Its last reading remains visible."
            }
        }.joined(separator: "\n")
    }

    func updateAlias(accountID: AccountID, input: String) async {
        do {
            let update = try await aliases.update(accountID: accountID, input: input)
            if let updates { await updates.aliasDidChange() } else { await load() }
            if let snapshot = update.snapshot {
                _ = await reminders.run(onIOS: false)
                await publication.collected(
                    CollectResult(snapshot: snapshot, change: update.change))
            }
            message = nil
        } catch {
            message = "The alias must be unique, visible text no longer than 32 bytes."
        }
    }

    func notificationOptIn(_ selection: WindowSelection) async -> Bool? {
        await preferences.notificationOptIn(selection)
    }

    func setNotificationOptIn(_ selection: WindowSelection, enabled: Bool) async -> OptInOutcome {
        let outcome = await setNotificationOptIn.set(selection, enabled: enabled)
        notificationAuthorization = await scheduler.authorization()
        return outcome
    }

    func reconcileNotifications() async {
        _ = await reminders.run(onIOS: false)
        notificationAuthorization = await scheduler.authorization()
    }
}

/// Bridges a committed collector report into the process-owned Home model. SourceRuntime is
/// created before OwnerFlowModels, so the binding is installed when composition finishes.
@MainActor
final class HomeSnapshotUpdates {
    private weak var home: HomeViewModel?
    private weak var sources: SourceSetupViewModel?

    func connect(home: HomeViewModel, sources: SourceSetupViewModel) {
        self.home = home
        self.sources = sources
    }

    func didCollect(_ snapshot: UsageSnapshot) { home?.didCollect(snapshot) }

    func aliasDidChange() async {
        await home?.load()
        await sources?.loadConfiguredAccounts()
    }
}

@MainActor
final class DiagnosticsViewModel: ObservableObject {
    @Published private(set) var events = [DiagnosticEvent]()
    private let diagnostics: LogDiagnosticsSink

    init(diagnostics: LogDiagnosticsSink) {
        self.diagnostics = diagnostics
    }

    func refresh() async { events = await diagnostics.history() }
}

@MainActor
final class OwnerFlowModels: ObservableObject {
    let home: HomeViewModel
    let general: LoginItemViewModel
    let sources: SourceSetupViewModel
    let relay: RelaySetupViewModel
    let pairing: PairingViewModel
    let devices: DevicesViewModel
    let recovery: RecoveryViewModel
    let diagnostics: DiagnosticsViewModel

    init(
        home: HomeViewModel, general: LoginItemViewModel, sources: SourceSetupViewModel,
        relay: RelaySetupViewModel, pairing: PairingViewModel, devices: DevicesViewModel,
        recovery: RecoveryViewModel, diagnostics: DiagnosticsViewModel
    ) {
        self.home = home
        self.general = general
        self.sources = sources
        self.relay = relay
        self.pairing = pairing
        self.devices = devices
        self.recovery = recovery
        self.diagnostics = diagnostics
    }
}
