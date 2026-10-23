import ResetRadarDomain

/// Why a pairing package was rejected by the codec. Carries no package field.
public enum PairingCodecError: Error, Equatable, Sendable {
    case malformed
    case unsupportedVersion
    case expired
    case implausibleDeadline
    case invalidKeyLength
    case invalidTokenLength
    case endpointNotAllowed
    case invalidIdentifier
}

public enum PairingError: Error, Equatable, Sendable {
    case codec(PairingCodecError)
    case confirmationRequired
    /// A pairing already exists: `ForgetMac` must run first.
    case forgetRequired
    /// A previous Forget Mac has not finished its cleanup.
    case cleanupPending
    case secretsUnavailable
    /// The Keychain write or the local commit failed; staged secrets were removed.
    case storageFailed
    /// The preflight read failed; nothing was committed.
    case preflightFailed(TransportStatus)
    /// `resumeActivation` found no pending pairing.
    case nothingToResume
}
