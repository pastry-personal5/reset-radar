import ResetRadarDomain

public protocol NotificationScheduler: Sendable {
    func authorization() async -> NotificationAuthorization
    func requestAuthorization() async -> NotificationAuthorization
    func pending() async -> [ResetRequest]
    func schedule(_ request: ResetRequest) async throws
    func cancel(accountWindow: AccountWindow) async
}
