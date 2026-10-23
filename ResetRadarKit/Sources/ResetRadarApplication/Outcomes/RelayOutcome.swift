import Foundation

/// The typed result of one relay call. Never an HTTP status code: `RelayGateway` adapters map the
/// status table in the relay protocol onto these cases, and use cases never see a code.
public enum RelayOutcome: Sendable, Equatable {
    /// 200 on a snapshot read: the opaque envelope bytes and the strong ETag.
    case snapshot(Data, etag: String, sequence: UInt64)
    /// 304.
    case notModified
    /// Authenticated 404 on a snapshot read. Any other 404 is `protocolFailure`.
    case awaitingFirstPublish
    /// 400.
    case badRequest
    /// 200 on a write, an idempotent activation, or a registration.
    case accepted(sequence: UInt64?)
    /// 202 with the relay-assigned expiry.
    case refreshAccepted(expiresAt: Date)
    /// 204.
    case deleted
    /// 401.
    case unauthorized
    /// 409 on a snapshot write.
    case publisherConflict
    /// 409 on reader registration: three readers are already registered.
    case readerCapReached
    /// 409 on a manual request: the last completed ID was repeated.
    case requestAlreadyCompleted
    /// 413.
    case payloadTooLarge
    /// 422.
    case unsupportedVersion
    /// 429 on a manual request.
    case requestRateLimited
    /// A platform quota response or the free-tier 429.
    case quotaLimited
    /// Another 3xx, an unknown route, or a malformed or oversized response.
    case protocolFailure
    /// No usable response.
    case offline
}

/// The case of a `RelayOutcome` without its payload, for tables and coverage checks. The raw
/// value is the case name, so every `RelayOutcome` case needs a matching kind.
public enum RelayOutcomeKind: String, Sendable, CaseIterable {
    case snapshot, notModified, awaitingFirstPublish, badRequest, accepted, refreshAccepted
    case deleted, unauthorized, publisherConflict, readerCapReached, requestAlreadyCompleted
    case payloadTooLarge, unsupportedVersion, requestRateLimited, quotaLimited, protocolFailure
    case offline

    public init(of outcome: RelayOutcome) {
        let name = String(String(describing: outcome).prefix { $0 != "(" })
        guard let kind = Self(rawValue: name) else {
            preconditionFailure("RelayOutcome case \(name) has no RelayOutcomeKind")
        }
        self = kind
    }
}
