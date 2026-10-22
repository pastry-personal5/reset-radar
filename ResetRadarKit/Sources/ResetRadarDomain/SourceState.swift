import Foundation

/// Written by the Mac for each product.
public enum SourceState: String, Codable, CaseIterable, Hashable, Sendable {
    case reporting
    case unavailable
    case signedOut
    case sourceOffline
    case incompatible
}

/// Device-local transport status.
public enum TransportStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case notPaired
    case awaitingFirstPublish
    case current
    case offline
    case authorizationRequired
    case quotaLimited
    case invalidSnapshot
    case incompatible
    case secretsUnavailable
}

public struct ProductSource: Codable, Hashable, Sendable {
    public let product: ProductID
    public let kind: SourceKind
    public let version: String
    public let state: SourceState

    public init(product: ProductID, kind: SourceKind, version: String, state: SourceState) {
        self.product = product
        self.kind = kind
        self.version = version
        self.state = state
    }
}
