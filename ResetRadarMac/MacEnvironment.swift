import AppKit
import Combine
import Foundation

@MainActor
final class MacEnvironment: ObservableObject {
    enum State: Equatable {
        case stopped
        case running
        case secondInstance
    }

    let publishingMode: PublishingMode
    let ownerFlows: OwnerFlowModels
    var collectionAllowed: Bool { signingReady }
    @Published private(set) var state = State.stopped

    private let instanceLock: SingleInstanceLock
    private let appNap: AppNapGuard
    private let sources: SourceRuntime
    private let publication: PublicationDriver
    private let manualRequests: ManualRequestDriver
    private let manualReady: Bool
    private let hasReaders: Bool
    private let wakeMonitor: WakeMonitor
    private let networkMonitor: NetworkMonitor
    private let secretRetry: SecretRetryDriver
    private let secrets: SessionSecretCache
    private let activationObserver: FirstInstanceActivationObserver
    private let prepareSources: @MainActor () -> Void
    private let signingReady: Bool
    private var systemChangeObservers: [Task<Void, Never>] = []

    deinit {
        for observer in systemChangeObservers { observer.cancel() }
    }

    init(
        publishingMode: PublishingMode, instanceLock: SingleInstanceLock,
        appNap: AppNapGuard, sources: SourceRuntime, publication: PublicationDriver,
        manualRequests: ManualRequestDriver, manualReady: Bool, hasReaders: Bool,
        wakeMonitor: WakeMonitor,
        networkMonitor: NetworkMonitor, secretRetry: SecretRetryDriver,
        secrets: SessionSecretCache, ownerFlows: OwnerFlowModels,
        signingReady: Bool,
        activationObserver: FirstInstanceActivationObserver,
        prepareSources: @escaping @MainActor () -> Void = {}
    ) {
        self.publishingMode = publishingMode
        self.instanceLock = instanceLock
        self.appNap = appNap
        self.sources = sources
        self.publication = publication
        self.manualRequests = manualRequests
        self.manualReady = manualReady
        self.hasReaders = hasReaders
        self.wakeMonitor = wakeMonitor
        self.networkMonitor = networkMonitor
        self.secretRetry = secretRetry
        self.secrets = secrets
        self.ownerFlows = ownerFlows
        self.activationObserver = activationObserver
        self.prepareSources = prepareSources
        self.signingReady = signingReady
        observeSchedulingChanges()
    }

    func start() async {
        guard state == .stopped else { return }
        guard instanceLock.acquire() else {
            state = .secondInstance
            return
        }
        prepareSources()
        if !signingReady {
            await publication.setSuspended(true)
            await manualRequests.setSuspended(true)
        }
        await ownerFlows.home.load()
        await ownerFlows.home.reconcileNotifications()
        await manualRequests.updateReadiness(ready: manualReady, hasReaders: hasReaders)
        await appNap.start()
        if signingReady { await sources.start() }
        await wakeMonitor.start()
        await networkMonitor.start()
        await secretRetry.start()
        state = .running
    }

    func foreground() async {
        await ownerFlows.home.reconcileNotifications()
        await sources.refresh(.foreground)
    }

    private func observeSchedulingChanges() {
        let names: [Notification.Name] = [
            NSApplication.didBecomeActiveNotification,
            .NSSystemTimeZoneDidChange,
            .NSSystemClockDidChange,
        ]
        systemChangeObservers = names.map { name in
            Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: name) {
                    guard let self else { return }
                    await ownerFlows.home.reconcileNotifications()
                }
            }
        }
    }

    func stop() async {
        await wakeMonitor.stop()
        await networkMonitor.stop()
        await manualRequests.stop()
        await sources.stop()
        await publication.stop()
        await secretRetry.stop()
        await secrets.invalidateCache()
        await appNap.stop()
        instanceLock.release()
        activationObserver.invalidate()
        state = .stopped
    }
}
