import Foundation

public enum ProviderFailureClass: String, TolerantEnum, CaseIterable, Hashable {
    case notInstalled
    case signedOut
    case incompatible
    case timeout
    case processExited
    case malformed
    case permissionDenied
    case accountScope
    case duplicateProviderScope
    case temporarilyUnavailable
    case unknown
}

/// A redacted compatibility or validation event.
///
/// Redaction holds by construction: no stored property, initializer, or factory parameter is a
/// `String`, so provider values, paths, tokens, and error text cannot enter an event.
public struct DiagnosticEvent: Codable, Hashable, Sendable {
    public enum Category: String, TolerantEnum, CaseIterable {
        case invalidPercentage
        case invalidTimestamp
        case invalidDuration
        case invalidPrecision
        case invalidIdentifier
        case invalidReportState
        case unknownProduct
        case duplicateWindow
        case ambiguousAccountWindow
        case invalidHeartbeat
        case unsupportedSchema
        case publicationStopped
        case envelopeTooLarge
        case secretsUnavailable
        case relayFailure
        case providerFailure
        case unknown
    }

    public let category: Category
    public let timestamp: Date
    public let product: ProductID?
    public let accountID: AccountID?
    public let sourceState: SourceState?
    public let transportStatus: TransportStatus?
    public let durationSeconds: Double?
    public let firstSequence: UInt64?
    public let lastSequence: UInt64?
    public let schemaVersion: Int?
    public let supportedSchemaVersion: Int?
    public let httpStatusClass: Int?
    public let providerFailureClass: ProviderFailureClass?

    private init(
        _ category: Category, at timestamp: Date, product: ProductID? = nil,
        accountID: AccountID? = nil, transportStatus: TransportStatus? = nil,
        lastSequence: UInt64? = nil, schemaVersion: Int? = nil,
        supportedSchemaVersion: Int? = nil, httpStatusClass: Int? = nil,
        providerFailureClass: ProviderFailureClass? = nil
    ) {
        self.category = category
        self.timestamp = timestamp
        self.product = product
        self.accountID = accountID
        self.sourceState = nil
        self.transportStatus = transportStatus
        self.durationSeconds = nil
        self.firstSequence = nil
        self.lastSequence = lastSequence
        self.schemaVersion = schemaVersion
        self.supportedSchemaVersion = supportedSchemaVersion
        self.httpStatusClass = httpStatusClass
        self.providerFailureClass = providerFailureClass
    }

    /// A window failed per-window validation for the reason carried by `category`.
    public static func invalidWindow(
        _ category: Category, product: ProductID?, at timestamp: Date
    ) -> DiagnosticEvent {
        DiagnosticEvent(category, at: timestamp, product: product)
    }

    public static func unknownProduct(at timestamp: Date) -> DiagnosticEvent {
        DiagnosticEvent(.unknownProduct, at: timestamp)
    }

    public static func duplicateWindow(
        accountID: AccountID, product: ProductID, at timestamp: Date
    ) -> DiagnosticEvent {
        DiagnosticEvent(.duplicateWindow, at: timestamp, product: product, accountID: accountID)
    }

    public static func ambiguousAccountWindow(
        _ window: AccountWindow, product: ProductID, at timestamp: Date
    ) -> DiagnosticEvent {
        DiagnosticEvent(
            .ambiguousAccountWindow, at: timestamp, product: product,
            accountID: window.accountID)
    }

    public static func invalidHeartbeat(at timestamp: Date) -> DiagnosticEvent {
        DiagnosticEvent(.invalidHeartbeat, at: timestamp)
    }

    public static func unsupportedSchema(
        found: Int, supported: ClosedRange<Int>, at timestamp: Date
    ) -> DiagnosticEvent {
        DiagnosticEvent(
            .unsupportedSchema, at: timestamp, schemaVersion: found,
            supportedSchemaVersion: supported.upperBound)
    }

    /// Automatic publication stopped; `status` is the relay's HTTP status class (4 or 5), if any.
    public static func publicationStopped(
        httpStatusClass: Int?, lastSequence: UInt64?, at timestamp: Date
    ) -> DiagnosticEvent {
        DiagnosticEvent(
            .publicationStopped, at: timestamp, lastSequence: lastSequence,
            httpStatusClass: httpStatusClass)
    }

    /// The sealed envelope exceeded the relay request limit and was not sent.
    public static func envelopeTooLarge(sequence: UInt64, at timestamp: Date) -> DiagnosticEvent {
        DiagnosticEvent(.envelopeTooLarge, at: timestamp, lastSequence: sequence)
    }

    public static func secretsUnavailable(at timestamp: Date) -> DiagnosticEvent {
        DiagnosticEvent(.secretsUnavailable, at: timestamp, transportStatus: .secretsUnavailable)
    }

    /// A relay call failed in a way that changes the transport status.
    public static func relayFailure(
        status: TransportStatus, httpStatusClass: Int?, at timestamp: Date
    ) -> DiagnosticEvent {
        DiagnosticEvent(
            .relayFailure, at: timestamp, transportStatus: status, httpStatusClass: httpStatusClass)
    }

    public static func providerFailure(
        _ failure: ProviderFailureClass, accountID: AccountID, product: ProductID,
        at timestamp: Date
    ) -> DiagnosticEvent {
        DiagnosticEvent(
            .providerFailure, at: timestamp, product: product, accountID: accountID,
            providerFailureClass: failure)
    }
}
