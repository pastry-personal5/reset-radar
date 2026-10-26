import Foundation
import ResetRadarApplication
import ResetRadarDomain

/// One user-started Refresh, from its first relay read to its Refresh Result.
public struct RefreshActivity: Equatable, Sendable {
    public enum Scope: Equatable, Sendable {
        /// Home: every configured Codex account plus the ordinary relay read.
        case home
        case account(AccountID)
    }

    public enum Phase: Equatable, Sendable {
        case readingRelay
        /// The relay read finished; the Codex request is being sent.
        case relayContacted
        case waitingForMac(deadline: Date)
        case finished(MacRefreshOutcome)
        /// The scene left the foreground before a result arrived; nothing was re-posted.
        case cancelled
    }

    public let scope: Scope
    public var phase: Phase

    public init(scope: Scope, phase: Phase = .readingRelay) {
        self.scope = scope
        self.phase = phase
    }

    public var isRunning: Bool {
        switch phase {
        case .readingRelay, .relayContacted, .waitingForMac: true
        case .finished, .cancelled: false
        }
    }

    public func concerns(_ accountID: AccountID) -> Bool {
        switch scope {
        case .home: true
        case .account(let target): target == accountID
        }
    }
}

/// Refresh Result copy. Relay contact, an accepted request, and the Mac's matching result stay
/// distinct, and each account reports its own outcome so a failure never hides a sibling.
public enum RefreshFeedback {
    /// The account's line for an activity that concerns it.
    public static func line(
        for product: ProductID, accountID: AccountID, in activity: RefreshActivity
    ) -> String? {
        guard activity.concerns(accountID) else { return nil }
        switch product {
        case .codex: return codexLine(accountID: accountID, phase: activity.phase)
        case .claudeCode: return claudeCodeLine(phase: activity.phase)
        }
    }

    private static func codexLine(accountID: AccountID, phase: RefreshActivity.Phase) -> String {
        switch phase {
        case .readingRelay: return "Reading the relay…"
        case .relayContacted: return "Relay contacted. Sending the request to the Collector Mac…"
        case .waitingForMac:
            return "Request accepted. Waiting up to 45 seconds for the Collector Mac…"
        case .cancelled:
            return "Reset Radar left the foreground before the Collector Mac answered. A later "
                + "result still updates this account."
        case .finished(let outcome):
            return codexOutcome(outcome, accountID: accountID)
        }
    }

    private static func codexOutcome(_ outcome: MacRefreshOutcome, accountID: AccountID) -> String {
        switch outcome {
        case .completed(let results): completed(results, accountID: accountID)
        case .macAsleepOrPending:
            "The Collector Mac may be asleep. The last valid reading stays visible."
        case .timedOut:
            "The Collector Mac did not answer within 45 seconds. The last valid reading stays "
                + "visible."
        case .rateLimited: "Refresh is rate limited. Try again shortly."
        case .alreadyCompleted: "The Collector Mac already completed this request."
        case .notRequested: "Relay read completed. No Mac request was sent."
        case .relayUnavailable, .pairingPending, .failed: sharedOutcome(outcome)
        }
    }

    /// The matching result's line for one account; a missing entry is reported, not assumed.
    private static func completed(
        _ results: [ManualRefreshAccountResult], accountID: AccountID
    ) -> String {
        guard let result = results.first(where: { $0.accountID == accountID }) else {
            return "The Collector Mac returned no result for this account."
        }
        return switch result.outcome {
        case .codexRead: "The Collector Mac read this account."
        case .sourceUnavailable: "The Collector Mac could not read Codex for this account."
        case .accountUnavailable: "This account is unavailable on the Collector Mac."
        }
    }

    private static func claudeCodeLine(phase: RefreshActivity.Phase) -> String {
        switch phase {
        case .readingRelay: return "Reading the relay…"
        case .finished(let outcome):
            switch outcome {
            case .relayUnavailable, .pairingPending, .failed: return sharedOutcome(outcome)
            default: break
            }
        case .relayContacted, .waitingForMac, .cancelled: break
        }
        return "Relay read completed. Claude Code readings arrive when its status line reports; "
            + "Refresh cannot request one."
    }

    private static func sharedOutcome(_ outcome: MacRefreshOutcome) -> String {
        switch outcome {
        case .relayUnavailable:
            "The relay could not be reached. The last valid reading stays visible."
        case .pairingPending: "Pairing is still being confirmed."
        case .failed(let status): "Refresh failed. \(ReaderVocabulary.transport(status))"
        default: "Refresh finished."
        }
    }
}
