import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarProviderAdapters
import ResetRadarScheduling
import ResetRadarStorage
import ResetRadarTransport

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
        let manualReady: Bool
        let hasReaders: Bool
    }

    @MainActor
    private struct UIContext {
        let messages: GlobalMessageCenter
        let homeUpdates: HomeSnapshotUpdates
    }

    @MainActor
    static func make(
        mode: PublishingMode, messages: GlobalMessageCenter, log: MacRotatingLog
    ) async throws -> MacEnvironment {
        let core = try makeCore(log: log)
        let selected = try await makeSources(mode: mode, core: core)
        let homeUpdates = HomeSnapshotUpdates()
        let runtime = try await makeRuntime(
            core: core, selected: selected, messages: messages, homeUpdates: homeUpdates)
        return try await makeEnvironment(
            mode: mode, core: core, runtime: runtime, log: log,
            uiContext: UIContext(messages: messages, homeUpdates: homeUpdates))
    }

    private static func makeCore(log: MacRotatingLog) throws -> Core {
        let flavor = MacBuildFlavor.current
        let locations = flavor.storage
        try FileManager.default.createDirectory(
            at: locations.directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let clock = SystemAppClock()
        let publisher = FilePublisherStore(locations: locations)
        let snapshots = FileSnapshotStore(locations: locations)
        let diagnostics = LogDiagnosticsSink(
            locations: locations, subsystem: flavor.logSubsystem,
            onRecord: { event in await log.record(.diagnostic(event)) })
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
        core: Core, selected: SelectedSources, messages: GlobalMessageCenter,
        homeUpdates: HomeSnapshotUpdates
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
            },
            reportOutcome: { outcome in
                await messages.reportPublication(outcome)
            })
        let sourceRuntime = SourceRuntime(
            sources: selected.sources, ingest: { try await collector.ingest($0) },
            notificationHook: MacResetNotificationHook(
                reminders: ReconcileResetNotifications(
                    visible: VisibleSnapshot(snapshots: core.snapshots),
                    preferences: DefaultsPreferenceStore(defaults: .standard),
                    scheduler: SystemNotificationScheduler(), gate: nil, clock: core.clock)),
            didCollect: { result in
                await homeUpdates.didCollect(result.snapshot)
                await publication.collected(result)
            })
        let handler = HandleManualRefreshRequests(
            publisher: core.publisher, snapshots: core.snapshots, collector: collector,
            sources: selected.sources, publishing: core.publishing, secrets: core.secrets,
            relay: core.relay, clock: core.clock)
        let manual = ManualRequestDriver(
            poll: { await pollRequests(core: core) },
            handle: { pending in
                let outcome = await handler.handle(pending: pending)
                await publication.reportManualOutcome(outcome)
                return outcome
            })
        return Runtime(
            sources: sourceRuntime, publication: publication, manual: manual,
            manualReady: state.lifecycle == .active, hasReaders: !state.devices.isEmpty)
    }

    @MainActor
    private static func makeEnvironment(
        mode: PublishingMode, core: Core, runtime: Runtime, log: MacRotatingLog,
        uiContext: UIContext
    ) async throws -> MacEnvironment {
        let router = RuntimeEventRouter(log: log)
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
        let ownerFlows = makeOwnerFlows(
            core: core, runtime: runtime, homeUpdates: uiContext.homeUpdates)
        let recordedTeam = SigningIdentityStateStore(
            development: core.development
        ).teamIdentifier
        let signing = SigningCheck(reader: SystemSignatureReader()).evaluate(
            recordedTeamIdentifier: recordedTeam)
        let signingReady: Bool
        if core.development {
            signingReady = true
        } else if case .valid = signing {
            signingReady = true
        } else {
            signingReady = false
        }
        return MacEnvironment(
            publishingMode: mode, instanceLock: instanceLock,
            appNap: AppNapGuard(controller: SystemProcessActivityController()),
            sources: runtime.sources, publication: runtime.publication,
            manualRequests: runtime.manual, manualReady: runtime.manualReady,
            hasReaders: runtime.hasReaders, wakeMonitor: wake, networkMonitor: network,
            secretRetry: retry, secrets: core.secrets, ownerFlows: ownerFlows,
            signingReady: signingReady,
            activationObserver: FirstInstanceActivationObserver(notificationName: activationName),
            prepareSources: {
                if mode != .synthetic {
                    ClaudeCodeHelperPreparation.onLaunch(
                        rootDirectory: core.locations.directory, messages: uiContext.messages)
                }
            })
    }

    @MainActor
    // swiftlint:disable:next function_body_length
    private static func makeOwnerFlows(
        core: Core, runtime: Runtime, homeUpdates: HomeSnapshotUpdates
    ) -> OwnerFlowModels {
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
        let notificationPreferences = DefaultsPreferenceStore(defaults: .standard)
        let notificationScheduler = SystemNotificationScheduler()
        let notificationReminders = ReconcileResetNotifications(
            visible: VisibleSnapshot(snapshots: core.snapshots),
            preferences: notificationPreferences,
            scheduler: notificationScheduler, gate: nil, clock: core.clock)
        let homeModel = HomeViewModel(
            catalog: core.catalog, snapshots: core.snapshots, aliases: aliases,
            publication: runtime.publication, updates: homeUpdates,
            publisher: core.publisher, preferences: notificationPreferences,
            scheduler: notificationScheduler, reminders: notificationReminders,
            refreshSources: { await runtime.sources.refreshAccounts(accountID: $0) })
        let sourceModel = SourceSetupViewModel(
            selections: selections, configure: configure, catalog: core.catalog,
            aliases: aliases, publication: runtime.publication,
            codexConfigurations: core.catalog, updates: homeUpdates)
        homeUpdates.connect(home: homeModel, sources: sourceModel)
        let refreshManualRequests: @MainActor () async -> Void = {
            let state = try? await core.publisher.load()
            await runtime.manual.updateReadiness(
                ready: state?.lifecycle == .active,
                hasReaders: !(state?.devices.isEmpty ?? true))
            await homeModel.load()
        }
        let pauseManualRequests: @MainActor () async -> Void = {
            await runtime.manual.setSuspended(true)
        }
        let resumeManualRequests: @MainActor () async -> Void = {
            await runtime.manual.setSuspended(false)
        }
        return OwnerFlowModels(
            home: homeModel, general: LoginItemViewModel(manager: SystemLoginItemManager()),
            sources: sourceModel,
            relay: RelaySetupViewModel(
                setup: setup, publication: runtime.publication,
                refreshManualRequests: refreshManualRequests,
                pauseManualRequests: pauseManualRequests,
                resumeManualRequests: resumeManualRequests,
                runningTeamIdentifier: {
                    guard
                        case .valid(let team) = signatureCheck.evaluate(
                            recordedTeamIdentifier: nil)
                    else { return nil }
                    return team
                }, recordTeamIdentifier: { identityState.record($0) },
                publisher: core.publisher),
            pairing: PairingViewModel(
                pairing: pairing, refreshManualRequests: refreshManualRequests),
            devices: DevicesViewModel(
                reconcile: ReconcileReaders(
                    publisher: core.publisher, secrets: core.secrets, relay: core.relay,
                    clock: core.clock, profileCipher: AESGCMReaderProfileCipher()),
                revoke: RevokeReader(
                    publisher: core.publisher, secrets: core.secrets, relay: core.relay),
                destroy: DestroyRelay(
                    publisher: core.publisher, secrets: core.secrets, relay: core.relay,
                    publishing: core.publishing),
                publication: runtime.publication, secrets: core.secrets,
                refreshManualRequests: refreshManualRequests,
                pauseManualRequests: pauseManualRequests),
            recovery: RecoveryViewModel(
                signingCheck: signatureCheck,
                recordedTeamIdentifier: { identityState.teamIdentifier },
                secretCache: core.secrets, development: core.development),
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
