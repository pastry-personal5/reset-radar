import Foundation

public struct ManualRefreshResult: Codable, Hashable, Sendable {
    public enum Outcome: String, Codable, CaseIterable, Hashable, Sendable {
        case codexRead
        case sourceUnavailable
    }

    public let readerID: ReaderID
    public let requestID: RequestID
    public let completedAt: Date
    public let outcome: Outcome

    public init(readerID: ReaderID, requestID: RequestID, completedAt: Date, outcome: Outcome) {
        self.readerID = readerID
        self.requestID = requestID
        self.completedAt = completedAt
        self.outcome = outcome
    }
}

public enum ManualRefreshResults {
    /// A result stays readable for two minutes after the Mac completes the request.
    public static let retention: TimeInterval = 120
    /// Largest `completedAt` lead over `now` still accepted, matching the observation skew rule.
    public static let clockSkewTolerance: TimeInterval = 300
    public static let perReaderLimit = 4
    public static let totalLimit = 12

    /// Drops expired and implausibly future results, then applies the per-reader and total caps,
    /// dropping the oldest first. Survivors keep their input order.
    public static func retained(
        _ results: [ManualRefreshResult], now: Date
    ) -> [ManualRefreshResult] {
        let live = results.enumerated().filter { _, result in
            let age = now.timeIntervalSince(result.completedAt)
            return age <= retention && -age <= clockSkewTolerance
        }
        // Newest first; the later array position wins a tie.
        let newestFirst = live.sorted {
            ($0.element.completedAt, $0.offset) > ($1.element.completedAt, $1.offset)
        }
        var perReader: [ReaderID: Int] = [:]
        var kept: [(offset: Int, element: ManualRefreshResult)] = []
        for entry in newestFirst where kept.count < totalLimit {
            let count = perReader[entry.element.readerID, default: 0]
            guard count < perReaderLimit else { continue }
            perReader[entry.element.readerID] = count + 1
            kept.append(entry)
        }
        return kept.sorted { $0.offset < $1.offset }.map(\.element)
    }

    /// The retained result answering `requestID`, only for the reader that asked.
    public static func result(
        for readerID: ReaderID, requestID: RequestID, in results: [ManualRefreshResult], now: Date
    ) -> ManualRefreshResult? {
        retained(results, now: now).first {
            $0.readerID == readerID && $0.requestID == requestID
        }
    }
}
