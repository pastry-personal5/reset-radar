import Foundation
import ResetRadarDomain

public protocol LiveActivityController: Sendable {
    func areActivitiesEnabled() async -> Bool
    func list() async -> [RunningActivity]
    func start(
        accountWindow: AccountWindow, content: ActivityContent, staleDate: Date
    ) async throws
    func update(accountWindow: AccountWindow, content: ActivityContent, staleDate: Date) async
    /// Ends with immediate dismissal.
    func end(accountWindow: AccountWindow) async
}
