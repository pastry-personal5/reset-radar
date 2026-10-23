import ResetRadarDomain

/// Typed per-device preferences, never synchronized.
public protocol PreferenceStore: Sendable {
    /// `nil` until the owner chooses.
    func notificationOptIn(_ slot: HomeSlot) async -> Bool?
    func setNotificationOptIn(_ slot: HomeSlot, enabled: Bool) async
    func complicationEnabled() async -> Bool
    func setComplicationEnabled(_ enabled: Bool) async
}
