import Foundation

public enum ManualRefreshTarget: Hashable, Sendable {
    case account(AccountID)
    case allCodex
}

extension ManualRefreshTarget: Codable {
    private enum CodingKeys: String, CodingKey {
        case accountID
        case target
    }

    private enum Kind: String, Codable {
        case account
        case allCodex
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .target)
        switch kind {
        case .account:
            self = .account(try container.decode(AccountID.self, forKey: .accountID))
        case .allCodex:
            guard !container.contains(.accountID) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .accountID, in: container,
                    debugDescription: "allCodex cannot carry an account ID")
            }
            self = .allCodex
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .account(let accountID):
            try container.encode(Kind.account, forKey: .target)
            try container.encode(accountID, forKey: .accountID)
        case .allCodex:
            try container.encode(Kind.allCodex, forKey: .target)
        }
    }
}

public struct ManualRefreshAccountResult: Codable, Hashable, Sendable {
    public enum Outcome: String, Codable, CaseIterable, Hashable, Sendable {
        case codexRead
        case sourceUnavailable
        case accountUnavailable
    }

    public let accountID: AccountID
    public let outcome: Outcome

    public init(accountID: AccountID, outcome: Outcome) {
        self.accountID = accountID
        self.outcome = outcome
    }
}

public enum ManualRefreshResultError: Error, Equatable, Sendable {
    case tooManyOutcomes
    case duplicateAccount
    case targetMismatch
}

public struct ManualRefreshResult: Codable, Hashable, Sendable {
    public static let maximumAccountOutcomes = 2

    public let readerID: ReaderID
    public let requestID: RequestID
    public let completedAt: Date
    public let target: ManualRefreshTarget
    public let accountResults: [ManualRefreshAccountResult]

    private enum CodingKeys: String, CodingKey {
        case readerID
        case requestID
        case completedAt
        case target
        case accountResults
    }

    public init(
        readerID: ReaderID, requestID: RequestID, completedAt: Date,
        target: ManualRefreshTarget, accountResults: [ManualRefreshAccountResult]
    ) throws(ManualRefreshResultError) {
        guard accountResults.count <= Self.maximumAccountOutcomes else { throw .tooManyOutcomes }
        guard Set(accountResults.map(\.accountID)).count == accountResults.count else {
            throw .duplicateAccount
        }
        if case .account(let accountID) = target {
            guard accountResults.count == 1, accountResults.first?.accountID == accountID else {
                throw .targetMismatch
            }
        }
        self.readerID = readerID
        self.requestID = requestID
        self.completedAt = completedAt
        self.target = target
        self.accountResults = accountResults
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                readerID: container.decode(ReaderID.self, forKey: .readerID),
                requestID: container.decode(RequestID.self, forKey: .requestID),
                completedAt: container.decode(Date.self, forKey: .completedAt),
                target: container.decode(ManualRefreshTarget.self, forKey: .target),
                accountResults: container.decode(
                    [ManualRefreshAccountResult].self, forKey: .accountResults))
        } catch let error as ManualRefreshResultError {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid manual refresh result: \(error)"))
        }
    }
}

public enum ManualRefreshResults {
    public static let retention: TimeInterval = 120
    public static let clockSkewTolerance: TimeInterval = 300
    public static let perReaderLimit = 4
    public static let totalLimit = 12

    public static func retained(
        _ results: [ManualRefreshResult], now: Date
    ) -> [ManualRefreshResult] {
        let live = results.enumerated().filter { _, result in
            let age = now.timeIntervalSince(result.completedAt)
            return age <= retention && -age <= clockSkewTolerance
        }
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

    public static func result(
        for readerID: ReaderID, requestID: RequestID, target: ManualRefreshTarget,
        in results: [ManualRefreshResult], now: Date
    ) -> ManualRefreshResult? {
        retained(results, now: now).first {
            $0.readerID == readerID && $0.requestID == requestID && $0.target == target
        }
    }
}
