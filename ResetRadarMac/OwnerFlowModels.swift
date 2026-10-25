import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarProviderAdapters
import ResetRadarStorage

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var accounts = [AccountMetadata]()
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var message: String?

    private let catalog: any AccountCatalogStore
    private let snapshots: any LocalSnapshotCommitting
    private let aliases: UpdateAccountAlias
    private let publication: PublicationDriver
    private let updates: HomeSnapshotUpdates?

    init(
        catalog: any AccountCatalogStore, snapshots: any LocalSnapshotCommitting,
        aliases: UpdateAccountAlias, publication: PublicationDriver,
        updates: HomeSnapshotUpdates? = nil
    ) {
        self.catalog = catalog
        self.snapshots = snapshots
        self.aliases = aliases
        self.publication = publication
        self.updates = updates
    }

    func load() async {
        do {
            let configured = try await catalog.loadCatalog().accounts
            let current = try await snapshots.load()
            accounts = AccountDisplayOrder.sorted(configured)
            snapshot = current
            message = nil
        } catch {
            message = "Local collector data could not be read. Quit and reopen Reset Radar."
        }
    }

    func didCollect(_ current: UsageSnapshot) {
        accounts = AccountDisplayOrder.sorted(current.accounts)
        snapshot = current
    }

    func updateAlias(accountID: AccountID, input: String) async {
        do {
            let update = try await aliases.update(accountID: accountID, input: input)
            if let updates { await updates.aliasDidChange() } else { await load() }
            if let snapshot = update.snapshot {
                await publication.collected(
                    CollectResult(snapshot: snapshot, change: update.change))
            }
            message = nil
        } catch {
            message = "The alias must be unique, visible text no longer than 32 bytes."
        }
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
