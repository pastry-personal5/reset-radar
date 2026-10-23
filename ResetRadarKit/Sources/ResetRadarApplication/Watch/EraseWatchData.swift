import Foundation

/// The owner-confirmed local erase on the Watch. It needs no iPhone connection.
public actor EraseWatchData {
    private let cache: any WatchCacheStore
    private let reloader: any SurfaceReloader

    public init(cache: any WatchCacheStore, reloader: any SurfaceReloader) {
        self.cache = cache
        self.reloader = reloader
    }

    /// Clears the snapshot, keeps the revision tombstone, and holds later usage payloads until
    /// the owner resets Watch pairing.
    @discardableResult
    public func erase() async -> EraseOutcome {
        do {
            try await cache.transact { state in
                state.snapshot = nil
                state.relaySequence = nil
                state.transportStatus = .notPaired
                state.lastRelayContactAt = nil
                state.lastCommitAt = nil
                state.cleared = true
                state.localEraseHold = true
            }
        } catch {
            return .failed
        }
        reloader.reloadComplications()
        return .erased
    }
}

public enum EraseOutcome: Sendable, Equatable {
    case erased
    case failed
}
