import Foundation
import ResetRadarDomain

/// Commits payloads on the Watch under the delivery-revision ordering rules.
public actor CommitWatchPayload {
    private let cache: any WatchCacheStore
    private let phone: any PhoneLink
    private let reloader: any SurfaceReloader

    public init(
        cache: any WatchCacheStore, phone: any PhoneLink, reloader: any SurfaceReloader
    ) {
        self.cache = cache
        self.phone = phone
        self.reloader = reloader
    }

    public func commit(_ payload: WatchPayload) async -> WatchCommitOutcome {
        guard let outcome = try? await cache.transact({ Self.apply(payload, to: &$0) }) else {
            return .rejectedConflict
        }
        await finish(outcome, payload: payload)
        return outcome
    }

    /// Accepts the previewed payload of a changed iPhone installation after the owner confirms:
    /// the old cache is cleared first.
    public func resetPairing(confirming payload: WatchPayload) async -> WatchCommitOutcome {
        let outcome = try? await cache.transact { state -> WatchCommitOutcome in
            guard state.pendingInstallation == payload else { return .rejectedConflict }
            state = WatchCacheState()
            state.pendingInstallation = nil
            return Self.apply(payload, to: &state)
        }
        guard let outcome else { return .rejectedConflict }
        await finish(outcome, payload: payload)
        return outcome
    }

    /// Ends a local-erase hold for the same installation; the revision floor never drops.
    public func resetPairing() async {
        try? await cache.transact { $0.localEraseHold = false }
    }

    private func finish(_ outcome: WatchCommitOutcome, payload: WatchPayload) async {
        switch outcome {
        case .committed:
            reloader.reloadComplications()
        case .cleared:
            reloader.reloadComplications()
            await queueReceipt(for: payload)
        case .idempotent where payload.cleared:
            await queueReceipt(for: payload)
        default:
            break
        }
    }

    private func queueReceipt(for payload: WatchPayload) async {
        // The receipt stays queued by WatchConnectivity; a failure to queue is retried by the
        // iPhone's resend of the same clear.
        try? await phone.queueReceipt(
            WatchEraseReceipt(
                installationID: payload.installationID, deliveryRevision: payload.deliveryRevision))
    }

    private static func apply(
        _ payload: WatchPayload, to state: inout WatchCacheState
    ) -> WatchCommitOutcome {
        if let current = state.installationID, current != payload.installationID {
            state.pendingInstallation = payload
            return .heldForOwnerConfirmation
        }
        if state.installationID != nil {
            if payload.deliveryRevision < state.deliveryRevision { return .ignoredOlder }
            if payload.deliveryRevision == state.deliveryRevision {
                return state.asPayload() == payload ? .idempotent : .rejectedConflict
            }
            if state.localEraseHold && !payload.cleared { return .rejectedByLocalEraseHold }
        }
        state.installationID = payload.installationID
        state.deliveryRevision = payload.deliveryRevision
        state.snapshot = payload.snapshot
        state.relaySequence = payload.relaySequence
        state.transportStatus = payload.transportStatus
        state.lastRelayContactAt = payload.lastRelayContactAt
        state.lastCommitAt = payload.lastCommitAt
        state.cleared = payload.cleared
        state.pendingInstallation = nil
        return payload.cleared ? .cleared : .committed
    }
}

extension WatchCacheState {
    /// The payload this cache would equal if it had just been committed.
    fileprivate func asPayload() -> WatchPayload? {
        guard let installationID else { return nil }
        return try? WatchPayload(
            installationID: installationID, deliveryRevision: deliveryRevision,
            snapshot: cleared ? nil : snapshot, relaySequence: relaySequence,
            transportStatus: transportStatus, lastRelayContactAt: lastRelayContactAt,
            lastCommitAt: lastCommitAt, cleared: cleared)
    }
}
