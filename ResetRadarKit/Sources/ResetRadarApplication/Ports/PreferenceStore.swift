import ResetRadarDomain

/// Typed per-device preferences, never synchronized.
public protocol PreferenceStore: Sendable {
    /// `nil` until the owner chooses.
    func notificationOptIn(_ accountWindow: AccountWindow) async -> Bool?
    func setNotificationOptIn(_ accountWindow: AccountWindow, enabled: Bool) async
    func notificationOptIn(_ selection: WindowSelection) async -> Bool?
    func setNotificationOptIn(_ selection: WindowSelection, enabled: Bool) async
    func complicationEnabled() async -> Bool
    func setComplicationEnabled(_ enabled: Bool) async
}

extension PreferenceStore {
    public func notificationOptIn(_ selection: WindowSelection) async -> Bool? {
        guard case .standard(let accountWindow) = selection else { return nil }
        return await notificationOptIn(accountWindow)
    }

    public func setNotificationOptIn(_ selection: WindowSelection, enabled: Bool) async {
        guard case .standard(let accountWindow) = selection else { return }
        await setNotificationOptIn(accountWindow, enabled: enabled)
    }
}
