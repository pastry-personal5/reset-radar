import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarProviderAdapters
import ResetRadarTestSupport
import Testing

private struct FailingAccountScoper: AccountScoper {
    func scope(forAccountIdentifier identifier: String) async throws -> AccountScope {
        throw CocoaError(.coderInvalidValue)
    }
}

@Suite("Codex rate-limit decoding and normalization")
struct CodexNormalizerTests {
    private let accountID = AccountID(data: Data(repeating: 0xA1, count: 16))!
    private let observedAt = Date(timeIntervalSince1970: 2_000_000_000)

    @Test("account status uses only the structured discriminator matrix")
    func accountStatusMatrix() {
        #expect(
            RateLimitDecoder.decodeAccountStatus(
                .object([
                    "account": .object(["type": .string("chatgpt")]),
                    "requiresOpenaiAuth": .boolean(false),
                ])) == .authenticated)
        #expect(
            RateLimitDecoder.decodeAccountStatus(
                .object([
                    "account": .object(["type": .string("chatgpt")]),
                    "requiresOpenaiAuth": .boolean(true),
                ])) == .authenticated)
        #expect(
            RateLimitDecoder.decodeAccountStatus(
                .object([
                    "account": .null, "requiresOpenaiAuth": .boolean(true),
                ])) == .signedOut)
        for incompatible: JSONValue in [
            .object(["account": .null, "requiresOpenaiAuth": .boolean(false)]),
            .object([
                "account": .object(["type": .string("apiKey")]),
                "requiresOpenaiAuth": .boolean(false),
            ]),
            .object([
                "account": .object(["type": .string("apiKey")]),
                "requiresOpenaiAuth": .boolean(true),
            ]),
            .object(["requiresOpenaiAuth": .boolean(true)]),
            .object(["account": .null, "requiresOpenaiAuth": .string("true")]),
        ] {
            #expect(RateLimitDecoder.decodeAccountStatus(incompatible) == .incompatible)
        }
    }

    @Test("compatibility-only response preserves integer usage and optional clock fields")
    func compatibilityOnly() async throws {
        let decoded = try await decode(
            response(
                compatibility: bucket(
                    id: "codex", label: "Codex", primary: window(used: 43, duration: 300),
                    secondary: window(used: 17, duration: nil, reset: nil)),
                ordinaryAllowed: true))
        let result = try await normalizer().normalize(decoded, observedAt: observedAt)

        #expect(result.snapshot.windows.count == 2)
        #expect(result.snapshot.windows.allSatisfy { $0.isDefaultLimit })
        #expect(result.snapshot.windows.allSatisfy { $0.observation?.fractionDigits == 0 })
        #expect(
            result.snapshot.windows.allSatisfy {
                $0.providerLimitState == .ordinaryUsageAllowed
            })
        let unknownClock = try #require(
            result.snapshot.windows.first(where: { $0.durationMinutes == nil }))
        #expect(unknownClock.resetsAt == nil)
    }

    @Test("a five-hour and weekly default pair resolves both standard rings with reported values")
    func fiveHourAndWeeklyResolve() async throws {
        let decoded = try await decode(
            response(
                compatibility: bucket(
                    id: "codex", label: "Codex",
                    primary: window(used: 43, duration: 300, reset: 2_000_000_300),
                    secondary: window(used: 17, duration: 10_080, reset: 2_000_604_800)),
                ordinaryAllowed: true))
        let snapshot = try await normalizer().normalize(decoded, observedAt: observedAt).snapshot

        for (standard, used, reset) in [
            (AccountWindow.StandardWindow.fiveHour, 43.0, 2_000_000_300.0),
            (.weekly, 17.0, 2_000_604_800.0),
        ] {
            let matches = snapshot.windows.filter {
                $0.isDefaultLimit && $0.durationMinutes == standard.durationMinutes
            }
            let window = try #require(matches.first)
            #expect(matches.count == 1)
            #expect(window.accountID == accountID)
            #expect(window.observation?.usedPercent == used)
            #expect(window.resetsAt == Date(timeIntervalSince1970: reset))
        }
    }

    @Test("multi-bucket identity match marks exactly one default and keeps same-duration limits")
    func multiBucketIdentity() async throws {
        let defaultBucket = bucket(
            id: "codex", label: "Default", primary: window(used: 10, duration: 300))
        let decoded = try await decode(
            response(
                compatibility: defaultBucket,
                buckets: [
                    "codex": defaultBucket,
                    "other": bucket(
                        id: "other", label: "Other", primary: window(used: 20, duration: 300)),
                ]))
        let result = try await normalizer().normalize(decoded, observedAt: observedAt)

        #expect(result.snapshot.windows.count == 2)
        #expect(result.snapshot.windows.filter(\.isDefaultLimit).map(\.limitID) == ["codex"])
        #expect(Set(result.snapshot.windows.map(\.id)).count == 2)
    }

    @Test("structural fallback requires one match and never overrides contradictory identity")
    func structuralFallback() async throws {
        let compatibility = bucket(primary: window(used: 10, duration: 300))
        let matching = bucket(id: "one", primary: window(used: 10, duration: 300))
        let decoded = try await decode(
            response(compatibility: compatibility, buckets: ["one": matching]))
        let result = try await normalizer().normalize(decoded, observedAt: observedAt)
        #expect(result.snapshot.windows.first?.isDefaultLimit == true)

        let ambiguous = try await decode(
            response(
                compatibility: compatibility,
                buckets: [
                    "one": matching,
                    "two": bucket(id: "two", primary: window(used: 10, duration: 300)),
                ]))
        await #expect(throws: CodexRateLimitError.ambiguousDefaultBucket) {
            try await normalizer().normalize(ambiguous, observedAt: observedAt)
        }

        let contradictory = try await decode(
            response(
                compatibility: bucket(id: "absent", primary: window(used: 10, duration: 300)),
                buckets: ["one": matching]))
        await #expect(throws: CodexRateLimitError.ambiguousDefaultBucket) {
            try await normalizer().normalize(contradictory, observedAt: observedAt)
        }
    }

    @Test("invalid sibling windows are diagnosed while a valid sibling survives")
    func invalidSibling() async throws {
        let decoded = try await decode(
            response(
                compatibility: bucket(
                    id: "codex", primary: window(used: 5, duration: 300),
                    secondary: .object(["usedPercent": .number(5.5)]))))
        let result = try await normalizer().normalize(decoded, observedAt: observedAt)
        #expect(result.snapshot.windows.count == 1)
        #expect(result.diagnostics.map(\.category) == [.invalidPercentage])
    }

    @Test("map identity disagreement and response bounds fail closed")
    func identityAndBounds() async {
        await #expect(throws: CodexRateLimitError.incompatibleResponse) {
            try await decode(
                response(
                    compatibility: bucket(id: "one", primary: window(used: 1, duration: 300)),
                    buckets: [
                        "one": bucket(id: "different", primary: window(used: 1, duration: 300))
                    ]))
        }
        var buckets: [String: JSONValue] = [:]
        for index in 0...RateLimitDecoder.maximumBuckets {
            buckets["limit-\(index)"] = bucket(
                id: "limit-\(index)", primary: window(used: 1, duration: 300))
        }
        await #expect(throws: CodexRateLimitError.tooManyBuckets) {
            try await decode(
                response(
                    compatibility: bucket(
                        id: "limit-0", primary: window(used: 1, duration: 300)),
                    buckets: buckets))
        }
    }

    @Test("candidate count includes compatibility and invalid candidates")
    func candidateBound() async {
        var buckets: [String: JSONValue] = [:]
        for index in 0..<64 {
            buckets["limit-\(index)"] = bucket(
                id: "limit-\(index)", primary: window(used: 1, duration: 300),
                secondary: .object(["usedPercent": .number(1.5)]))
        }
        await #expect(throws: CodexRateLimitError.tooManyCandidateWindows) {
            try await decode(
                response(
                    compatibility: bucket(
                        id: "limit-0", primary: window(used: 1, duration: 300)),
                    buckets: buckets))
        }
    }

    @Test("reached takes precedence and false permission remains explicit")
    func providerStatePrecedence() async throws {
        let reached = try await decode(
            response(
                compatibility: bucket(
                    id: "codex", reached: "rate_limit_reached",
                    primary: window(used: 20, duration: 300)),
                ordinaryAllowed: false))
        let reachedResult = try await normalizer().normalize(reached, observedAt: observedAt)
        #expect(reachedResult.snapshot.windows.first?.providerLimitState == .reached)

        let unrecognized = try await decode(
            response(
                compatibility: bucket(
                    id: "codex", reached: "a_future_reached_kind",
                    primary: window(used: 20, duration: 300)),
                ordinaryAllowed: true))
        let unrecognizedResult = try await normalizer().normalize(
            unrecognized, observedAt: observedAt)
        #expect(unrecognizedResult.snapshot.windows.first?.providerLimitState == .unknown)

        let disallowed = try await decode(
            response(
                compatibility: bucket(
                    id: "codex", primary: window(used: 20, duration: 300)),
                ordinaryAllowed: false))
        let disallowedResult = try await normalizer().normalize(
            disallowed, observedAt: observedAt)
        #expect(
            disallowedResult.snapshot.windows.first?.providerLimitState
                == .ordinaryUsageDisallowed)
    }

    @Test("duplicate constructed identities, empty results, and scoping failure fail closed")
    func normalizationFailures() async throws {
        let duplicate = try await decode(
            response(
                compatibility: bucket(
                    id: "codex", primary: window(used: 1, duration: 300),
                    secondary: window(used: 2, duration: 300))))
        await #expect(throws: CodexRateLimitError.duplicateWindow) {
            try await normalizer().normalize(duplicate, observedAt: observedAt)
        }
        let empty = try await decode(
            response(compatibility: bucket(id: "codex")))
        await #expect(throws: CodexRateLimitError.noValidWindows) {
            try await normalizer().normalize(empty, observedAt: observedAt)
        }
        await #expect(throws: CodexRateLimitError.accountScopeFailure) {
            try await RateLimitDecoder.decodeRateLimits(
                response(compatibility: bucket(id: "codex")),
                scoper: FailingAccountScoper())
        }
    }
}

extension CodexNormalizerTests {
    private func normalizer() -> CodexNormalizer {
        CodexNormalizer(accountID: accountID, sourceVersion: "codex 1.0.0")
    }

    private func decode(_ value: JSONValue) async throws -> CodexDecodedRateLimits {
        try await RateLimitDecoder.decodeRateLimits(value, scoper: FakeAccountScoper())
    }

    private func response(
        compatibility: JSONValue, buckets: [String: JSONValue]? = nil,
        ordinaryAllowed: Bool? = nil
    ) -> JSONValue {
        var object: [String: JSONValue] = [
            "accountId": .string("synthetic-account"), "rateLimits": compatibility,
        ]
        if let buckets { object["rateLimitsByLimitId"] = .object(buckets) }
        if let ordinaryAllowed { object["ordinaryUsageAllowed"] = .boolean(ordinaryAllowed) }
        return .object(object)
    }

    private func bucket(
        id: String? = nil, label: String? = nil, reached: String? = nil,
        primary: JSONValue? = nil, secondary: JSONValue? = nil
    ) -> JSONValue {
        var object: [String: JSONValue] = [:]
        if let id { object["limitId"] = .string(id) }
        if let label { object["limitName"] = .string(label) }
        if let reached { object["rateLimitReachedType"] = .string(reached) }
        if let primary { object["primary"] = primary }
        if let secondary { object["secondary"] = secondary }
        return .object(object)
    }

    private func window(
        used: Int64, duration: Int64?, reset: Int64? = 2_000_000_100
    ) -> JSONValue {
        var object: [String: JSONValue] = ["usedPercent": .integer(used)]
        object["windowDurationMins"] = duration.map(JSONValue.integer) ?? .null
        object["resetsAt"] = reset.map(JSONValue.integer) ?? .null
        return .object(object)
    }
}
