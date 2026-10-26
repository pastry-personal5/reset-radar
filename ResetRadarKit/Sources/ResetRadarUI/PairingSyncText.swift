import Foundation
import ResetRadarApplication
import ResetRadarDomain

/// Pairing & Sync copy: the reader relationship, local cleanup, and Watch Erasure Status.
public enum PairingSyncText {
    public static func status(_ pairing: PairingStatusReadModel?) -> String {
        guard let pairing else { return "Local pairing data can’t be read yet." }
        if pairing.cleanupPending { return "Local Cleanup Pending" }
        return switch pairing.state {
        case .notPaired: "Not paired with a Collector Mac"
        case .awaitingActivation: "Confirming Pairing"
        case .paired: "Paired with your Collector Mac"
        }
    }

    /// Whether this device may accept a new Pairing Package now.
    public static func acceptsPairingPackage(_ pairing: PairingStatusReadModel?) -> Bool {
        guard let pairing else { return false }
        return pairing.state == .notPaired && !pairing.cleanupPending
    }

    /// Whether Forget Mac has anything to remove or finish.
    public static func offersForgetMac(_ pairing: PairingStatusReadModel?) -> Bool {
        guard let pairing else { return false }
        return pairing.state != .notPaired || pairing.cleanupPending
    }

    public static func watchErasure(_ state: WatchEraseState) -> String {
        switch state {
        case .pending:
            "Watch Erasure Status: pending. The Watch cache may remain until the Watch "
                + "reconnects or you choose Erase Watch Data in the Watch app."
        case .confirmed(_, let confirmedAt):
            "Watch Erasure Status: confirmed for the responding Watch cache on "
                + confirmedAt.formatted(date: .abbreviated, time: .shortened)
                + ". This does not cover another paired Watch or an already rendered "
                + "complication."
        }
    }

    public static func pairingOutcome(_ outcome: PairingOutcome) -> String {
        switch outcome {
        case .paired: "Paired. Accounts appear after the Collector Mac publishes."
        case .awaitingActivation:
            "Pairing is saved. Reset Radar keeps confirming it with the relay."
        case .activationRejected:
            "The relay rejected this pairing because it expired or was revoked. Create a new "
                + "Pairing Package on the Collector Mac."
        case .failed(let error): pairingError(error)
        }
    }

    public static func pairingError(_ error: PairingError) -> String {
        switch error {
        case .codec(let codec):
            codecError(codec)
        case .confirmationRequired:
            "Compare the Pairing Confirmation Code with the Collector Mac before confirming."
        case .forgetRequired:
            "This device is already paired. Use Forget Mac before pairing another Mac."
        case .cleanupPending:
            "Local cleanup from Forget Mac is unfinished. Retry cleanup before pairing."
        case .secretsUnavailable:
            "Pairing secrets could not be read. Unlock this device and try again."
        case .storageFailed:
            "The pairing could not be saved on this device. Nothing was activated."
        case .preflightFailed(let status):
            "The relay check failed: \(ReaderVocabulary.transport(status)) Nothing was saved."
        case .nothingToResume:
            "There is no saved pairing to confirm."
        }
    }

    private static func codecError(_ error: PairingCodecError) -> String {
        switch error {
        case .expired: "This Pairing Package has expired. Create a new one on the Collector Mac."
        case .endpointNotAllowed: "This Pairing Package names a relay Reset Radar does not accept."
        case .unsupportedVersion: "This Pairing Package needs a newer version of Reset Radar."
        default: "This is not a valid Reset Radar Pairing Package."
        }
    }

    public static func forgetOutcome(_ outcome: ForgetOutcome) -> String {
        switch outcome {
        case .complete:
            "This device forgot the Collector Mac and erased its local usage. The Mac still "
                + "lists this reader until you revoke it there."
        case .cleanupPending:
            "Local Cleanup Pending. Old usage stays hidden; retry cleanup to finish."
        case .failed:
            "Forget Mac could not be saved, so nothing changed. Try again."
        }
    }
}

/// The iPad's device-local Home selection, kept by stable account ID.
public enum AccountSelection {
    /// The current or stored account when it is still listed, otherwise the first account in
    /// display order; `nil` for an empty list.
    public static func resolve(
        current: AccountID?, stored: AccountID?, ordered: [AccountID]
    ) -> AccountID? {
        if let current, ordered.contains(current) { return current }
        if let stored, ordered.contains(stored) { return stored }
        return ordered.first
    }
}
