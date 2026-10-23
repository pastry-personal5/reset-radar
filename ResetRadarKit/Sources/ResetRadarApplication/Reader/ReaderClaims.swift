import Foundation
import ResetRadarDomain

/// What a fetch may use, copied out of `ReaderState` when the claim is taken.
public struct ClaimedFetch: Sendable, Equatable {
    public let claim: FetchClaim
    public let pairing: ReaderPairing
    public let etag: String?
    public let committedSequence: UInt64?
    public let hasValidatedSnapshot: Bool
    public let transportStatus: TransportStatus
}

public enum ClaimResult: Sendable, Equatable {
    case claimed(ClaimedFetch)
    case inProgress
    case skipped(SkipReason)
}

/// The cross-process fetch lease over `ReaderStore`, shared by ingestion and the reader's
/// bounded manual-refresh wait so a concurrent trigger reports `inProgress`.
public struct ReaderClaims: Sendable {
    public static let leaseDuration: TimeInterval = 30

    private let reader: any ReaderStore
    private let random: any SecretGenerator
    private let clock: any AppClock

    public init(reader: any ReaderStore, random: any SecretGenerator, clock: any AppClock) {
        self.reader = reader
        self.random = random
        self.clock = clock
    }

    public func claim(trigger: FetchTrigger) async throws -> ClaimResult {
        let now = clock.now
        let id = try random.randomUUID()
        return try await reader.transact { state in
            switch ReaderRefreshPolicy.decide(trigger: trigger, state: state, now: now) {
            case .inProgress:
                return .inProgress
            case .skip(let reason):
                return .skipped(reason)
            case .fetch:
                let claim = FetchClaim(
                    id: id, expiresAt: now.addingTimeInterval(Self.leaseDuration))
                state.lease = claim
                state.lastAttemptAt = now
                // `fetch` implies a pairing; the guard keeps the compiler honest.
                guard let pairing = state.pairing else { return .skipped(.notPaired) }
                let valid =
                    state.snapshot != nil && state.snapshot?.publisherID == pairing.publisherID
                return .claimed(
                    ClaimedFetch(
                        claim: claim, pairing: pairing, etag: state.etag,
                        committedSequence: state.committedSequence,
                        hasValidatedSnapshot: valid, transportStatus: state.transportStatus))
            }
        }
    }

    /// Releases a claim without a result, only if it still owns the lease.
    public func release(_ claim: FetchClaim) async throws {
        try await reader.transact { state in
            if state.lease?.id == claim.id { state.lease = nil }
        }
    }
}
