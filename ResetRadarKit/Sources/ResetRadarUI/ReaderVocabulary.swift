import Foundation
import ResetRadarDomain

/// Visible names from the UX terms. Code-facing names never reach the interface.
public enum ReaderVocabulary {
    public static func productName(_ product: ProductID) -> String {
        switch product {
        case .codex: "Codex"
        case .claudeCode: "Claude Code"
        }
    }

    public static func sourceName(_ kind: SourceKind) -> String {
        switch kind {
        case .codexAppServer: "Codex app-server"
        case .claudeCodeStatusLine: "Claude Code status line"
        }
    }

    /// The compact caption below a ring.
    public static func windowCaption(_ window: AccountWindow.StandardWindow) -> String {
        switch window {
        case .fiveHour: "5-hour"
        case .weekly: "Weekly"
        }
    }

    /// The spoken and heading form of a standard window name.
    public static func windowName(_ window: AccountWindow.StandardWindow) -> String {
        switch window {
        case .fiveHour: "Five-hour"
        case .weekly: "Weekly"
        }
    }

    /// A provider window's label, or a neutral description when the provider sent none.
    public static func windowLabel(_ window: AllowanceWindow) -> String {
        if let label = window.label, !label.isEmpty { return label }
        let standard = AccountWindow.StandardWindow.allCases.first {
            $0.durationMinutes == window.durationMinutes
        }
        if window.isDefaultLimit, let standard { return windowName(standard) }
        if let minutes = window.durationMinutes { return "\(minutes)-minute window" }
        return "Additional window"
    }

    public static func sourceState(_ state: SourceState) -> String {
        switch state {
        case .reporting: "Reporting"
        case .unavailable: "Unavailable"
        case .signedOut: "Signed out"
        case .sourceOffline: "Offline"
        case .incompatible: "Incompatible"
        }
    }

    /// Compatibility as the provenance area reports it.
    public static func compatibility(_ state: SourceState) -> String {
        state == .incompatible ? "Incompatible source version" : "Compatible"
    }

    /// The Collector Mac's publication status; `nil` means there is no snapshot to judge.
    public static func macPublication(_ macLive: Bool?) -> String {
        switch macLive {
        case true: "Publishing"
        case false: "Not publishing recently"
        case nil: "Unknown until the first publication"
        }
    }

    /// Device delivery status. `current` is the only state that is not a Sync Problem.
    public static func transport(_ status: TransportStatus) -> String {
        switch status {
        case .notPaired: "Not paired"
        case .awaitingFirstPublish: "Waiting for Mac Data"
        case .current: "Synced"
        case .offline: "The relay could not be reached."
        case .authorizationRequired: "This device’s pairing expired or was revoked."
        case .quotaLimited: "The relay reached its daily limit."
        case .invalidSnapshot: "The relay sent data that could not be verified."
        case .incompatible: "The relay data needs a newer version of Reset Radar."
        case .secretsUnavailable: "Pairing secrets are unavailable until this device is unlocked."
        }
    }

    /// True for a delivery failure that keeps committed rows visible beside a Sync Problem.
    public static func isSyncProblem(_ status: TransportStatus) -> Bool {
        switch status {
        case .offline, .authorizationRequired, .quotaLimited, .invalidSnapshot, .incompatible,
            .secretsUnavailable:
            true
        case .notPaired, .awaitingFirstPublish, .current:
            false
        }
    }
}
