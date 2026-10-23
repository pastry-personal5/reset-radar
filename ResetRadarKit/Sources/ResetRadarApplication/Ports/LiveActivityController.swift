import Foundation
import ResetRadarDomain

public protocol LiveActivityController: Sendable {
    func areActivitiesEnabled() async -> Bool
    func list() async -> [RunningActivity]
    func start(slot: HomeSlot, content: ActivityContent, staleDate: Date) async throws
    func update(slot: HomeSlot, content: ActivityContent, staleDate: Date) async
    /// Ends with immediate dismissal.
    func end(slot: HomeSlot) async
}
