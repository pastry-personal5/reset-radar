import Foundation
import ResetRadarApplication
import ResetRadarDomain

/// Typed per-device preferences. Notification opt-in is stored per slot and never synchronized.
public struct DefaultsPreferenceStore: PreferenceStore {
    private static let complicationKey = "complicationEnabled"

    // `UserDefaults` is documented thread-safe but not annotated `Sendable`.
    nonisolated(unsafe) private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    private static func optInKey(_ slot: HomeSlot) -> String {
        "notificationOptIn.\(slot.rawValue)"
    }

    public func notificationOptIn(_ slot: HomeSlot) async -> Bool? {
        let key = Self.optInKey(slot)
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.bool(forKey: key)
    }

    public func setNotificationOptIn(_ slot: HomeSlot, enabled: Bool) async {
        defaults.set(enabled, forKey: Self.optInKey(slot))
    }

    public func complicationEnabled() async -> Bool {
        defaults.bool(forKey: Self.complicationKey)
    }

    public func setComplicationEnabled(_ enabled: Bool) async {
        defaults.set(enabled, forKey: Self.complicationKey)
    }
}
