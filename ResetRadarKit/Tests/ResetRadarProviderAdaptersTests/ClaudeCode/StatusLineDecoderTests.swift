import Foundation
import Testing

@testable import ResetRadarProviderAdapters

@Suite("Claude Code status-line decoder")
struct StatusLineDecoderTests {
    @Test func decodesFiveHourAndSevenDayWithExactNumbers() throws {
        let input = try decoded(
            statusPayload(
                rateLimits:
                    "{\"seven_day\":\(windowJSON("100")),\"five_hour\":\(windowJSON("0.5"))}"))
        #expect(input.version == "2.1.0")
        #expect(input.activity == 1000)
        #expect(input.windows.map(\.kind) == ["five_hour", "seven_day"])
        #expect(input.windows.map(\.usedPercent) == [0.5, 100])
        #expect(input.windows[0].resetsAt == Date(timeIntervalSince1970: 1_900_000_000))
        #expect(input.sessionKey == SessionKey(sessionID: sentinelSessionID))
    }

    @Test func missingEmptyAndNullRateLimitsAreNotWindows() throws {
        #expect(try decoded(statusPayload(rateLimits: nil)).windows.isEmpty)
        #expect(try decoded(statusPayload(rateLimits: "{}")).windows.isEmpty)
        #expect(try decoded(statusPayload(rateLimits: "null")).windows.isEmpty)
    }

    @Test func spendLimitIsCountedThenIgnored() throws {
        let input = try decoded(
            statusPayload(
                rateLimits:
                    "{\"spend_limit\":{\"used_percentage\":900,\"dollars\":3},"
                    + "\"five_hour\":\(windowJSON("1"))}"))
        #expect(input.windows.map(\.kind) == ["five_hour"])
        let only = try decoded(
            statusPayload(rateLimits: "{\"spend_limit\":{\"used_percentage\":5000}}"))
        #expect(only.windows.isEmpty)
    }

    @Test func unknownKindsKeepNoDurationAndUnsafeKindsReject() throws {
        let input = try decoded(
            statusPayload(rateLimits: "{\"seven_day_opus\":\(windowJSON("3"))}"))
        #expect(input.windows.map(\.kind) == ["seven_day_opus"])
        for kind in ["Five-Hour", "has space", "", String(repeating: "a", count: 129)] {
            #expect(throws: StatusLineDecodingError.invalidWindow) {
                try decoded(statusPayload(rateLimits: "{\"\(kind)\":\(windowJSON("3"))}"))
            }
        }
    }

    @Test func percentageValidation() throws {
        for good in ["0", "7", "12.5", "12.50", "100", "100.0"] {
            _ = try decoded(statusPayload(rateLimits: "{\"five_hour\":\(windowJSON(good))}"))
        }
        for bad in ["-1", "-0", "100.1", "101", "12.34", "1e1", "\"5\"", "true", "null", "{}"] {
            #expect(throws: StatusLineDecodingError.invalidWindow, "\(bad)") {
                try decoded(statusPayload(rateLimits: "{\"five_hour\":\(windowJSON(bad))}"))
            }
        }
        #expect(throws: StatusLineDecodingError.invalidWindow) {
            try decoded(statusPayload(rateLimits: "{\"five_hour\":{\"resets_at\":1900000000}}"))
        }
        #expect(throws: StatusLineDecodingError.invalidWindow) {
            try decoded(statusPayload(rateLimits: "{\"five_hour\":{}}"))
        }
    }

    @Test func resetValidation() throws {
        let absent = try decoded(
            statusPayload(rateLimits: "{\"five_hour\":\(windowJSON("1", resetsAt: nil))}"))
        #expect(absent.windows[0].resetsAt == nil)
        // An expired reset is a valid reading; the Domain decides it is stale.
        _ = try decoded(
            statusPayload(rateLimits: "{\"five_hour\":\(windowJSON("1", resetsAt: "1"))}"))
        for bad in [
            "1.5", "1900000000.0", "-5", "1e9", "\"1900000000\"", "253402300800",
            "9007199254740993",
        ] {
            #expect(throws: StatusLineDecodingError.invalidWindow, "\(bad)") {
                try decoded(
                    statusPayload(rateLimits: "{\"five_hour\":\(windowJSON("1", resetsAt: bad))}"))
            }
        }
    }

    @Test func activityIsOptionalButPresentValuesMustBeExact() throws {
        #expect(try decoded(statusPayload(cost: nil)).activity == nil)
        #expect(try decoded(statusPayload(cost: "{}")).activity == nil)
        #expect(
            try decoded(statusPayload(cost: "{\"total_api_duration_ms\":null}")).activity == nil)
        #expect(
            try decoded(statusPayload(cost: "{\"total_api_duration_ms\":12.5}")).activity == 12.5)
        #expect(
            try decoded(statusPayload(cost: "{\"total_api_duration_ms\":999999999999999}"))
                .activity == 999_999_999_999_999)
        for bad in [
            "-1", "1e3", "\"5\"", "true", "9007199254740993", "1234567890123456",
            "[1]",
        ] {
            #expect(throws: StatusLineDecodingError.invalidActivity, "\(bad)") {
                try decoded(statusPayload(cost: "{\"total_api_duration_ms\":\(bad)}"))
            }
        }
    }

    @Test func versionAndSessionIdentifierGrammars() throws {
        for bad in ["", "2 1", String(repeating: "1", count: 129), "v\u{00E9}"] {
            #expect(throws: StatusLineDecodingError.invalidVersion) {
                try decoded(statusPayload(version: bad))
            }
        }
        #expect(throws: StatusLineDecodingError.invalidSessionID) {
            try decoded(statusPayload(sessionID: ""))
        }
        #expect(throws: StatusLineDecodingError.invalidSessionID) {
            try decoded(Data("{\"version\":\"1\"}".utf8))
        }
        #expect(throws: StatusLineDecodingError.invalidVersion) {
            try decoded(Data("{\"session_id\":\"s\"}".utf8))
        }
        #expect(throws: StatusLineDecodingError.invalidSessionID) {
            try decoded(
                statusPayload(sessionID: String(repeating: "a", count: 4_097)))
        }
    }

    @Test func duplicateMembersAreRejectedAtEveryDepth() {
        let payloads = [
            "{\"session_id\":\"s\",\"session_id\":\"t\",\"version\":\"1\"}",
            "{\"session_id\":\"s\",\"version\":\"1\",\"cost\":{\"a\":1,\"a\":2}}",
            "{\"session_id\":\"s\",\"version\":\"1\",\"rate_limits\":"
                + "{\"five_hour\":\(windowJSON("1")),\"five_hour\":\(windowJSON("2"))}}",
            "{\"session_id\":\"s\",\"version\":\"1\",\"rate_limits\":"
                + "{\"five_hour\":{\"used_percentage\":1,\"used_percentage\":2}}}",
            "{\"session_id\":\"s\",\"version\":\"1\",\"unrelated\":{\"deep\":{\"k\":1,\"k\":2}}}",
            "{\"session_id\":\"s\",\"version\":\"1\",\"unrelated\":[{\"k\":1,\"k\":2}]}",
        ]
        for payload in payloads {
            #expect(throws: StatusLineDecodingError.duplicateMember) {
                try decoded(Data(payload.utf8))
            }
        }
    }

    @Test func nestingAndMemberBounds() throws {
        let deep = String(repeating: "[", count: 40) + String(repeating: "]", count: 40)
        #expect(throws: StatusLineDecodingError.nestingTooDeep) {
            try decoded(statusPayload(extra: "\"x\":\(deep)"))
        }
        let shallow = String(repeating: "[", count: 20) + String(repeating: "]", count: 20)
        _ = try decoded(statusPayload(extra: "\"x\":\(shallow)"))
        let limits = (0..<129).map { "\"k\($0)\":\(windowJSON("1"))" }.joined(separator: ",")
        #expect(throws: StatusLineDecodingError.tooManyLimits) {
            try decoded(statusPayload(rateLimits: "{\(limits)}"))
        }
        let exact = (0..<128).map { "\"k\($0)\":\(windowJSON("1"))" }.joined(separator: ",")
        #expect(try decoded(statusPayload(rateLimits: "{\(exact)}")).windows.count == 128)
        // An ignored spend limit still counts toward the bound.
        let withSpend =
            (0..<128).map { "\"k\($0)\":\(windowJSON("1"))" }
            + ["\"spend_limit\":{\"used_percentage\":5}"]
        #expect(throws: StatusLineDecodingError.tooManyLimits) {
            try decoded(statusPayload(rateLimits: "{\(withSpend.joined(separator: ","))}"))
        }
    }

    @Test func overlongIgnoredStringsStayIgnoredButKeysAreBounded() throws {
        let long = String(repeating: "x", count: 10_000)
        _ = try decoded(statusPayload(extra: "\"note\":\"\(long)\""))
        #expect(throws: StatusLineDecodingError.stringTooLarge) {
            try decoded(statusPayload(extra: "\"\(long)\":1"))
        }
        // Escape expansion counts decoded bytes: 1,400 escaped astral scalars exceed 4 KiB.
        let astral = String(repeating: "\\ud83d\\ude00", count: 1_100)
        #expect(throws: StatusLineDecodingError.stringTooLarge) {
            try decoded(statusPayload(extra: "\"\(astral)\":1"))
        }
    }

    @Test func malformedInputIsRejected() {
        let bad = [
            "", "[]", "{", "{\"session_id\":\"s\",}", "{\"session_id\":\"s\" \"version\":\"1\"}",
            "{\"session_id\":\"\\ud800\",\"version\":\"1\"}",
            "{\"session_id\":\"s\",\"version\":\"1\"} trailing",
            "{\"session_id\":\"s\",\"version\":\"1\",\"n\":01}",
            "{\"session_id\":\"s\",\"version\":\"1\",\"n\":NaN}",
        ]
        for payload in bad {
            #expect(throws: StatusLineDecodingError.self) { try decoded(Data(payload.utf8)) }
        }
        #expect(throws: StatusLineDecodingError.malformedJSON) {
            try decoded(Data([0x7B, 0xFF, 0x7D]))
        }
    }

    @Test func inputBoundIsExact() throws {
        let filler = "\"pad\":\"\(String(repeating: "a", count: 2_000))\""
        let base = statusPayload(extra: filler)
        let room = StatusLineLimits.maximumInputBytes - base.count
        let exact = statusPayload(
            extra: "\"pad\":\"\(String(repeating: "a", count: 2_000 + room))\"")
        #expect(exact.count == StatusLineLimits.maximumInputBytes)
        _ = try decoded(exact)
        #expect(throws: StatusLineDecodingError.inputTooLarge) {
            try decoded(exact + Data(" ".utf8))
        }
    }

    @Test func errorsAndKeysNeverReflectInput() {
        #expect(String(describing: SessionKey(sessionID: sentinelSessionID)) == "SessionKey")
        let payload = statusPayload(
            extra: "\"\(sentinelPrompt)\":{\"k\":1,\"k\":2}")
        do {
            _ = try decoded(payload)
            Issue.record("expected failure")
        } catch {
            #expect(!String(describing: error).contains("SENTINEL"))
            #expect(!"\(error)".contains(sentinelPrompt))
        }
    }

    @Test func sessionKeyIsA128BitDigestOfTheIdentifier() {
        let key = SessionKey(sessionID: "abc")
        #expect(key.hex == "ba7816bf8f01cfea414140de5dae2223")
        #expect(SessionKey(hex: key.hex) == key)
        #expect(SessionKey(hex: "BA7816BF8F01CFEA414140DE5DAE2223") == nil)
        #expect(SessionKey(hex: "abc") == nil)
        #expect(!key.fileName.contains("abc"))
    }

    @Test func captureNeverReturnsATruncatedPayload() {
        var capture = BoundedStatusCapture(maximumBytes: 4)
        capture.append(Data("ab".utf8))
        capture.append(Data("cd".utf8))
        #expect(capture.completeInput == Data("abcd".utf8))
        capture.append(Data("e".utf8))
        #expect(capture.isAbandoned)
        #expect(capture.completeInput == nil)
        capture.append(Data())
        #expect(capture.completeInput == nil)
        var single = BoundedStatusCapture(maximumBytes: 4)
        single.append(Data("abcde".utf8))
        #expect(single.completeInput == nil)
    }
}
