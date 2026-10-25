import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarProviderAdapters
import ResetRadarStorage
import ResetRadarTransport

private actor SyntheticCatalogStore: AccountCatalogStore {
    let catalog: AccountCatalog

    init(account: AccountMetadata) throws {
        catalog = try AccountCatalog(validating: [account])
    }

    func loadCatalog() -> AccountCatalog { catalog }
    func setAlias(accountID: AccountID, alias: AccountAlias?) throws -> AccountCatalog {
        guard accountID == catalog.accounts[0].id else {
            throw ProviderAccountCatalogStoreError.accountNotFound
        }
        return try AccountCatalog(validating: [catalog.accounts[0].replacingAlias(alias)])
    }
}

private actor SyntheticUsageSource: UsageSource {
    nonisolated let accountID: AccountID
    nonisolated let product = ProductID.codex
    nonisolated let updates: AsyncStream<SourceSnapshot>
    private let continuation: AsyncStream<SourceSnapshot>.Continuation
    private let clock: any AppClock
    private var stopped = false

    init(accountID: AccountID, clock: any AppClock) {
        self.accountID = accountID
        self.clock = clock
        let pair = AsyncStream<SourceSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        updates = pair.stream
        continuation = pair.continuation
    }

    func start() async throws { _ = await refresh() }

    func refresh() -> ReadReceipt {
        let now = clock.now
        guard !stopped else { return .unavailable(sourceState: .unavailable) }
        let report = SourceSnapshot(
            source: AccountSource(
                accountID: accountID, product: .codex, kind: .codexAppServer,
                version: "synthetic", state: .reporting),
            windows: [], isCompleteReport: true)
        continuation.yield(report)
        return ReadReceipt(startedAt: now, finishedAt: now, succeeded: true, report: report)
    }

    func stop() {
        stopped = true
        continuation.finish()
    }
}

private actor RuntimeEventRouter {
    var sources: SourceRuntime?
    var publication: PublicationDriver?
    var manual: ManualRequestDriver?
    var retry: SecretRetryDriver?

    func configure(
        sources: SourceRuntime, publication: PublicationDriver, manual: ManualRequestDriver,
        retry: SecretRetryDriver
    ) {
        self.sources = sources
        self.publication = publication
        self.manual = manual
        self.retry = retry
    }

    func workspace(_ event: WorkspaceEvent) async {
        switch event {
        case .woke:
            await manual?.wake()
            await sources?.refresh(.wake)
            await publication?.trigger(.wake)
        case .sessionActive:
            await retry?.loginSessionBecameActive()
        case .foreground:
            await sources?.refresh(.foreground)
        case .sleeping:
            await manual?.update(ready: true, hasReaders: true, sleeping: true)
        }
    }

    func networkRestored() async {
        await publication?.trigger(.networkRestored)
    }
}

// swiftlint:disable:next type_body_length
enum ProductionEnvironmentFactory {
    enum FactoryError: Error { case invalidSyntheticIdentifier }

    private struct Core {
        let development: Bool
        let locations: StorageLocations
        let clock: SystemAppClock
        let publisher: FilePublisherStore
        let snapshots: FileSnapshotStore
        let diagnostics: LogDiagnosticsSink
        let secrets: SessionSecretCache
        let random: CryptoSecretGenerator
        let relay: HTTPRelayGateway
        let publishing: PublishSnapshot
        let catalog: ProviderAccountCatalogStore
    }

    private struct Runtime {
        let sources: SourceRuntime
        let publication: PublicationDriver
        let manual: ManualRequestDriver
    }

    @MainActor
    static func make(mode: PublishingMode) async throws -> MacEnvironment {
        let core = try makeCore()
        let selected = try await makeSources(mode: mode, core: core)
        let runtime = try await makeRuntime(core: core, selected: selected)
        return try await makeEnvironment(mode: mode, core: core, runtime: runtime)
    }

    private static func makeCore() throws -> Core {
        let flavor: MacBuildFlavor = {
            #if DEBUG
                .development
            #else
                .release
            #endif
        }()
        let locations = flavor.storage
        try FileManager.default.createDirectory(
            at: locations.directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let clock = SystemAppClock()
        let publisher = FilePublisherStore(locations: locations)
        let snapshots = FileSnapshotStore(locations: locations)
        let diagnostics = LogDiagnosticsSink(locations: locations)
        let keychainBuild: KeychainSecretStore.Build = {
            if case .release = flavor { return .release }
            return .debug
        }()
        let baseSecrets = KeychainSecretStore(build: keychainBuild)
        let secrets = SessionSecretCache(store: baseSecrets)
        let random = CryptoSecretGenerator()
        let relay = HTTPRelayGateway()
        let publishing = PublishSnapshot(
            publisher: publisher, secrets: secrets, cipher: AESGCMEnvelopeCipher(), relay: relay,
            diagnostics: diagnostics, clock: clock, random: random)

        let development: Bool
        if case .development = flavor { development = true } else { development = false }
        return Core(
            development: development, locations: locations, clock: clock, publisher: publisher,
            snapshots: snapshots,
            diagnostics: diagnostics, secrets: secrets, random: random, relay: relay,
            publishing: publishing,
            catalog: ProviderAccountCatalogStore(directoryURL: locations.directory))
    }

    private static func makeRuntime(
        core: Core, selected: SelectedSources
    ) async throws -> Runtime {
        let state = try await core.publisher.load()
        let collectorPublisherID: PublisherID
        if let activePublisherID = state.publisherID {
            collectorPublisherID = activePublisherID
        } else {
            collectorPublisherID = try core.random.randomIdentifier(PublisherID.self)
        }
        let collector = CollectUsage(
            snapshots: core.snapshots, diagnostics: core.diagnostics, clock: core.clock,
            catalogStore: selected.catalog, publisherID: collectorPublisherID,
            heartbeatSeconds: Int(PublicationPolicy.heartbeat))
        let publication = PublicationDriver(
            clock: core.clock, loadSnapshot: { try await core.snapshots.load() },
            publish: { snapshot, change, trigger in
                await core.publishing.publish(snapshot, change: change, trigger: trigger)
            })
        let sourceRuntime = SourceRuntime(
            sources: selected.sources, ingest: { try await collector.ingest($0) },
            didCollect: { await publication.collected($0) })
        let handler = HandleManualRefreshRequests(
            publisher: core.publisher, snapshots: core.snapshots, collector: collector,
            sources: selected.sources, publishing: core.publishing, secrets: core.secrets,
            relay: core.relay, clock: core.clock)
        let manual = ManualRequestDriver(
            poll: { await pollRequests(core: core) },
            handle: { await handler.handle(pending: $0) })
        await manual.update(
            ready: state.lifecycle == .active, hasReaders: !state.devices.isEmpty, sleeping: false)
        return Runtime(sources: sourceRuntime, publication: publication, manual: manual)
    }

    @MainActor
    private static func makeEnvironment(
        mode: PublishingMode, core: Core, runtime: Runtime
    ) async throws -> MacEnvironment {
        let router = RuntimeEventRouter()
        let retry = SecretRetryDriver { await runtime.publication.trigger(.heartbeat) }
        let wake = WakeMonitor(events: SystemWorkspaceEvents()) {
            await router.workspace($0)
        }
        let network = NetworkMonitor(paths: SystemNetworkPathProvider()) {
            await router.networkRestored()
        }
        await router.configure(
            sources: runtime.sources, publication: runtime.publication, manual: runtime.manual,
            retry: retry)
        let lockURL = try core.locations.file("collector.lock")
        let activationName = Notification.Name("ResetRadar.activate-first-instance")
        let instanceLock = SingleInstanceLock(
            fileURL: lockURL,
            activator: DistributedFirstInstanceActivator(notificationName: activationName))
        let ownerFlows = makeOwnerFlows(core: core, runtime: runtime)
        return MacEnvironment(
            publishingMode: mode, instanceLock: instanceLock,
            appNap: AppNapGuard(controller: SystemProcessActivityController()),
            sources: runtime.sources, publication: runtime.publication,
            manualRequests: runtime.manual, wakeMonitor: wake, networkMonitor: network,
            secretRetry: retry, secrets: core.secrets, ownerFlows: ownerFlows,
            activationObserver: FirstInstanceActivationObserver(notificationName: activationName))
    }

    @MainActor
    // swiftlint:disable:next function_body_length
    private static func makeOwnerFlows(core: Core, runtime: Runtime) -> OwnerFlowModels {
        let runner = FoundationCodexCommandRunner(clock: core.clock)
        let selections = CodexDiscoverySelections(workingDirectory: core.locations.directory)
        let codex = CodexConfigurator(
            contexts: selections, locator: CodexExecutableLocator(runner: runner),
            metadataReader: CodexExecutableMetadataReader(runner: runner), store: core.catalog)
        let embedded = Bundle.main.bundleURL.appending(
            path: "Contents/Helpers/ResetRadarStatusLine")
        let installer = StatusLineHelperInstaller(
            embeddedHelper: embedded, rootDirectory: core.locations.directory)
        let home = URL.homeDirectory
        let claudePaths = ClaudeCodeConfiguratorPaths(
            homeDirectory: home, rootDirectory: core.locations.directory,
            settingsURL: home.appending(path: ".claude/settings.json"), managedSettingsURL: nil,
            environment: ProcessInfo.processInfo.environment)
        let claude = ClaudeCodeConfigurator(
            paths: claudePaths, installer: installer, catalog: core.catalog)
        let configure = ConfigureSources(configurators: [codex, claude])
        let setup = SetUpRelay(
            publisher: core.publisher, secrets: core.secrets, random: core.random,
            relay: core.relay, snapshots: core.snapshots, publishing: core.publishing,
            clock: core.clock, heartbeatSeconds: Int(PublicationPolicy.heartbeat))
        let pairing = PairReader(
            publisher: core.publisher, secrets: core.secrets, random: core.random,
            relay: core.relay, codec: JSONPairingCodec(), clock: core.clock)
        let identityState = SigningIdentityStateStore(development: core.development)
        let signatureCheck = SigningCheck(reader: SystemSignatureReader())
        let aliases = UpdateAccountAlias(
            catalogStore: core.catalog, snapshots: core.snapshots, clock: core.clock)
        let homeModel = HomeViewModel(
            catalog: core.catalog, snapshots: core.snapshots, aliases: aliases,
            publication: runtime.publication)
        return OwnerFlowModels(
            home: homeModel, general: LoginItemViewModel(manager: SystemLoginItemManager()),
            sources: SourceSetupViewModel(
                selections: selections, configure: configure, catalog: core.catalog,
                aliases: aliases, publication: runtime.publication),
            relay: RelaySetupViewModel(
                setup: setup, publication: runtime.publication,
                runningTeamIdentifier: {
                    guard
                        case .valid(let team) = signatureCheck.evaluate(
                            recordedTeamIdentifier: nil)
                    else { return nil }
                    return team
                }, recordTeamIdentifier: { identityState.record($0) }),
            pairing: PairingViewModel(pairing: pairing),
            devices: DevicesViewModel(
                reconcile: ReconcileReaders(
                    publisher: core.publisher, secrets: core.secrets, relay: core.relay,
                    clock: core.clock),
                revoke: RevokeReader(
                    publisher: core.publisher, secrets: core.secrets, relay: core.relay),
                destroy: DestroyRelay(
                    publisher: core.publisher, secrets: core.secrets, relay: core.relay,
                    publishing: core.publishing),
                publication: runtime.publication, secrets: core.secrets),
            recovery: RecoveryViewModel(
                signingCheck: signatureCheck,
                recordedTeamIdentifier: { identityState.teamIdentifier },
                secretCache: core.secrets),
            diagnostics: DiagnosticsViewModel(diagnostics: core.diagnostics))
    }

    private static func pollRequests(core: Core) async -> [PendingRefreshRequest] {
        guard let state = try? await core.publisher.load(), state.lifecycle == .active,
            !state.devices.isEmpty, let endpoint = state.endpoint,
            let token = try? await core.secrets.read(.writeToken),
            case .value(let requests) = await core.relay.listRefreshRequests(
                endpoint: endpoint, writeToken: token)
        else { return [] }
        return requests
    }

    private struct SelectedSources {
        let sources: [any UsageSource]
        let catalog: any AccountCatalogStore
    }

    private static func makeSources(
        mode: PublishingMode, core: Core
    ) async throws -> SelectedSources {
        if mode == .synthetic { return try makeSyntheticSources(clock: core.clock) }
        let accountCatalog = try await core.catalog.loadCatalog()
        let scoper = HMACAccountScoper(secrets: core.secrets, generator: core.random)
        let workingDirectory = core.locations.directory
        let host = ChildProcessHost(appWorkingDirectoryURL: workingDirectory)
        let runner = FoundationCodexCommandRunner(clock: core.clock)
        let metadataReader = CodexExecutableMetadataReader(runner: runner)
        var sources: [any UsageSource] = []
        for account in accountCatalog.accounts where account.product == .codex {
            let factory = StoredCodexProcessRPCSessionFactory(
                accountID: account.id, store: core.catalog, host: host,
                workingDirectoryURL: workingDirectory, clock: core.clock)
            let inspector = StoredCodexRuntimeInspector(
                accountID: account.id, store: core.catalog, metadataReader: metadataReader,
                workingDirectoryURL: workingDirectory)
            sources.append(
                CodexAppServerSource(
                    accountID: account.id, sourceVersion: "unknown", factory: factory,
                    scoper: scoper, diagnostics: core.diagnostics, clock: core.clock,
                    runtimeInspector: inspector))
        }
        if let account = accountCatalog.accounts.first(where: { $0.product == .claudeCode }) {
            let embedded = Bundle.main.bundleURL.appending(
                path: "Contents/Helpers/ResetRadarStatusLine")
            let installer = StatusLineHelperInstaller(
                embeddedHelper: embedded, rootDirectory: core.locations.directory)
            let home = URL.homeDirectory
            let paths = ClaudeCodeConfiguratorPaths(
                homeDirectory: home, rootDirectory: core.locations.directory,
                settingsURL: home.appending(path: ".claude/settings.json"),
                managedSettingsURL: nil, environment: ProcessInfo.processInfo.environment)
            let configurator = ClaudeCodeConfigurator(
                paths: paths, installer: installer, catalog: core.catalog)
            sources.append(
                ClaudeCodeSource(
                    accountID: account.id,
                    file: SessionRecordFile(rootDirectory: core.locations.directory),
                    probe: ConfiguratorInstallationProbe(
                        configurator: configurator, installer: installer),
                    diagnostics: core.diagnostics, clock: core.clock))
        }
        return SelectedSources(sources: sources, catalog: core.catalog)
    }

    private static func makeSyntheticSources(clock: any AppClock) throws -> SelectedSources {
        guard
            let id = AccountID(data: Data(repeating: 0x53, count: AccountID.byteCount))
        else { throw FactoryError.invalidSyntheticIdentifier }
        let metadata = AccountMetadata(id: id, product: .codex, number: 1)
        return SelectedSources(
            sources: [SyntheticUsageSource(accountID: id, clock: clock)],
            catalog: try SyntheticCatalogStore(account: metadata))
    }
}
