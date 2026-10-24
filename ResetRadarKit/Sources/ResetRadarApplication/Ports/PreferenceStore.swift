import ResetRadarDomain

/// Typed per-device preferences, never synchronized.
public protocol PreferenceStore: Sendable {
    /// `nil` until the owner chooses.
    func notificationOptIn(_ accountWindow: AccountWindow) async -> Bool?
    func setNotificationOptIn(_ accountWindow: AccountWindow, enabled: Bool) async
    func complicationEnabled() async -> Bool
    func setComplicationEnabled(_ enabled: Bool) async
}
