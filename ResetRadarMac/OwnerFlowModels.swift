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
    enum AliasDeliveryState: String, Equatable, Sendable {
        case publishing = "Saved locally — publishing"
        case available = "Saved and available to devices"
        case failed = "Saved locally — couldn’t publish"
        case localOnly = "Saved locally"
    }

    struct AliasDeliveryTransition: Sendable {
        let accountID: AccountID
        let label: String
        let state: AliasDeliveryState
    }
    @Published private(set) var accounts = [AccountMetadata]()
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var message: String?
    @Published private(set) var relayLifecycle = RelayLifecycle.notConfigured
    @Published private(set) var pairedReaderCount = 0
    @Published private(set) var isRefreshing = false
    @Published private(set) var loadFailed = false
    @Published private(set) var notificationAuthorization = NotificationAuthorization.notDetermined
    @Published private(set) var aliasDeliveries = [AccountID: AliasDeliveryState]()
    @Published private(set) var aliasDeliveryTransition: AliasDeliveryTransition?

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
            await publishAlias(update, accountID: accountID)
            message = nil
        } catch UpdateAccountAliasError.snapshotCommitFailed {
            setAliasDelivery(.failed, for: accountID)
            message =
                "The alias was saved locally, but the local snapshot could not be updated. "
                + "Retry the edit."
        } catch UpdateAccountAliasError.localSaveFailed {
            clearAliasDelivery(for: accountID, includingFailure: true)
            message = "The alias could not be saved locally. Retry when local storage is available."
        } catch UpdateAccountAliasError.accountNotFound {
            clearAliasDelivery(for: accountID, includingFailure: true)
            message = "This account is no longer configured."
        } catch {
            clearAliasDelivery(for: accountID, includingFailure: true)
            message = "The alias must be unique, visible text no longer than 32 bytes."
        }
    }

    private func publishAlias(_ update: AccountAliasUpdate, accountID: AccountID) async {
        guard let snapshot = update.snapshot else {
            setAliasDelivery(.localOnly, for: accountID)
            return
        }
        _ = await reminders.run(onIOS: false)
        guard let publisher else {
            setAliasDelivery(.localOnly, for: accountID)
            return
        }
        guard let state = try? await publisher.load() else {
            setAliasDelivery(.failed, for: accountID)
            return
        }
        guard state.lifecycle == .active else {
            setAliasDelivery(.localOnly, for: accountID)
            return
        }
        setAliasDelivery(.publishing, for: accountID)
        await publication.observeMetadataDelivery(account: update.account) { [weak self] outcome in
            await MainActor.run {
                self?.setAliasDelivery(Self.aliasState(for: outcome), for: accountID)
            }
        }
        let outcome = await publication.collected(
            CollectResult(snapshot: snapshot, change: update.change))
        let deliveryState = Self.aliasState(for: outcome)
        if aliasDelivery(for: accountID) != .available || deliveryState == .available {
            setAliasDelivery(deliveryState, for: accountID)
        }
    }

    func aliasDelivery(for accountID: AccountID) -> AliasDeliveryState? {
        aliasDeliveries[accountID]
    }

    func clearAliasDelivery(for accountID: AccountID, includingFailure: Bool = false) {
        guard let state = aliasDeliveries[accountID],
            includingFailure || state == .available || state == .localOnly
        else { return }
        aliasDeliveries.removeValue(forKey: accountID)
    }

    private func setAliasDelivery(_ state: AliasDeliveryState, for accountID: AccountID) {
        guard aliasDeliveries[accountID] != state else { return }
        aliasDeliveries[accountID] = state
        let label =
            accounts.first(where: { $0.id == accountID })?.effectiveDisplayLabel ?? "Account"
        aliasDeliveryTransition = AliasDeliveryTransition(
            accountID: accountID, label: label, state: state)
    }

    private static func aliasState(for outcome: PublishOutcome) -> AliasDeliveryState {
        switch outcome {
        case .published: .available
        case .notDue, .backoff: .publishing
        case .paused, .secretsUnavailable, .envelopeTooLarge, .stopped: .failed
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
