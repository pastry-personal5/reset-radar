import ResetRadarDomain

public protocol NotificationScheduler: Sendable {
    func authorization() async -> NotificationAuthorization
    func requestAuthorization() async -> NotificationAuthorization
    func pending() async -> [ResetRequest]
    /// Every request identifier owned by Reset Radar, including malformed legacy state.
    func ownedPendingIdentifiers() async -> Set<String>
    func schedule(_ request: ResetRequest) async throws
    func cancel(accountWindow: AccountWindow) async
    func cancel(selection: WindowSelection) async
    func cancel(identifier: String) async
}

extension NotificationScheduler {
    public func cancel(selection: WindowSelection) async {
        guard case .standard(let accountWindow) = selection else { return }
        await cancel(accountWindow: accountWindow)
    }

    public func ownedPendingIdentifiers() async -> Set<String> {
        Set(await pending().map(\.identifier))
    }

    public func cancel(identifier: String) async {}
}
