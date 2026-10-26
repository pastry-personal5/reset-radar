import Foundation
import ResetRadarApplication
import ResetRadarDomain

/// Typed per-device preferences. Notification opt-in is stored per account window and never
/// synchronized.
public struct DefaultsPreferenceStore: PreferenceStore {
    private static let complicationKey = "complicationEnabled"

    // `UserDefaults` is documented thread-safe but not annotated `Sendable`.
    nonisolated(unsafe) private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    private static func optInKey(_ accountWindow: AccountWindow) -> String {
        "notificationOptIn.\(accountWindow.accountID.hex).\(accountWindow.window.rawValue)"
    }

    private static func optInKey(_ selection: WindowSelection) -> String {
        switch selection {
        case .standard(let accountWindow): optInKey(accountWindow)
        case .additional: "notificationOptIn.v1.\(selection.stableDigest)"
        }
    }

    public func notificationOptIn(_ accountWindow: AccountWindow) async -> Bool? {
        let key = Self.optInKey(accountWindow)
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.bool(forKey: key)
    }

    public func setNotificationOptIn(_ accountWindow: AccountWindow, enabled: Bool) async {
        defaults.set(enabled, forKey: Self.optInKey(accountWindow))
    }

    public func notificationOptIn(_ selection: WindowSelection) async -> Bool? {
        let key = Self.optInKey(selection)
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.bool(forKey: key)
    }

    public func setNotificationOptIn(_ selection: WindowSelection, enabled: Bool) async {
        defaults.set(enabled, forKey: Self.optInKey(selection))
    }

    public func complicationEnabled() async -> Bool {
        defaults.bool(forKey: Self.complicationKey)
    }

    public func setComplicationEnabled(_ enabled: Bool) async {
        defaults.set(enabled, forKey: Self.complicationKey)
    }
}
