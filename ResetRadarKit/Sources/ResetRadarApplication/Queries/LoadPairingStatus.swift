import Foundation

public struct LoadPairingStatus: Sendable {
    private let reader: any ReaderStore
    private let hasWatchStage: Bool

    /// `hasWatchStage` is false on iPad.
    public init(reader: any ReaderStore, hasWatchStage: Bool) {
        self.reader = reader
        self.hasWatchStage = hasWatchStage
    }

    public func load() async -> PairingStatusReadModel? {
        guard let state = try? await reader.load() else { return nil }
        let pairing: PairingState =
            state.pairing == nil
            ? .notPaired : (state.awaitingActivation ? .awaitingActivation : .paired)
        var erase: WatchEraseState?
        if hasWatchStage {
            if let pending = state.watchErasePending {
                erase = .pending(revision: pending.revision)
            } else if let confirmed = state.confirmedWatchErasure {
                erase = .confirmed(revision: confirmed.revision, confirmedAt: confirmed.confirmedAt)
            }
        }
        return PairingStatusReadModel(
            state: pairing, cleanupPending: state.forgetCleanupPending, watchErase: erase)
    }
}
