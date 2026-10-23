import Foundation
import ResetRadarDomain

/// Why automatic publication stopped. A stop persists for the publisher's life; only a new
/// process or `resume()` after relay setup clears it.
public enum StopReason: Sendable, Equatable {
    case snapshotConflict
    case authorizationRequired
    case payloadRejected
    case incompatible
}

public enum PublishOutcome: Sendable, Equatable {
    case published(sequence: UInt64)
    /// The policy says the change is not yet due; `next` is when to ask again.
    case notDue(next: Date?)
    /// Relay setup is missing, pending, or being destroyed.
    case paused
    case secretsUnavailable
    case envelopeTooLarge
    case stopped(StopReason)
    case backoff(until: Date)
}

public enum IngestOutcome: Sendable, Equatable {
    case committed
    case unchanged
    case inProgress
    case skipped
    case failed(TransportStatus)
    /// The reader store could not be read or written; the transport status is unchanged.
    case storageFailed
}

public enum MacRefreshOutcome: Sendable, Equatable {
    case completed(ManualRefreshResult.Outcome)
    case macAsleepOrPending
    case rateLimited
    case alreadyCompleted
    case relayUnavailable
    case timedOut
    case pairingPending
    /// The action was scoped to Claude Code only, so no request was posted.
    case notRequested
    case failed(TransportStatus)
}

public enum HandleOutcome: Sendable, Equatable {
    /// No pending request needed work.
    case idle
    /// `count` requests were satisfied, published, and acknowledged.
    case handled(count: Int)
    /// The 30-second forced-read limit defers the read until the given instant.
    case waiting(until: Date)
    /// The result was not published, so no request was acknowledged.
    case publicationFailed(PublishOutcome)
}

public enum ActivationState: Sendable, Equatable {
    case pending
    case confirmed
    /// The relay-assigned deadline passed without activation.
    case expired
}

public enum PairingOutcome: Sendable, Equatable {
    /// Activation succeeded.
    case paired
    /// Saved locally; activation was not confirmed and will be retried.
    case awaitingActivation
    /// An authenticated 401 after expiry or revocation cleared the pending pairing.
    case activationRejected
    case failed(PairingError)
}

public enum ForgetOutcome: Sendable, Equatable {
    case complete
    /// Keychain or surface cleanup failed; `retryCleanup` completes it.
    case cleanupPending
    /// The local transaction did not commit, so nothing was forgotten; `retryCleanup` repeats it.
    case failed
}

public enum ReceiptOutcome: Sendable, Equatable {
    case confirmed
    case ignored
}

public enum WatchCommitOutcome: Sendable, Equatable {
    case committed
    /// A clear was committed as a tombstone and its receipt queued.
    case cleared
    case idempotent
    case ignoredOlder
    case rejectedConflict
    case rejectedByLocalEraseHold
    /// The cache could not be read or written; nothing changed.
    case storageFailed
    /// A different installation ID: held for owner confirmation.
    case heldForOwnerConfirmation
}

public enum ReconcileOutcome: Sendable, Equatable {
    case reconciled
    /// Another instance holds the gate or the claim was interrupted; nothing was changed.
    case retryable
}

public enum OptInOutcome: Sendable, Equatable {
    case enabled
    case disabled
    /// Authorization is denied; the UI shows the route to system settings.
    case denied
}
