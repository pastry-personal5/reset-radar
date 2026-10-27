import Foundation
import ResetRadarDomain

/// Accepts the Watch's receipt for a pending clear, then lets newer usage flow again.
public actor ConfirmWatchErase {
    private let reader: any ReaderStore
    private let clock: any AppClock
    private let forward: ForwardToWatch?

    public init(reader: any ReaderStore, clock: any AppClock, forward: ForwardToWatch?) {
        self.reader = reader
        self.clock = clock
        self.forward = forward
    }

    public func confirm(_ receipt: WatchEraseReceipt) async -> ReceiptOutcome {
        let now = clock.now
        let confirmed: Bool
        do {
            confirmed = try await reader.transact { state -> Bool in
                guard let pending = state.watchErasePending,
                    receipt.installationID == state.installationID,
                    receipt.deliveryRevision == pending.revision
                else { return false }
                state.watchErasePending = nil
                state.confirmedWatchErasure = ConfirmedWatchErasure(
                    revision: pending.revision, confirmedAt: now)
                return true
            }
        } catch {
            return .storageFailed
        }
        guard confirmed else { return .ignored }
        if let event = await latestUsage() { await forward?.send(after: event) }
        return .confirmed
    }

    /// The committed snapshot, if the reader is fully paired and usage may be shown.
    private func latestUsage() async -> CommitEvent? {
        guard let state = try? await reader.load(), let snapshot = state.snapshot,
            state.pairing != nil
        else { return nil }
        return state.awaitingActivation ? nil : CommitEvent(snapshot: snapshot, process: .app)
    }
}
