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
    @Published private(set) var state = State.stopped

    private let instanceLock: SingleInstanceLock
    private let appNap: AppNapGuard
    private let sources: SourceRuntime
    private let publication: PublicationDriver
    private let manualRequests: ManualRequestDriver
    private let wakeMonitor: WakeMonitor
    private let networkMonitor: NetworkMonitor
    private let secretRetry: SecretRetryDriver
    private let secrets: SessionSecretCache
    private let activationObserver: FirstInstanceActivationObserver

    init(
        publishingMode: PublishingMode, instanceLock: SingleInstanceLock,
        appNap: AppNapGuard, sources: SourceRuntime, publication: PublicationDriver,
        manualRequests: ManualRequestDriver, wakeMonitor: WakeMonitor,
        networkMonitor: NetworkMonitor, secretRetry: SecretRetryDriver,
        secrets: SessionSecretCache, ownerFlows: OwnerFlowModels,
        activationObserver: FirstInstanceActivationObserver
    ) {
        self.publishingMode = publishingMode
        self.instanceLock = instanceLock
        self.appNap = appNap
        self.sources = sources
        self.publication = publication
        self.manualRequests = manualRequests
        self.wakeMonitor = wakeMonitor
        self.networkMonitor = networkMonitor
        self.secretRetry = secretRetry
        self.secrets = secrets
        self.ownerFlows = ownerFlows
        self.activationObserver = activationObserver
    }

    func start() async {
        guard state == .stopped else { return }
        guard instanceLock.acquire() else {
            state = .secondInstance
            return
        }
        await appNap.start()
        await sources.start()
        await wakeMonitor.start()
        await networkMonitor.start()
        await secretRetry.start()
        state = .running
    }

    func foreground() async {
        await sources.refresh(.foreground)
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
