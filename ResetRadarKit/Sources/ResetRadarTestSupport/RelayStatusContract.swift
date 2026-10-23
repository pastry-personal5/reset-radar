import Foundation
import ResetRadarApplication

/// The status table of the relay protocol as fixtures: the contract that Transport's
/// `ResponseMapper` implements and its tests replay (P1-M7). A status of 0 is a network or TLS
/// failure with no HTTP response.
public enum RelayStatusContract {
    public struct Row: Sendable {
        public let status: Int
        public let scenario: String
        public let outcome: RelayOutcome
    }

    public static let rows: [Row] = [
        Row(
            status: 200, scenario: "snapshot read",
            outcome: .snapshot(Data([0x7B, 0x7D]), etag: "\"1\"", sequence: 1)),
        Row(status: 200, scenario: "snapshot write", outcome: .accepted(sequence: 1)),
        Row(status: 200, scenario: "idempotent activation", outcome: .accepted(sequence: nil)),
        Row(
            status: 202, scenario: "refresh request accepted",
            outcome: .refreshAccepted(expiresAt: Date(timeIntervalSinceReferenceDate: 60))),
        Row(status: 204, scenario: "delete", outcome: .deleted),
        Row(status: 304, scenario: "conditional read unchanged", outcome: .notModified),
        Row(status: 301, scenario: "unexpected redirect", outcome: .protocolFailure),
        Row(status: 400, scenario: "malformed request", outcome: .badRequest),
        Row(status: 401, scenario: "missing, unknown, or revoked token", outcome: .unauthorized),
        Row(
            status: 404, scenario: "authenticated snapshot read before first publish",
            outcome: .awaitingFirstPublish),
        Row(status: 404, scenario: "unknown route", outcome: .protocolFailure),
        Row(status: 409, scenario: "snapshot write conflict", outcome: .publisherConflict),
        Row(status: 409, scenario: "reader registration at cap", outcome: .readerCapReached),
        Row(
            status: 409, scenario: "manual request already completed",
            outcome: .requestAlreadyCompleted),
        Row(status: 413, scenario: "payload over 64 KiB", outcome: .payloadTooLarge),
        Row(status: 422, scenario: "unsupported mandatory version", outcome: .unsupportedVersion),
        Row(status: 429, scenario: "manual request rate limit", outcome: .requestRateLimited),
        Row(status: 429, scenario: "free-tier daily limit", outcome: .quotaLimited),
        Row(status: 503, scenario: "Worker or Durable Object failure", outcome: .offline),
        Row(status: 0, scenario: "network or TLS failure", outcome: .offline),
    ]
}
