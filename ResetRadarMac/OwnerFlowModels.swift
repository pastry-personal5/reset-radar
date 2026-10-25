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

    init(
        catalog: any AccountCatalogStore, snapshots: any LocalSnapshotCommitting,
        aliases: UpdateAccountAlias, publication: PublicationDriver
    ) {
        self.catalog = catalog
        self.snapshots = snapshots
        self.aliases = aliases
        self.publication = publication
    }

    func load() async {
        do {
            accounts = try await catalog.loadCatalog().accounts
            snapshot = try await snapshots.load()
            message = nil
        } catch {
            message = "Local collector data could not be read. Quit and reopen Reset Radar."
        }
    }

    func updateAlias(accountID: AccountID, input: String) async {
        do {
            let update = try await aliases.update(accountID: accountID, input: input)
            await load()
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
