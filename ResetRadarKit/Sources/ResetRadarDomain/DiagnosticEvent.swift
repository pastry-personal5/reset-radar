import Foundation

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
        case ambiguousHomeSlot
        case invalidHeartbeat
        case unsupportedSchema
        case unknown
    }

    public let category: Category
    public let timestamp: Date
    public let product: ProductID?
    public let slot: HomeSlot?
    public let sourceState: SourceState?
    public let transportStatus: TransportStatus?
    public let durationSeconds: Double?
    public let firstSequence: UInt64?
    public let lastSequence: UInt64?
    public let schemaVersion: Int?
    public let supportedSchemaVersion: Int?
    public let httpStatusClass: Int?

    private init(
        _ category: Category, at timestamp: Date, product: ProductID? = nil, slot: HomeSlot? = nil,
        schemaVersion: Int? = nil, supportedSchemaVersion: Int? = nil
    ) {
        self.category = category
        self.timestamp = timestamp
        self.product = product
        self.slot = slot
        self.sourceState = nil
        self.transportStatus = nil
        self.durationSeconds = nil
        self.firstSequence = nil
        self.lastSequence = nil
        self.schemaVersion = schemaVersion
        self.supportedSchemaVersion = supportedSchemaVersion
        self.httpStatusClass = nil
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

    public static func duplicateWindow(product: ProductID, at timestamp: Date) -> DiagnosticEvent {
        DiagnosticEvent(.duplicateWindow, at: timestamp, product: product)
    }

    public static func ambiguousHomeSlot(_ slot: HomeSlot, at timestamp: Date) -> DiagnosticEvent {
        DiagnosticEvent(.ambiguousHomeSlot, at: timestamp, product: slot.product, slot: slot)
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
}
