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

public struct AccountSource: Codable, Hashable, Sendable {
    public let accountID: AccountID
    public let product: ProductID
    public let kind: SourceKind
    public let version: String
    public let state: SourceState
    public let providerScope: AccountScope?

    public init(
        accountID: AccountID, product: ProductID, kind: SourceKind, version: String,
        state: SourceState, providerScope: AccountScope? = nil
    ) {
        self.accountID = accountID
        self.product = product
        self.kind = kind
        self.version = version
        self.state = state
        self.providerScope = providerScope
    }
}
