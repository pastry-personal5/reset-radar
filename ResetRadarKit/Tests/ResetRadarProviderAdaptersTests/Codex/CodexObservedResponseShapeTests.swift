import Foundation
import ResetRadarDomain
import ResetRadarProviderAdapters
import ResetRadarTestSupport
import Testing

@Suite("Codex observed response shape")
struct CodexObservedResponseShapeTests {
    @Test("the owner-selected app-server shape reaches a reporting snapshot")
    func observedShape() async throws {
        let frames = try responseFrames()
        #expect(frames.count == 2)
        let accountFrame = try #require(frames.first)
        let limitFrame = try #require(frames.dropFirst().first)
        guard
            case .response(id: 1, result: let account) = try JSONRPCMessageDecoder.decode(
                accountFrame)
        else {
            Issue.record("Expected an account response")
            return
        }
        #expect(RateLimitDecoder.decodeAccountStatus(account) == .authenticated)
        guard
            case .response(id: 2, result: let limits) = try JSONRPCMessageDecoder.decode(
                limitFrame)
        else {
            Issue.record("Expected a rate-limit response")
            return
        }
        let decoded = try await RateLimitDecoder.decodeRateLimits(
            limits, scoper: FakeAccountScoper())
        let accountID = try #require(AccountID(data: Data(repeating: 0xA1, count: 16)))
        let report = try await CodexNormalizer(accountID: accountID, sourceVersion: "codex 0.0.0")
            .normalize(decoded, observedAt: Date(timeIntervalSince1970: 2_000_000_000))
        #expect(report.snapshot.source.state == .reporting)
        #expect(report.snapshot.windows.count == 2)
        #expect(report.snapshot.windows.allSatisfy { $0.isDefaultLimit })
        #expect(report.diagnostics.isEmpty)
    }

    private func responseFrames() throws -> [Data] {
        let account = JSONValue.object([
            "account": .object([
                "email": .string("synthetic@example.invalid"),
                "planType": .string("synthetic"),
                "type": .string("chatgpt"),
            ]),
            "requiresOpenaiAuth": .boolean(true),
            "workspaceRouting": .null,
        ])
        let bucket = observedBucket()
        let limits = JSONValue.object([
            "accountId": .string("synthetic-account"),
            "ordinaryUsageAllowed": .boolean(true),
            "rateLimitResetCredits": .null,
            "rateLimitUpsell": .null,
            "rateLimits": bucket,
            "rateLimitsByLimitId": .object(["synthetic-default": bucket]),
        ])
        var framed = try frame(id: 1, result: account)
        framed.append(try frame(id: 2, result: limits))
        var reader = BoundedRPCFrame()
        let frames = try reader.consume(framed)
        try reader.finish()
        return frames
    }

    private func observedBucket() -> JSONValue {
        .object([
            "credits": .object([:]),
            "individualLimit": .null,
            "limitId": .string("synthetic-default"),
            "limitName": .string("Synthetic"),
            "normalModelSlug": .null,
            "planType": .string("synthetic"),
            "primary": window(used: 43, duration: 300, reset: 2_000_000_300),
            "rateLimitReachedType": .string("synthetic-state"),
            "secondary": window(used: 17, duration: 10_080, reset: 2_000_604_800),
            "spendControlReached": .boolean(false),
        ])
    }

    private func window(used: Int64, duration: Int64, reset: Int64) -> JSONValue {
        .object([
            "usedPercent": .integer(used),
            "windowDurationMins": .integer(duration),
            "resetsAt": .integer(reset),
        ])
    }

    private func frame(id: Int64, result: JSONValue) throws -> Data {
        var data = try JSONEncoder().encode(
            JSONValue.object(["id": .integer(id), "result": result]))
        data.append(UInt8(ascii: "\n"))
        return data
    }
}
