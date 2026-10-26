import BackgroundTasks
import Foundation
import ResetRadarApplication

@MainActor
protocol BackgroundRefreshTask: AnyObject {
    var expirationHandler: (() -> Void)? { get set }
    func setTaskCompleted(success: Bool)
}

extension BGAppRefreshTask: BackgroundRefreshTask {}

/// Owns the sole background-refresh registration. The scheduler's begin date is an earliest
/// request only; each submission replaces any queued request for this identifier.
@MainActor
enum BackgroundRefreshDriver {
    static let identifier = "com.unidentifiedstealthstartup.ResetRadar.refresh"
    private static weak var environment: ReaderEnvironment?
    private static var registered = false

    static func register(environment: ReaderEnvironment) -> Bool {
        self.environment = environment
        guard !registered else { return true }
        let accepted = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier, using: nil
        ) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                guard let environment = self.environment else {
                    refresh.setTaskCompleted(success: false)
                    return
                }
                await environment.runBackgroundRefresh(refresh)
            }
        }
        registered = accepted
        return accepted
    }

    @discardableResult
    static func submit(earliestBeginDate: Date) -> Bool {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = earliestBeginDate
        do {
            try BGTaskScheduler.shared.submit(request)
            return true
        } catch {
            return false
        }
    }
}
