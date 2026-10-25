import Foundation
import ResetRadarApplication
import ResetRadarDomain

public enum CodexAccountStatus: Equatable, Sendable {
    case authenticated
    case signedOut
    case incompatible
}

public enum CodexRateLimitError: Error, Equatable, Sendable {
    case incompatibleResponse
    case missingAccountIdentifier
    case tooManyBuckets
    case tooManyCandidateWindows
    case ambiguousDefaultBucket
    case duplicateWindow
    case noValidWindows
    case accountScopeFailure
}

public struct CodexDecodedWindow: Equatable, Sendable {
    public let usedPercent: Int
    public let durationMinutes: Int?
    public let resetsAtUnixSeconds: Int64?
}

public enum CodexWindowCandidate: Equatable, Sendable {
    case valid(CodexDecodedWindow)
    case rejected(WindowValidationError)
}

public struct CodexDecodedBucket: Equatable, Sendable {
    public let embeddedLimitID: String?
    public let label: String?
    public let reached: Bool
    public let reachedUnrecognized: Bool
    public let primary: CodexWindowCandidate?
    public let secondary: CodexWindowCandidate?

    func matchesWithoutIdentity(_ other: CodexDecodedBucket) -> Bool {
        label == other.label && reached == other.reached
            && reachedUnrecognized == other.reachedUnrecognized && primary == other.primary
            && secondary == other.secondary
    }
}

public struct CodexDecodedRateLimits: Equatable, Sendable {
    public let accountScope: AccountScope
    public let ordinaryUsageAllowed: Bool?
    public let compatibility: CodexDecodedBucket
    public let buckets: [String: CodexDecodedBucket]?
}

public enum RateLimitDecoder {
    public static let maximumBuckets = 128
    public static let maximumCandidateWindows = 128

    public static func decodeAccountStatus(_ value: JSONValue) -> CodexAccountStatus {
        guard case .object(let object) = value,
            case .boolean(let requiresOpenAIAuth) = object["requiresOpenaiAuth"],
            let account = object["account"]
        else { return .incompatible }
        switch (account, requiresOpenAIAuth) {
        case (.null, true):
            return .signedOut
        case (.object(let account), _):
            return account["type"] == .string("chatgpt") ? .authenticated : .incompatible
        default:
            return .incompatible
        }
    }

    public static func decodeRateLimits(
        _ value: JSONValue, scoper: any AccountScoper
    ) async throws(CodexRateLimitError) -> CodexDecodedRateLimits {
        guard case .object(let object) = value else { throw .incompatibleResponse }
        guard case .string(let accountIdentifier) = object["accountId"],
            !accountIdentifier.isEmpty
        else { throw .missingAccountIdentifier }
        guard case .object(let compatibilityObject) = object["rateLimits"] else {
            throw .incompatibleResponse
        }
        let ordinaryUsageAllowed = try optionalBoolean(object["ordinaryUsageAllowed"])
        let mapObjects = try decodeMap(object["rateLimitsByLimitId"])
        try validateCandidateCount(compatibility: compatibilityObject, map: mapObjects)
        let compatibility = try decodeBucket(compatibilityObject)
        let buckets = try mapObjects.map(decodeBuckets)
        let accountScope: AccountScope
        do {
            accountScope = try await scoper.scope(forAccountIdentifier: accountIdentifier)
        } catch {
            throw .accountScopeFailure
        }
        return CodexDecodedRateLimits(
            accountScope: accountScope,
            ordinaryUsageAllowed: ordinaryUsageAllowed,
            compatibility: compatibility,
            buckets: buckets)
    }

    private static func decodeBucket(
        _ object: [String: JSONValue]
    ) throws(CodexRateLimitError) -> CodexDecodedBucket {
        let embeddedLimitID = try optionalNonemptyString(object["limitId"])
        let label = try optionalString(object["limitName"])
        let reached: Bool
        var unrecognized = false
        switch object["rateLimitReachedType"] {
        case nil, .null?:
            reached = false
        case .string(let value)?:
            reached = Self.reachedValues.contains(value)
            unrecognized = !reached
        default:
            throw .incompatibleResponse
        }
        return CodexDecodedBucket(
            embeddedLimitID: embeddedLimitID, label: label, reached: reached,
            reachedUnrecognized: unrecognized,
            primary: try decodeCandidate(object["primary"]),
            secondary: try decodeCandidate(object["secondary"]))
    }

    private static func decodeCandidate(
        _ value: JSONValue?
    ) throws(CodexRateLimitError) -> CodexWindowCandidate? {
        switch value {
        case nil, .null?:
            return nil
        case .object(let object)?:
            guard case .success(let usedPercent) = decodePercentage(object["usedPercent"])
            else { return .rejected(.invalidPercentage) }
            guard case .success(let duration) = decodeDuration(object["windowDurationMins"])
            else { return .rejected(.invalidDuration) }
            guard case .success(let reset) = decodeReset(object["resetsAt"])
            else { return .rejected(.invalidTimestamp) }
            return .valid(
                CodexDecodedWindow(
                    usedPercent: Int(usedPercent), durationMinutes: duration,
                    resetsAtUnixSeconds: reset))
        default:
            throw .incompatibleResponse
        }
    }

    private static func decodeMap(
        _ value: JSONValue?
    ) throws(CodexRateLimitError) -> [String: JSONValue]? {
        switch value {
        case nil, .null?:
            return nil
        case .object(let values)?:
            guard values.count <= maximumBuckets else { throw .tooManyBuckets }
            return values
        default:
            throw .incompatibleResponse
        }
    }

    private static func validateCandidateCount(
        compatibility: [String: JSONValue], map: [String: JSONValue]?
    ) throws(CodexRateLimitError) {
        var count = countCandidates(in: compatibility)
        if let map {
            for value in map.values {
                guard case .object(let bucket) = value else { throw .incompatibleResponse }
                count += countCandidates(in: bucket)
            }
        }
        guard count <= maximumCandidateWindows else { throw .tooManyCandidateWindows }
    }

    private static func decodeBuckets(
        _ objects: [String: JSONValue]
    ) throws(CodexRateLimitError) -> [String: CodexDecodedBucket] {
        var decoded: [String: CodexDecodedBucket] = [:]
        for (key, value) in objects {
            guard !key.isEmpty, case .object(let object) = value else {
                throw .incompatibleResponse
            }
            let bucket = try decodeBucket(object)
            if let embedded = bucket.embeddedLimitID, embedded != key {
                throw .incompatibleResponse
            }
            decoded[key] = bucket
        }
        return decoded
    }

    private static func decodePercentage(
        _ value: JSONValue?
    ) -> Result<Int, WindowValidationError> {
        guard case .integer(let value) = value, (0...100).contains(value),
            let exact = Int(exactly: value)
        else { return .failure(.invalidPercentage) }
        return .success(exact)
    }

    private static func decodeDuration(
        _ value: JSONValue?
    ) -> Result<Int?, WindowValidationError> {
        switch value {
        case nil, .null?: return .success(nil)
        case .integer(let value)?:
            guard value > 0, let exact = Int(exactly: value) else {
                return .failure(.invalidDuration)
            }
            return .success(exact)
        default: return .failure(.invalidDuration)
        }
    }

    private static func decodeReset(
        _ value: JSONValue?
    ) -> Result<Int64?, WindowValidationError> {
        switch value {
        case nil, .null?: return .success(nil)
        case .integer(let value)?:
            guard value > 0, value <= JSONRPCIDSequence.maximum else {
                return .failure(.invalidTimestamp)
            }
            return .success(value)
        default: return .failure(.invalidTimestamp)
        }
    }

    private static func countCandidates(in object: [String: JSONValue]) -> Int {
        [object["primary"], object["secondary"]].reduce(into: 0) { count, value in
            if let value, value != .null { count += 1 }
        }
    }

    private static func optionalBoolean(
        _ value: JSONValue?
    ) throws(CodexRateLimitError) -> Bool? {
        switch value {
        case nil, .null?: nil
        case .boolean(let value)?: value
        default: throw .incompatibleResponse
        }
    }

    private static func optionalString(
        _ value: JSONValue?
    ) throws(CodexRateLimitError) -> String? {
        switch value {
        case nil, .null?: nil
        case .string(let value)?: value
        default: throw .incompatibleResponse
        }
    }

    private static func optionalNonemptyString(
        _ value: JSONValue?
    ) throws(CodexRateLimitError) -> String? {
        guard let value = try optionalString(value) else { return nil }
        guard !value.isEmpty else { throw .incompatibleResponse }
        return value
    }

    private static let reachedValues = Set([
        "rate_limit_reached",
        "workspace_owner_credits_depleted",
        "workspace_member_credits_depleted",
        "workspace_owner_usage_limit_reached",
        "workspace_member_usage_limit_reached",
    ])
}
