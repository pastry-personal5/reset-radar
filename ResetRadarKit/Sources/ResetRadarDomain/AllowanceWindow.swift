import Foundation

public enum ReportState: String, TolerantEnum, CaseIterable, Hashable {
    case reported
    case retained
    case unknown
}

/// Provider limit state, kept separate from the percentage.
public enum ProviderLimitState: String, TolerantEnum, CaseIterable, Hashable {
    case reached
    case ordinaryUsageAllowed
    case unknown
}

public enum WindowValidationError: Error, Equatable, Sendable {
    case invalidPercentage
    case invalidTimestamp
    case invalidDuration
    case invalidPrecision
    case invalidIdentifier
    case invalidReportState
    case unknownProduct

    public var category: DiagnosticEvent.Category {
        switch self {
        case .invalidPercentage: .invalidPercentage
        case .invalidTimestamp: .invalidTimestamp
        case .invalidDuration: .invalidDuration
        case .invalidPrecision: .invalidPrecision
        case .invalidIdentifier: .invalidIdentifier
        case .invalidReportState: .invalidReportState
        case .unknownProduct: .unknownProduct
        }
    }
}

/// The latest timestamped provider reading. `usedPercent` is provider-reported percentage used.
public struct UsageObservation: Hashable, Sendable {
    public let usedPercent: Double
    public let observedAt: Date
    public let sourceVersion: String
    /// 0 for Codex integers, 1 for Claude Code; nil when unreported.
    public let fractionDigits: Int?

    public init(
        validating usedPercent: Double, observedAt: Date, sourceVersion: String,
        fractionDigits: Int? = nil
    ) throws(WindowValidationError) {
        guard usedPercent.isFinite, (0...100).contains(usedPercent) else {
            throw .invalidPercentage
        }
        guard observedAt.timeIntervalSinceReferenceDate.isFinite else { throw .invalidTimestamp }
        if let fractionDigits, !(0...1).contains(fractionDigits) { throw .invalidPrecision }
        // Adding zero turns -0.0 into +0.0.
        self.usedPercent = usedPercent + 0
        self.observedAt = observedAt
        self.sourceVersion = sourceVersion
        self.fractionDigits = fractionDigits
    }
}

/// The unvalidated wire shape of an observation.
public struct RawObservation: Codable, Equatable, Sendable {
    public var usedPercent: Double
    public var observedAt: Date
    public var sourceVersion: String
    public var fractionDigits: Int?

    public init(
        usedPercent: Double, observedAt: Date, sourceVersion: String, fractionDigits: Int? = nil
    ) {
        self.usedPercent = usedPercent
        self.observedAt = observedAt
        self.sourceVersion = sourceVersion
        self.fractionDigits = fractionDigits
    }
}

/// The unvalidated wire shape of a window, as decoded from a snapshot or built by an adapter.
public struct RawWindow: Codable, Equatable, Sendable {
    public var product: String
    public var accountScope: String?
    public var limitID: String
    public var label: String?
    public var durationMinutes: Int?
    public var isDefaultLimit: Bool
    public var reportState: ReportState
    public var resetsAt: Date?
    public var observation: RawObservation?
    public var providerLimitState: ProviderLimitState?

    public init(
        product: String, accountScope: String? = nil, limitID: String, label: String? = nil,
        durationMinutes: Int? = nil, isDefaultLimit: Bool, reportState: ReportState,
        resetsAt: Date? = nil, observation: RawObservation? = nil,
        providerLimitState: ProviderLimitState? = nil
    ) {
        self.product = product
        self.accountScope = accountScope
        self.limitID = limitID
        self.label = label
        self.durationMinutes = durationMinutes
        self.isDefaultLimit = isDefaultLimit
        self.reportState = reportState
        self.resetsAt = resetsAt
        self.observation = observation
        self.providerLimitState = providerLimitState
    }
}

public struct AllowanceWindow: Codable, Hashable, Sendable {
    public let product: ProductID
    public let scope: AccountScope?
    public let limitID: String
    public let label: String?
    public let durationMinutes: Int?
    public let isDefaultLimit: Bool
    public let reportState: ReportState
    public let resetsAt: Date?
    public let observation: UsageObservation?
    public let providerLimitState: ProviderLimitState?

    public var id: WindowID {
        WindowID(
            product: product, scope: scope, limitID: limitID, durationMinutes: durationMinutes)
    }

    public init(validating raw: RawWindow) throws(WindowValidationError) {
        guard let product = ProductID(rawValue: raw.product) else { throw .unknownProduct }
        guard !raw.limitID.isEmpty else { throw .invalidIdentifier }
        var scope: AccountScope?
        if let text = raw.accountScope {
            guard let parsed = AccountScope(hex: text) else { throw .invalidIdentifier }
            scope = parsed
        }
        if let minutes = raw.durationMinutes, minutes <= 0 { throw .invalidDuration }
        guard raw.reportState != .unknown else { throw .invalidReportState }
        if let resetsAt = raw.resetsAt, !resetsAt.timeIntervalSinceReferenceDate.isFinite {
            throw .invalidTimestamp
        }
        var observation: UsageObservation?
        if let rawObservation = raw.observation {
            observation = try UsageObservation(
                validating: rawObservation.usedPercent, observedAt: rawObservation.observedAt,
                sourceVersion: rawObservation.sourceVersion,
                fractionDigits: rawObservation.fractionDigits)
        }
        self.product = product
        self.scope = scope
        self.limitID = raw.limitID
        self.label = raw.label
        self.durationMinutes = raw.durationMinutes
        self.isDefaultLimit = raw.isDefaultLimit
        self.reportState = raw.reportState
        self.resetsAt = raw.resetsAt
        self.observation = observation
        self.providerLimitState = raw.providerLimitState
    }

    var raw: RawWindow {
        RawWindow(
            product: product.rawValue, accountScope: scope?.hex, limitID: limitID, label: label,
            durationMinutes: durationMinutes, isDefaultLimit: isDefaultLimit,
            reportState: reportState, resetsAt: resetsAt,
            observation: observation.map {
                RawObservation(
                    usedPercent: $0.usedPercent, observedAt: $0.observedAt,
                    sourceVersion: $0.sourceVersion, fractionDigits: $0.fractionDigits)
            },
            providerLimitState: providerLimitState)
    }

    public init(from decoder: any Decoder) throws {
        let raw = try RawWindow(from: decoder)
        do {
            try self.init(validating: raw)
        } catch {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid window: \(error.category.rawValue)"))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        try raw.encode(to: encoder)
    }
}

extension UsageObservation: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try RawObservation(from: decoder)
        do {
            try self.init(
                validating: raw.usedPercent, observedAt: raw.observedAt,
                sourceVersion: raw.sourceVersion, fractionDigits: raw.fractionDigits)
        } catch {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid observation: \(error.category.rawValue)"))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        try RawObservation(
            usedPercent: usedPercent, observedAt: observedAt, sourceVersion: sourceVersion,
            fractionDigits: fractionDigits
        ).encode(to: encoder)
    }
}
