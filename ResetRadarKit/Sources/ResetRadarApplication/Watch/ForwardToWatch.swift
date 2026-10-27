import Foundation
import ResetRadarDomain

/// Builds the `WatchPayload` after a commit or transport-status change and sends it as the
/// application context, plus a complication transfer when the daily budget allows.
public actor ForwardToWatch: AfterCommitStep {
    private enum ForwardError: Error { case invalidSnapshot }

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

    public func afterCommitOutcome(_ event: CommitEvent) async -> AfterCommitOutcome {
        await sendOutcome(after: event)
    }

    public func send(after event: CommitEvent) async {
        _ = await sendOutcome(after: event)
    }

    public func activate() async { await watch.activate() }

    /// Replays the currently permitted value after launch or session activation. A pending clear
    /// wins even though the reader no longer has a usage snapshot.
    public func reconcileCurrent() async -> AfterCommitOutcome {
        guard let state = try? await reader.load() else { return .retryable }
        if let erasure = state.watchErasePending {
            return await deliver(erasure.clear) ? .complete : .retryable
        }
        guard let snapshot = state.snapshot else { return .complete }
        return await sendOutcome(
            after: CommitEvent(
                snapshot: snapshot, process: .app,
                relaySequence: state.committedSequence ?? 0))
    }

    /// The latest payload permitted for an interactive Watch reply. It is read under the current
    /// ReaderStore transaction rather than reused from an older commit event, so a Forget Mac or
    /// newer relay commit cannot be resurrected by a late request.
    public func currentPayload() async -> WatchPayload? {
        guard let state = try? await reader.load() else { return nil }
        if let erasure = state.watchErasePending { return erasure.clear }
        guard !state.forgetCleanupPending, !state.awaitingActivation, state.pairing != nil,
            let snapshot = state.snapshot
        else { return nil }
        let event = CommitEvent(snapshot: snapshot, process: .app)
        return try? await persistPayload(for: event)
    }

    private func sendOutcome(after event: CommitEvent) async -> AfterCommitOutcome {
        let state: ReaderState
        do {
            state = try await reader.load()
        } catch {
            return .retryable
        }
        if let erasure = state.watchErasePending {
            // Later usage waits for the receipt: only the saved clear goes out.
            return await deliver(erasure.clear) ? .complete : .retryable
        }
        guard !state.forgetCleanupPending, !state.awaitingActivation, state.pairing != nil else {
            return .complete
        }
        let payload: WatchPayload
        do {
            payload = try await persistPayload(for: event)
        } catch {
            return .retryable
        }
        guard await deliver(payload) else { return .retryable }
        guard let snapshot = payload.snapshot else { return .complete }
        return await transferComplication(payload, snapshot: snapshot)
    }

    /// Persists one revision per distinct payload before anything is sent.
    private func persistPayload(for event: CommitEvent) async throws -> WatchPayload {
        return try await reader.transact { state in
            // A commit event may have waited behind a newer ingest or Forget Mac. Always prefer
            // the value held by the same locked ReaderStore transaction used for the revision.
            guard let snapshot = Self.watchCopy(of: state.snapshot ?? event.snapshot) else {
                throw ForwardError.invalidSnapshot
            }
            let candidate = try WatchPayload(
                installationID: state.installationID, deliveryRevision: 0, snapshot: snapshot,
                relaySequence: state.committedSequence, transportStatus: state.transportStatus,
                lastRelayContactAt: state.lastContactAt, lastCommitAt: state.lastCommitAt,
                cleared: false)
            if let last = state.lastWatchPayload, last.withRevision(0) == candidate {
                return last
            }
            state.watchDeliveryRevision += 1
            state.hasSentToWatch = true
            guard let payload = candidate.withRevision(state.watchDeliveryRevision) else {
                throw ForwardError.invalidSnapshot
            }
            state.lastWatchPayload = payload
            return payload
        }
    }

    /// The Watch needs usage state, not other readers' opaque request results.
    private static func watchCopy(of snapshot: UsageSnapshot) -> UsageSnapshot? {
        try? UsageSnapshot(
            publisherID: snapshot.publisherID, generatedAt: snapshot.generatedAt,
            heartbeatSeconds: snapshot.heartbeatSeconds, accounts: snapshot.accounts,
            sources: snapshot.sources,
            windows: snapshot.windows, diagnostics: snapshot.diagnostics)
    }

    private func deliver(_ payload: WatchPayload) async -> Bool {
        do {
            try await watch.sendContext(payload)
            return true
        } catch {
            // The persisted revision makes an activation or launch reconciliation retry safe.
            return false
        }
    }

    private func transferComplication(
        _ payload: WatchPayload, snapshot: UsageSnapshot
    ) async -> AfterCommitOutcome {
        let now = clock.now
        let values = Self.complicationValues(of: snapshot, now: now)
        let enabled = await preferences.complicationEnabled()
        let linkState = await watch.state()
        guard
            linkState.activated, linkState.paired, linkState.watchAppInstalled,
            linkState.complicationEnabled, linkState.remainingComplicationTransfers > 0
        else { return .complete }
        let allowed: Bool
        do {
            allowed = try await reader.transact { state -> Bool in
                let budget = ComplicationBudgetState(
                    enabled: enabled, transfers: state.complicationTransfers)
                guard
                    ComplicationBudgetPolicy.allows(
                        state: budget, changedSince: values != state.lastComplicationValues,
                        now: now)
                else { return false }
                // Deliberately counted before the transfer: a failed transfer still spends budget,
                // which keeps the system's daily allowance safe, and the unchanged values are not
                // retried until they change.
                state.complicationTransfers =
                    state.complicationTransfers.filter {
                        now.timeIntervalSince($0) < ComplicationBudgetPolicy.window
                    } + [now]
                return true
            }
        } catch {
            return .retryable
        }
        guard allowed else { return .complete }
        do {
            try await watch.transferComplication(payload)
            try await reader.transact { $0.lastComplicationValues = values }
        } catch {
            // The reservation remains spent, but the changed-value marker does not advance. A
            // later eligible activation may retry without exceeding the rolling system budget.
            return .retryable
        }
        return .complete
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
    func withRevision(_ revision: UInt64) -> WatchPayload? {
        try? WatchPayload(
            installationID: installationID, deliveryRevision: revision, snapshot: snapshot,
            relaySequence: relaySequence, transportStatus: transportStatus,
            lastRelayContactAt: lastRelayContactAt, lastCommitAt: lastCommitAt, cleared: cleared)
    }
}
