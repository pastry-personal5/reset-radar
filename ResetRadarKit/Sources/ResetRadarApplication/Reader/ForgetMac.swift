import Foundation
import ResetRadarDomain

/// Forgets the paired Mac: one atomic local transaction first, then Watch delivery and cleanup
/// that can be retried.
public actor ForgetMac {
    private let reader: any ReaderStore
    private let secrets: any SecretStore
    private let notifications: any NotificationScheduler
    private let activities: any LiveActivityController
    private let reloader: any SurfaceReloader
    private let watch: (any WatchLink)?

    /// `watch` is `nil` on iPad, which has no Watch stage.
    public init(
        reader: any ReaderStore, secrets: any SecretStore, notifications: any NotificationScheduler,
        activities: any LiveActivityController, reloader: any SurfaceReloader,
        watch: (any WatchLink)?
    ) {
        self.reader = reader
        self.secrets = secrets
        self.notifications = notifications
        self.activities = activities
        self.reloader = reloader
        self.watch = watch
    }

    public func forget() async -> ForgetOutcome {
        let erasure: WatchErasure?
        do {
            erasure = try await reader.transact { state in Self.clear(&state) }
        } catch {
            return .failed  // nothing was persisted: the Mac is still paired
        }
        if let erasure { try? await watch?.sendContext(erasure.clear) }
        return await cleanup()
    }

    public func retryCleanup() async -> ForgetOutcome {
        guard let state = try? await reader.load() else { return .failed }
        guard state.forgetCleanupPending else {
            // Without the marker, a leftover pairing or snapshot means the transaction never ran.
            return state.pairing != nil || state.snapshot != nil ? await forget() : .complete
        }
        if let erasure = state.watchErasePending { try? await watch?.sendContext(erasure.clear) }
        return await cleanup()
    }

    /// The single transaction: usage and pairing state go, the installation ID stays, the Watch
    /// revision advances, and the cleanup and Watch-erasure intents are recorded.
    private static func clear(_ state: inout ReaderState) -> WatchErasure? {
        state.snapshot = nil
        state.pairing = nil
        state.committedSequence = nil
        state.etag = nil
        state.lease = nil
        state.lastAttemptAt = nil
        state.lastSuccessAt = nil
        state.lastContactAt = nil
        state.lastCommitAt = nil
        state.transportStatus = .notPaired
        state.failureCount = 0
        state.backoffUntil = nil
        state.needsAppReconcile = false
        state.stagingReaderID = nil
        state.awaitingActivation = false
        state.pendingManualRequest = nil
        state.lastWatchPayload = nil
        state.lastComplicationValues = nil
        state.watchDeliveryRevision += 1
        state.forgetCleanupPending = true
        guard state.hasSentToWatch,
            let clear = try? WatchPayload(
                installationID: state.installationID, deliveryRevision: state.watchDeliveryRevision,
                snapshot: nil, relaySequence: nil, transportStatus: .notPaired,
                lastRelayContactAt: nil, lastCommitAt: nil, cleared: true)
        else { return nil }
        let erasure = WatchErasure(clear: clear)
        state.watchErasePending = erasure
        return erasure
    }

    private func cleanup() async -> ForgetOutcome {
        do {
            try await secrets.delete(.readToken)
            try await secrets.delete(.contentKey)
        } catch {
            return .cleanupPending
        }
        for identifier in await notifications.ownedPendingIdentifiers() {
            await notifications.cancel(identifier: identifier)
        }
        for activity in await activities.list() {
            await activities.end(accountWindow: activity.accountWindow)
        }
        reloader.reloadWidgets()
        // Removal is fire-and-forget at the framework boundary. Do not clear the durable cleanup
        // marker while an owned request is still visible on a subsequent read.
        guard await notifications.ownedPendingIdentifiers().isEmpty else { return .cleanupPending }
        do {
            try await reader.transact { $0.forgetCleanupPending = false }
        } catch {
            return .cleanupPending
        }
        return .complete
    }
}
