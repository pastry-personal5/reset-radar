import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarProviderAdapters
import ResetRadarTestSupport
import ResetRadarTransport
import Testing

@testable import ResetRadarMac

@MainActor
private final class FakeLoginItemManager: LoginItemManaging {
    enum Failure: Error { case injected }
    var state = LoginItemState.disabled
    var shouldFail = false

    func setEnabled(_ enabled: Bool) throws {
        if shouldFail { throw Failure.injected }
        state = enabled ? .enabled : .disabled
    }
}

private struct OwnerFlowSignatureReader: SignatureReading {
    let signature: RunningSignature
    func runningSignature() -> RunningSignature { signature }
}

@MainActor
private final class FakePairingPasteboard: PairingPasteboard {
    var changeCount = 0
    var value: String?
    var clearCount = 0

    func readString() -> String? { value }
    func writeString(_ value: String) -> Int {
        changeCount += 1
        self.value = value
        return changeCount
    }
    func clear() {
        changeCount += 1
        clearCount += 1
        value = nil
    }
    func replaceExternally(with value: String) {
        changeCount += 1
        self.value = value
    }
}

private struct FailingClaudePreviewConfigurator: SourceConfigurator {
    enum Failure: CaseIterable, Sendable { case existingCommand, helper }

    let product = ProductID.claudeCode
    let option = ConfigurationOption(
        id: ConfigurationOptionID(), product: .claudeCode,
        launch: ConfigurationLaunchPreview(executablePath: "/synthetic/helper", environment: []))
    let failure: Failure

    func inspect(accountID: AccountID?) async -> ConfigurationState { .notConfigured }
    func discover() async throws -> [ConfigurationOption] { [option] }
    func preview(
        optionID: ConfigurationOptionID, intent: ConfigurationIntent
    ) async throws -> ConfigurationPreview {
        switch failure {
        case .existingCommand: throw ConfigureSourcesError.unsafeExistingConfiguration
        case .helper: throw ClaudeCodeConfiguratorError.helperNotCurrent
        }
    }
    func apply(_ preview: ConfigurationPreview) async throws {}
    func remove(accountID: AccountID) async throws {}
    func restore() async throws {}
}

@Suite("Owner-flow view models")
struct OwnerFlowViewModelTests {
    @MainActor
    @Test func committedSourceReportRefreshesHomeWithoutReopeningTheWindow() async throws {
        let clock = FakeAppClock()
        let initial = try runtimeSnapshot(at: clock.now)
        let catalog = FakeAccountCatalogStore(accounts: initial.accounts)
        let snapshots = FakeSnapshotStore(snapshot: initial)
        let publication = PublicationDriver(
            clock: clock, loadSnapshot: { try await snapshots.load() },
            publish: { _, _, _ in .published(sequence: 1) })
        let home = HomeViewModel(
            catalog: catalog, snapshots: snapshots,
            aliases: UpdateAccountAlias(
                catalogStore: catalog, snapshots: snapshots, clock: clock),
            publication: publication)
        let updates = HomeSnapshotUpdates()
        let sources = SourceSetupViewModel(
            selections: CodexDiscoverySelections(
                workingDirectory: FileManager.default.temporaryDirectory),
            configure: ConfigureSources(configurators: []), catalog: catalog)
        updates.connect(home: home, sources: sources)
        await home.load()

        let committed = try runtimeSnapshot(at: clock.now.addingTimeInterval(60))
        updates.didCollect(committed)

        #expect(home.snapshot?.generatedAt == committed.generatedAt)
        #expect(home.accounts == AccountDisplayOrder.sorted(committed.accounts))
    }

    @MainActor
    @Test func sourceRequiresPreviewAndConfirmation() async throws {
        let source = FakeSourceConfigurator(product: .claudeCode)
        let configure = ConfigureSources(configurators: [source])
        let selections = CodexDiscoverySelections(
            workingDirectory: FileManager.default.temporaryDirectory)
        let model = SourceSetupViewModel(selections: selections, configure: configure)
        await model.discoverClaudeCode()
        let option = try #require(model.options.first)
        await model.prepare(option)
        #expect(model.preview != nil)
        #expect(source.applied.isEmpty)
        #expect(await model.confirmPreview())
        #expect(source.applied.count == 1)
        #expect(model.preview == nil)
    }

    @MainActor
    @Test func claudePreviewExplainsTheSpecificBlocker() async throws {
        for failure in FailingClaudePreviewConfigurator.Failure.allCases {
            let source = FailingClaudePreviewConfigurator(failure: failure)
            let model = SourceSetupViewModel(
                selections: CodexDiscoverySelections(
                    workingDirectory: FileManager.default.temporaryDirectory),
                configure: ConfigureSources(configurators: [source]))
            await model.discoverClaudeCode()
            await model.prepare(try #require(model.options.first))
            #expect(model.preview == nil)
            switch failure {
            case .existingCommand:
                #expect(model.message?.contains("trusted executable path or a simple") == true)
            case .helper:
                #expect(model.message?.contains("helper could not be installed") == true)
            }
        }
    }

    @MainActor
    @Test func sourceSetupListsConfiguredAccountsForConfirmedRemoval() async throws {
        let id = try #require(AccountID(data: Data(repeating: 9, count: AccountID.byteCount)))
        let catalog = FakeAccountCatalogStore(
            accounts: [AccountMetadata(id: id, product: .codex, number: 1)])
        let model = SourceSetupViewModel(
            selections: CodexDiscoverySelections(
                workingDirectory: FileManager.default.temporaryDirectory),
            configure: ConfigureSources(configurators: [FakeSourceConfigurator(product: .codex)]),
            catalog: catalog)

        await model.loadConfiguredAccounts()

        #expect(
            model.configuredAccounts == [
                AccountMetadata(id: id, product: .codex, number: 1)
            ])
    }

    @MainActor
    @Test func aliasEditsRefreshBothOpenMacViews() async throws {
        let clock = FakeAppClock()
        let snapshot = try runtimeSnapshot(at: clock.now)
        let catalog = FakeAccountCatalogStore(accounts: snapshot.accounts)
        let snapshots = FakeSnapshotStore(snapshot: snapshot)
        let publication = PublicationDriver(
            clock: clock, loadSnapshot: { try await snapshots.load() },
            publish: { _, _, _ in .published(sequence: 1) })
        let aliases = UpdateAccountAlias(
            catalogStore: catalog, snapshots: snapshots, clock: clock)
        let updates = HomeSnapshotUpdates()
        let home = HomeViewModel(
            catalog: catalog, snapshots: snapshots, aliases: aliases,
            publication: publication, updates: updates)
        let model = SourceSetupViewModel(
            selections: CodexDiscoverySelections(
                workingDirectory: FileManager.default.temporaryDirectory),
            configure: ConfigureSources(configurators: [FakeSourceConfigurator(product: .codex)]),
            catalog: catalog,
            aliases: aliases, publication: publication, updates: updates)
        updates.connect(home: home, sources: model)
        await home.load()

        await model.updateAlias(accountID: snapshot.accounts[0].id, input: "Work Mac")

        #expect(model.configuredAccounts[0].alias?.value == "Work Mac")
        #expect(home.accounts[0].alias?.value == "Work Mac")
        #expect(home.snapshot?.accounts[0].alias?.value == "Work Mac")
        #expect(model.message == nil)

        await home.updateAlias(accountID: snapshot.accounts[0].id, input: "Personal Mac")

        #expect(home.accounts[0].alias?.value == "Personal Mac")
        #expect(model.configuredAccounts[0].alias?.value == "Personal Mac")
    }

    @MainActor
    @Test func loginItemReportsActualFailureState() {
        let manager = FakeLoginItemManager()
        manager.shouldFail = true
        let model = LoginItemViewModel(manager: manager)
        model.setEnabled(true)
        #expect(model.state == .disabled)
        #expect(model.errorMessage != nil)
    }

    @MainActor
    @Test func relayRejectsNonCanonicalOriginBeforePrepare() async throws {
        let rig = try await RelayViewModelRig()
        rig.model.origin = "http://local.invalid"
        await rig.model.prepare()
        #expect(rig.model.writeDigest == nil)
        #expect(rig.model.message?.contains("canonical HTTPS") == true)
    }

    @MainActor
    @Test func relayPrepareAndActivateRecoverably() async throws {
        let rig = try await RelayViewModelRig()
        rig.model.origin = "https://synthetic.reset-radar.workers.dev"
        await rig.model.prepare()
        #expect(rig.model.writeDigest?.count == 64)
        #expect(rig.model.adminDigest?.count == 64)
        #expect(rig.model.isPending)
        await rig.model.activate()
        #expect(!rig.model.isPending)
        #expect(rig.publisher.state.lifecycle == .active)
    }

    @MainActor
    @Test func pairingDoesNotClearAChangedClipboard() async throws {
        let clock = FakeAppClock()
        let relay = FakeRelayGateway()
        relay.queueRegister(.value(clock.now.addingTimeInterval(300)))
        let publisher = FakePublisherStore()
        publisher.seed {
            $0.lifecycle = .active
            $0.endpoint = URL(string: "https://synthetic.reset-radar.workers.dev")
            $0.publisherID = PublisherID(
                data: Data(repeating: 3, count: PublisherID.byteCount))
        }
        let secrets = FakeSecretStore()
        secrets.seed(.contentKey, SecretValue(Data(repeating: 4, count: 32)))
        secrets.seed(.adminToken, SecretValue(Data(repeating: 5, count: 32)))
        let pairing = PairReader(
            publisher: publisher, secrets: secrets, random: FakeSecretGenerator(), relay: relay,
            codec: FakePairingCodec(), clock: clock)
        let pasteboard = FakePairingPasteboard()
        let model = PairingViewModel(pairing: pairing, pasteboard: pasteboard)
        await model.begin()
        #expect(model.encodedPackage != nil)
        model.copyWithWarningConfirmed()
        pasteboard.replaceExternally(with: "owner clipboard")
        await model.dismiss()
        #expect(pasteboard.value == "owner clipboard")
        #expect(pasteboard.clearCount == 0)
    }

    @MainActor
    @Test func pairingScreenHidesWithoutLeavingCopiedCredentials() async throws {
        let clock = FakeAppClock()
        let relay = FakeRelayGateway()
        relay.queueRegister(.value(clock.now.addingTimeInterval(300)))
        let publisher = FakePublisherStore()
        publisher.seed {
            $0.lifecycle = .active
            $0.endpoint = URL(string: "https://synthetic.reset-radar.workers.dev")
            $0.publisherID = PublisherID(
                data: Data(repeating: 3, count: PublisherID.byteCount))
        }
        let secrets = FakeSecretStore()
        secrets.seed(.contentKey, SecretValue(Data(repeating: 4, count: 32)))
        secrets.seed(.adminToken, SecretValue(Data(repeating: 5, count: 32)))
        let pairing = PairReader(
            publisher: publisher, secrets: secrets, random: FakeSecretGenerator(), relay: relay,
            codec: FakePairingCodec(), clock: clock)
        let pasteboard = FakePairingPasteboard()
        let model = PairingViewModel(pairing: pairing, pasteboard: pasteboard)

        await model.begin()
        model.copyWithWarningConfirmed()
        model.pairingViewDisappeared()

        #expect(pasteboard.value == nil)
        #expect(pasteboard.clearCount == 1)
        #expect(model.encodedPackage != nil)
    }

    @MainActor
    @Test func recoveryDistinguishesChangedTeamAndLockedSecrets() async {
        let cache = SessionSecretCache(store: FakeSecretStore())
        let changed = RecoveryViewModel(
            signingCheck: SigningCheck(
                reader: OwnerFlowSignatureReader(
                    signature: RunningSignature(teamIdentifier: "B", isAdHoc: false))),
            recordedTeamIdentifier: { "A" }, secretCache: cache)
        #expect(changed.recoveryCopy.contains("signing identity changed"))
        let lockedStore = FakeSecretStore()
        lockedStore.setReadFailure(.interactionRequired)
        let lockedCache = SessionSecretCache(store: lockedStore)
        _ = try? await lockedCache.read(.contentKey)
        let locked = RecoveryViewModel(
            signingCheck: SigningCheck(
                reader: OwnerFlowSignatureReader(
                    signature: RunningSignature(teamIdentifier: "A", isAdHoc: false))),
            recordedTeamIdentifier: { "A" }, secretCache: lockedCache)
        await locked.refresh()
        #expect(locked.recoveryCopy.contains("login keychain is locked"))
    }
}

@MainActor
private struct RelayViewModelRig {
    let model: RelaySetupViewModel
    let publisher: FakePublisherStore

    init() async throws {
        let clock = FakeAppClock()
        let snapshot = try runtimeSnapshot(at: clock.now)
        let snapshots = FakeSnapshotStore(snapshot: snapshot)
        publisher = FakePublisherStore()
        let secrets = FakeSecretStore()
        let relay = FakeRelayGateway()
        let publishing = PublishSnapshot(
            publisher: publisher, secrets: secrets, cipher: FakeEnvelopeCipher(), relay: relay,
            diagnostics: FakeDiagnosticsSink(), clock: clock, random: FakeSecretGenerator())
        let setup = SetUpRelay(
            publisher: publisher, secrets: secrets, random: FakeSecretGenerator(), relay: relay,
            snapshots: snapshots, publishing: publishing, clock: clock, heartbeatSeconds: 300)
        let driver = PublicationDriver(
            clock: clock, loadSnapshot: { try await snapshots.load() },
            publish: { snapshot, change, trigger in
                await publishing.publish(snapshot, change: change, trigger: trigger)
            })
        model = RelaySetupViewModel(setup: setup, publication: driver)
    }
}
