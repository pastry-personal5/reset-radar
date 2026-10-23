import ResetRadarDomain

/// Facts about the outcome that the outcome alone does not carry.
public struct MappingContext: Sendable, Equatable {
    /// True once an opened snapshot passed header, pairing-floor, and snapshot validation.
    public let snapshotValidated: Bool

    public init(snapshotValidated: Bool) {
        self.snapshotValidated = snapshotValidated
    }
}

/// Maps a relay outcome onto the device-local transport status. `nil` is a stated no-op: the
/// outcome is reported by its use case and does not change the transport status.
public enum TransportStatusMapping {
    public static func status(
        for outcome: RelayOutcome, context: MappingContext
    ) -> TransportStatus? {
        switch outcome {
        case .snapshot: context.snapshotValidated ? .current : .invalidSnapshot
        case .notModified: .current
        case .awaitingFirstPublish: .awaitingFirstPublish
        case .badRequest, .protocolFailure: .invalidSnapshot
        case .unauthorized: .authorizationRequired
        case .payloadTooLarge, .unsupportedVersion: .incompatible
        case .quotaLimited: .quotaLimited
        case .offline: .offline
        case .accepted, .refreshAccepted, .deleted, .publisherConflict, .readerCapReached,
            .requestAlreadyCompleted, .requestRateLimited:
            nil
        }
    }
}
