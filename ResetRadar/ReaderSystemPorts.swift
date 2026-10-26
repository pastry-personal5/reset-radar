@preconcurrency import ActivityKit
import Foundation
import ResetRadarApplication
import ResetRadarDomain
import UIKit
import WidgetKit

struct SystemReaderClock: AppClock {
    var now: Date { Date() }

    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

/// System state that is not already owned by a Scheduling adapter.
protocol ReaderSystemStatus: Sendable {
    /// `nil` where Live Activities are not offered, which includes iPad.
    func liveActivitiesEnabled() async -> Bool?
}

struct LiveReaderSystemStatus: ReaderSystemStatus {
    func liveActivitiesEnabled() async -> Bool? {
        guard await MainActor.run(body: { UIDevice.current.userInterfaceIdiom == .phone }) else {
            return nil
        }
        return ActivityAuthorizationInfo().areActivitiesEnabled
    }
}

/// The iPad's device-local Home selection: only a stable account ID is kept.
protocol AccountSelectionStore: Sendable {
    func load() -> AccountID?
    func save(_ accountID: AccountID?)
}

struct UserDefaultsSelectionStore: AccountSelectionStore, @unchecked Sendable {
    var defaults: UserDefaults = .standard
    var key = "reader.homeSelection"

    func load() -> AccountID? {
        defaults.string(forKey: key).flatMap(AccountID.init(hex:))
    }

    func save(_ accountID: AccountID?) {
        if let accountID {
            defaults.set(accountID.hex, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

/// A short background-execution assertion, so a locked section finishes or is abandoned
/// before the app suspends while holding the shared-container lock.
protocol BackgroundAssertion: Sendable {
    func begin() async -> UIBackgroundTaskIdentifier
    func end(_ identifier: UIBackgroundTaskIdentifier) async
}

struct ApplicationBackgroundTask: BackgroundAssertion {
    @MainActor private static var active: Set<UIBackgroundTaskIdentifier> = []

    func begin() async -> UIBackgroundTaskIdentifier {
        await MainActor.run {
            let task = ExpiringTask()
            let identifier = UIApplication.shared.beginBackgroundTask(
                withName: "ResetRadar.readerTransaction"
            ) {
                Self.finish(task.identifier)
            }
            task.identifier = identifier
            if identifier != .invalid { Self.active.insert(identifier) }
            return identifier
        }
    }

    func end(_ identifier: UIBackgroundTaskIdentifier) async {
        await MainActor.run { Self.finish(identifier) }
    }

    /// Ends a task once, whether its section finished or the system expired it first.
    @MainActor private static func finish(_ identifier: UIBackgroundTaskIdentifier) {
        guard active.remove(identifier) != nil else { return }
        UIApplication.shared.endBackgroundTask(identifier)
    }
}

@MainActor private final class ExpiringTask {
    var identifier = UIBackgroundTaskIdentifier.invalid
}

/// Holds the assertion for each claim or commit only, never across the network request that
/// the use cases run between two transactions.
struct BackgroundTaskReaderStore: ReaderStore {
    let store: any ReaderStore
    let assertion: any BackgroundAssertion

    func load() async throws -> ReaderState {
        try await store.load()
    }

    func transact<T: Sendable>(
        _ body: @Sendable (inout ReaderState) throws -> T
    ) async throws -> T {
        let identifier = await assertion.begin()
        do {
            let value = try await store.transact(body)
            await assertion.end(identifier)
            return value
        } catch {
            await assertion.end(identifier)
            throw error
        }
    }
}

/// A WidgetKit reload request is the completion boundary for the app pipeline; WidgetKit decides
/// when it renders the new committed cache.
struct WidgetCenterReloader: SurfaceReloader {
    func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
    func reloadComplications() {}
}

/// Explicit iPad implementation: Live Activities are unsupported on this platform configuration.
struct UnavailableLiveActivityController: LiveActivityController {
    func areActivitiesEnabled() async -> Bool { false }
    func list() async -> [RunningActivity] { [] }
    func start(
        accountWindow: AccountWindow, content: ResetRadarApplication.ActivityContent,
        staleDate: Date
    ) async throws {}
    func update(
        accountWindow: AccountWindow, content: ResetRadarApplication.ActivityContent,
        staleDate: Date
    ) async {}
    func end(accountWindow: AccountWindow) async {}
}
