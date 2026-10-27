import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarStorage
import ResetRadarWatchSync
import SwiftUI
import WidgetKit

@MainActor
final class WatchEnvironment: ObservableObject {
    @Published private(set) var home = HomeReadModel(accounts: [], nextChange: nil)
    @Published private(set) var details = UsageDetailsReadModel(
        accounts: [], macLive: nil, transport: .notPaired)
    @Published private(set) var unavailable = false
    @Published private(set) var watchState = WatchCacheState()
    @Published var showEraseConfirmation = false
    @Published var showResetConfirmation = false
    @Published var showInstallationConfirmation = false
    @Published var operationMessage: String?

    private let cache: any WatchCacheStore
    private let bridge: WCSessionBridge
    private let loadHome: LoadHome
    private let loadDetails: LoadUsageDetails
    private let phone: WatchSidePhoneLink
    private let commit: CommitWatchPayload
    private let request: RequestPhoneRefresh
    private let eraseData: EraseWatchData

    private init(cache: any WatchCacheStore, bridge: WCSessionBridge) {
        self.cache = cache
        self.bridge = bridge
        let snapshots = WatchSnapshotStore(store: cache)
        let clock = WatchClock()
        loadHome = LoadHome(visible: VisibleSnapshot(snapshots: snapshots), clock: clock)
        loadDetails = LoadUsageDetails(
            visible: VisibleSnapshot(snapshots: snapshots), clock: clock)
        phone = WatchSidePhoneLink(session: bridge)
        commit = CommitWatchPayload(cache: cache, phone: phone, reloader: WatchReloader())
        request = RequestPhoneRefresh(phone: phone, commit: commit)
        eraseData = EraseWatchData(cache: cache, reloader: WatchReloader())
        let payloads = bridge.incomingPayloads()
        Task { [weak self] in
            for await payload in payloads {
                guard let self else { return }
                let outcome = await self.commit.commit(payload)
                switch outcome {
                case .storageFailed:
                    self.operationMessage = "Watch data could not be saved. Delivery will retry."
                case .clearedReceiptPending:
                    self.operationMessage =
                        "Watch data was erased, but confirmation is still waiting to send."
                default:
                    break
                }
                await self.reload()
                bridge.payloadHandled()
            }
        }
    }

    static func live() -> WatchEnvironment {
        let appGroupRoot = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.unidentifiedstealthstartup.ResetRadar"
        )
        #if DEBUG
            let root =
                appGroupRoot
                ?? URL.applicationSupportDirectory.appending(
                    path: "ResetRadarWatch", directoryHint: .isDirectory)
            let unavailable = false
        #else
            // A signed Watch must use its own App Group container. Do not silently substitute an
            // unrelated sandbox, which could show stale data and defeat installation evidence.
            let root =
                appGroupRoot
                ?? URL.temporaryDirectory.appending(
                    path: "ResetRadarWatchUnavailable", directoryHint: .isDirectory)
            let unavailable = appGroupRoot == nil
        #endif
        let environment = WatchEnvironment(
            cache: FileWatchCacheStore(locations: StorageLocations(root: root, flavor: .release)),
            bridge: WCSessionBridge())
        environment.unavailable = unavailable
        return environment
    }

    func activate() async {
        await phone.activate()
        if !(await commit.retryPendingReceipt()) {
            operationMessage = "Erase confirmation is still waiting to send to the iPhone."
        }
        await reload()
        await request.request()
        await reload()
    }

    func refresh() async {
        await request.request()
        await reload()
    }
    func finishBackgroundDelivery() async {
        await bridge.waitForPayloads()
        await reload()
    }
    func requestEraseConfirmation() { showEraseConfirmation = true }
    func requestResetConfirmation() { showResetConfirmation = true }
    func requestInstallationConfirmation() { showInstallationConfirmation = true }
    func erase() async {
        guard await eraseData.erase() == .erased else {
            operationMessage = "Watch data could not be erased. Try again."
            return
        }
        await reload()
    }
    func resetPairing() async {
        guard await commit.resetPairing() else {
            operationMessage = "Watch pairing could not be reset. Try again."
            return
        }
        await reload()
    }
    func confirmPendingInstallation() async {
        let state: WatchCacheState
        do {
            state = try await cache.load()
        } catch {
            operationMessage = "The pending iPhone data could not be read. Try again."
            return
        }
        guard let payload = state.pendingInstallation else {
            return
        }
        let outcome = await commit.resetPairing(confirming: payload)
        if outcome == .storageFailed {
            operationMessage = "The new iPhone data could not be saved. Try again."
        } else if outcome == .clearedReceiptPending {
            operationMessage = "The data was cleared, but its confirmation is waiting to send."
        }
        await reload()
    }
    private func reload() async {
        do {
            watchState = try await cache.load()
        } catch {
            operationMessage = "Watch data could not be read. Try again."
            return
        }
        home = await loadHome.load()
        details = await loadDetails.load()
    }
}

private struct WatchClock: AppClock {
    var now: Date { Date() }
    func sleep(for duration: Duration) async throws { try await Task.sleep(for: duration) }
}

private struct WatchReloader: SurfaceReloader {
    func reloadWidgets() {}
    func reloadComplications() { WidgetCenter.shared.reloadAllTimelines() }
}
