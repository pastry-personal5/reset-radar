import Foundation
import ResetRadarDomain

/// Builds the `WatchPayload` after a commit or transport-status change and sends it as the
/// application context, plus a complication transfer when the daily budget allows.
public actor ForwardToWatch: AfterCommitStep {
    private let reader: any ReaderStore
    private let preferences: any PreferenceStore
    private let watch: any WatchLink
    private let clock: any AppClock

    public init(
        reader: any ReaderStore, preferences: any PreferenceStore, watch: any WatchLink,
        clock: any AppClock
    ) {
        self.reader = reader
        self.preferences = preferences
        self.watch = watch
        self.clock = clock
    }

    public func afterCommit(_ event: CommitEvent) async {
        await send(after: event)
    }

    public func send(after event: CommitEvent) async {
        guard let state = try? await reader.load() else { return }
        if let erasure = state.watchErasePending {
            // Later usage waits for the receipt: only the saved clear goes out.
            await deliver(erasure.clear)
            return
        }
        guard !state.forgetCleanupPending, !state.awaitingActivation, state.pairing != nil,
            let payload = await persistPayload(for: event)
        else { return }
        await deliver(payload)
        await transferComplication(payload, snapshot: event.snapshot)
    }

    /// Persists one revision per distinct payload before anything is sent.
    private func persistPayload(for event: CommitEvent) async -> WatchPayload? {
        let snapshot = Self.watchCopy(of: event.snapshot)
        return try? await reader.transact { state -> WatchPayload? in
            guard
                let candidate = try? WatchPayload(
                    installationID: state.installationID, deliveryRevision: 0, snapshot: snapshot,
                    relaySequence: state.committedSequence, transportStatus: state.transportStatus,
                    lastRelayContactAt: state.lastContactAt, lastCommitAt: state.lastCommitAt,
                    cleared: false)
            else { return nil }
            if let last = state.lastWatchPayload, last.withRevision(0) == candidate {
                return last
            }
            state.watchDeliveryRevision += 1
            state.hasSentToWatch = true
            let payload = candidate.withRevision(state.watchDeliveryRevision)
            state.lastWatchPayload = payload
            return payload
        } ?? nil
    }

    /// The Watch needs usage state, not other readers' opaque request results.
    private static func watchCopy(of snapshot: UsageSnapshot) -> UsageSnapshot {
        let stripped = try? UsageSnapshot(
            publisherID: snapshot.publisherID, generatedAt: snapshot.generatedAt,
            heartbeatSeconds: snapshot.heartbeatSeconds, accounts: snapshot.accounts,
            sources: snapshot.sources,
            windows: snapshot.windows, diagnostics: snapshot.diagnostics)
        return stripped ?? snapshot
    }

    private func deliver(_ payload: WatchPayload) async {
        // An unreachable or inactive Watch session is not an error for the iPhone.
        try? await watch.sendContext(payload)
    }

    private func transferComplication(_ payload: WatchPayload, snapshot: UsageSnapshot) async {
        let now = clock.now
        let values = Self.complicationValues(of: snapshot, now: now)
        let enabled = await preferences.complicationEnabled()
        let allowed = try? await reader.transact { state -> Bool in
            let budget = ComplicationBudgetState(
                enabled: enabled, transfers: state.complicationTransfers)
            guard
                ComplicationBudgetPolicy.allows(
                    state: budget, changedSince: values != state.lastComplicationValues, now: now)
            else { return false }
            // Deliberately counted before the transfer: a failed transfer still spends budget,
            // which keeps the system's daily allowance safe, and the unchanged values are not
            // retried until they change.
            state.complicationTransfers =
                state.complicationTransfers.filter {
                    now.timeIntervalSince($0) < ComplicationBudgetPolicy.window
                } + [now]
            state.lastComplicationValues = values
            return true
        }
        if allowed == true { try? await watch.transferComplication(payload) }
    }

    static func complicationValues(of snapshot: UsageSnapshot, now: Date) -> ComplicationValues {
        ComplicationValues(
            cells: AccountDisplayOrder.sorted(snapshot.accounts).flatMap { account in
                AccountWindow.StandardWindow.allCases.map { standardWindow in
                    let accountWindow = AccountWindow(
                        accountID: account.id, window: standardWindow)
                    let (resolution, _) = AccountWindowResolver.resolve(
                        accountWindow, in: snapshot, now: now)
                    guard case .window(let window) = resolution else {
                        return .init(
                            accountWindow: accountWindow, usedPercent: nil, resetsAt: nil,
                            sourceState: snapshot.source(for: account.id)?.state)
                    }
                    return .init(
                        accountWindow: accountWindow,
                        usedPercent: window.observation?.usedPercent,
                        resetsAt: window.resetsAt,
                        sourceState: snapshot.source(for: account.id)?.state)
                }
            })
    }
}

extension WatchPayload {
    /// The same payload at another delivery revision.
    func withRevision(_ revision: UInt64) -> WatchPayload {
        // A payload that already exists is valid, so rebuilding it cannot fail.
        (try? WatchPayload(
            installationID: installationID, deliveryRevision: revision, snapshot: snapshot,
            relaySequence: relaySequence, transportStatus: transportStatus,
            lastRelayContactAt: lastRelayContactAt, lastCommitAt: lastCommitAt, cleared: cleared))
            ?? self
    }
}
