import Foundation
import ResetRadarDomain

public enum RelayLifecycle: String, Codable, Sendable, Equatable {
    case notConfigured
    case setupPending
    case active
    case destroyPending
}

public struct PairedDevice: Codable, Sendable, Equatable {
    public let readerID: ReaderID
    public var name: String
    public var pairedAt: Date
    public var relayActivatedAt: Date?
    public var profileUnavailable: Bool?
    public var deviceClass: ReaderDeviceClass?

    public init(
        readerID: ReaderID, name: String, pairedAt: Date, relayActivatedAt: Date? = nil,
        profileUnavailable: Bool? = nil, deviceClass: ReaderDeviceClass? = nil
    ) {
        self.readerID = readerID
        self.name = name
        self.pairedAt = pairedAt
        self.relayActivatedAt = relayActivatedAt
        self.profileUnavailable = profileUnavailable
        self.deviceClass = deviceClass
    }
}

public struct PendingRegistration: Codable, Sendable, Equatable {
    public let readerID: ReaderID
    public var name: String
    /// The relay-assigned deadline.
    public var expiresAt: Date

    public init(readerID: ReaderID, name: String, expiresAt: Date) {
        self.readerID = readerID
        self.name = name
        self.expiresAt = expiresAt
    }
}

/// The Mac's relay metadata. Secrets never appear here.
public struct PublisherState: Codable, Sendable, Equatable {
    public var lifecycle: RelayLifecycle = .notConfigured
    public var endpoint: URL?
    public var publisherID: PublisherID?
    public var sequence: UInt64 = 0
    /// The highest sequence the relay accepted: the pairing floor for new readers.
    public var lastPublishedSequence: UInt64 = 0
    public var devices: [PairedDevice] = []
    public var pendingRegistrations: [PendingRegistration] = []
    /// Handled manual-refresh IDs and when to forget them.
    public var handledRequests: [RequestID: Date] = [:]
    public init() {}
}
