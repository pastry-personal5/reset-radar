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
            return .storageFailed
        }
        return await finish(outcome, payload: payload)
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
        guard let outcome else { return .storageFailed }
        return await finish(outcome, payload: payload)
    }

    /// Ends a local-erase hold for the same installation; the revision floor never drops.
    @discardableResult
    public func resetPairing() async -> Bool {
        do {
            try await cache.transact { $0.localEraseHold = false }
            return true
        } catch {
            return false
        }
    }

    /// Retries only a receipt already made durable with its cleared cache. This is called at
    /// Watch activation so a queue failure cannot be mistaken for remote erasure.
    @discardableResult
    public func retryPendingReceipt() async -> Bool {
        let state: WatchCacheState
        do {
            state = try await cache.load()
        } catch {
            return false
        }
        guard let receipt = state.pendingEraseReceipt else { return true }
        return await queueReceipt(for: receipt)
    }

    private func finish(
        _ outcome: WatchCommitOutcome, payload: WatchPayload
    ) async -> WatchCommitOutcome {
        switch outcome {
        case .committed:
            reloader.reloadComplications()
            return outcome
        case .cleared:
            reloader.reloadComplications()
            return await queueReceipt(for: payload) ? outcome : .clearedReceiptPending
        case .idempotent where payload.cleared:
            return await queueReceipt(for: payload) ? outcome : .clearedReceiptPending
        default:
            return outcome
        }
    }

    private func queueReceipt(for payload: WatchPayload) async -> Bool {
        await queueReceipt(
            for: WatchEraseReceipt(
                installationID: payload.installationID, deliveryRevision: payload.deliveryRevision))
    }

    private func queueReceipt(for receipt: WatchEraseReceipt) async -> Bool {
        do {
            try await phone.queueReceipt(receipt)
            try await cache.transact { state in
                if state.pendingEraseReceipt == receipt { state.pendingEraseReceipt = nil }
            }
            return true
        } catch {
            return false
        }
    }

    private static func apply(
        _ payload: WatchPayload, to state: inout WatchCacheState
    ) -> WatchCommitOutcome {
        if let current = state.installationID, current != payload.installationID {
            if let pending = state.pendingInstallation {
                guard pending.installationID == payload.installationID else {
                    return .rejectedConflict
                }
                if payload.deliveryRevision < pending.deliveryRevision { return .ignoredOlder }
                if payload.deliveryRevision == pending.deliveryRevision {
                    return pending == payload ? .heldForOwnerConfirmation : .rejectedConflict
                }
            }
            state.pendingInstallation = payload
            return .heldForOwnerConfirmation
        }
        if state.installationID != nil {
            if payload.deliveryRevision < state.deliveryRevision { return .ignoredOlder }
            if payload.deliveryRevision == state.deliveryRevision {
                return state.asPayload() == payload ? .idempotent : .rejectedConflict
            }
        }
        if state.localEraseHold && !payload.cleared { return .rejectedByLocalEraseHold }
        state.installationID = payload.installationID
        state.deliveryRevision = payload.deliveryRevision
        state.snapshot = payload.snapshot
        state.relaySequence = payload.relaySequence
        state.transportStatus = payload.transportStatus
        state.lastRelayContactAt = payload.lastRelayContactAt
        state.lastCommitAt = payload.lastCommitAt
        state.cleared = payload.cleared
        if payload.cleared {
            state.pendingEraseReceipt = WatchEraseReceipt(
                installationID: payload.installationID, deliveryRevision: payload.deliveryRevision)
        }
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
