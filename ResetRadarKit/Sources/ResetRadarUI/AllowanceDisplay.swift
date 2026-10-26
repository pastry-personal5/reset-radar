import Foundation
import ResetRadarApplication
import ResetRadarDomain

/// One window's presentation: a value only where its state allows one, plus the text, symbol,
/// and explanation that every state carries so color never carries it alone.
public struct AllowanceDisplay: Equatable, Sendable {
    public let state: PresentationState
    /// Percentage Used, 0 through 100. `nil` for unavailable and waiting windows, never 0.
    public let usedPercent: Double?
    public let fractionDigits: Int?

    public init(state: PresentationState, window: AllowanceWindow?) {
        self.state = state
        switch state {
        case .current, .stale:
            usedPercent = window?.observation?.usedPercent
            fractionDigits = window?.observation?.fractionDigits
        case .resetAwaitingRefresh, .unavailable:
            usedPercent = nil
            fractionDigits = nil
        }
    }

    public init(ring: AccountRingSummary) {
        if case .window(let window) = ring.resolution {
            self.init(state: ring.presentation, window: window)
        } else {
            self.init(state: .unavailable, window: nil)
        }
    }

    public init(details: WindowDetails) {
        self.init(state: details.presentation, window: details.window)
    }

    /// The ring's fill from 0 toward 1.
    public var fill: Double? {
        usedPercent.map { min(max($0 / 100, 0), 1) }
    }

    /// The source-precision percentage, for example `42%` or `42.5%`.
    public var percentText: String? {
        guard let usedPercent else { return nil }
        let value =
            if let fractionDigits {
                usedPercent.formatted(.number.precision(.fractionLength(fractionDigits)))
            } else {
                usedPercent.formatted(.number.precision(.fractionLength(0...2)))
            }
        return "\(value)%"
    }

    public var statusText: String {
        switch state {
        case .current: "Current"
        case .stale: "Stale"
        case .resetAwaitingRefresh: "Waiting for Update"
        case .unavailable: "Unavailable"
        }
    }

    public var symbolName: String {
        switch state {
        case .current: "checkmark.circle"
        case .stale: "exclamationmark.circle.fill"
        case .resetAwaitingRefresh: "clock"
        case .unavailable: "questionmark.circle"
        }
    }

    /// Why the reading is not current, or `nil` when it is.
    public func explanation(source: AccountSource?) -> String? {
        switch state {
        case .current:
            return nil
        case .stale(let reason):
            return Self.staleExplanation(reason, source: source)
        case .resetAwaitingRefresh:
            return "The reset time passed. Waiting for a new reading to confirm the next window."
        case .unavailable:
            if let source, source.state != .reporting {
                return "No reading is available. " + Self.sourceExplanation(source)
            }
            return "No reading is available for this window."
        }
    }

    /// The complete spoken description of one ring.
    public func accessibilityLabel(account: AccountMetadata, window: String) -> String {
        let product = ReaderVocabulary.productName(account.product)
        let reading = percentText.map { "\($0) used" } ?? "No percentage available"
        return "\(account.effectiveDisplayLabel), \(product), \(window), \(reading), \(statusText)"
    }

    private static func staleExplanation(_ reason: StaleReason, source: AccountSource?) -> String {
        switch reason {
        case .sourceNotReporting:
            let detail = source.map(sourceExplanation) ?? "The source is not reporting."
            return "\(detail) This is the last valid reading."
        case .retained:
            return "The source did not report this window in its latest reading."
        case .observationOld:
            return "This reading is older than its freshness window."
        case .observationInFuture:
            return "This reading’s time is ahead of this device’s clock."
        }
    }

    private static func sourceExplanation(_ source: AccountSource) -> String {
        let product = ReaderVocabulary.productName(source.product)
        return switch source.state {
        case .reporting: "\(product) is reporting."
        case .signedOut: "\(product) is signed out on the Collector Mac."
        case .sourceOffline: "\(product) is offline on the Collector Mac."
        case .incompatible: "The \(ReaderVocabulary.sourceName(source.kind)) is incompatible."
        case .unavailable: "\(product) is unavailable on the Collector Mac."
        }
    }
}
