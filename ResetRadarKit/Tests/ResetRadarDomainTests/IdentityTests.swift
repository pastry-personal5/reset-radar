import Foundation
import Testing

@testable import ResetRadarDomain

@Suite struct IdentityTests {
    @Test func byteIdentifiersRoundTrip() throws {
        let coder = (WireCoding.encoder(), WireCoding.decoder())
        let scope = AccountScope(data: bytes(16))!
        let data = try coder.0.encode([scope])
        #expect(
            text(data) == "[\"\(String(repeating: "ab", count: 16))\"]")
        #expect(try coder.1.decode([AccountScope].self, from: data) == [scope])
        #expect(
            try coder.1.decode(
                PublisherID.self, from: coder.0.encode([publisher]).dropFirst().dropLast())
                == publisher)
        for id in [readerA, readerB] {
            #expect(try coder.1.decode([ReaderID].self, from: coder.0.encode([id])) == [id])
        }
    }

    @Test(arguments: [15, 17]) func accountScopeRejectsWrongLength(count: Int) {
        #expect(AccountScope(data: bytes(count)) == nil)
    }

    @Test func fixedLengths() {
        #expect(PublisherID(data: bytes(31)) == nil)
        #expect(ReaderID(data: bytes(17)) == nil)
        #expect(AccountScope(hex: "zz" + String(repeating: "00", count: 15)) == nil)
        #expect(AccountScope(hex: String(repeating: "AB", count: 16)) == nil)
    }

    /// 15 two-byte characters plus two ASCII ones have 32 UTF-8 bytes but 17 characters.
    @Test func multiByteHexIsRejectedWithoutTrapping() {
        #expect(AccountScope(hex: String(repeating: "é", count: 15) + "ab") == nil)
        #expect(AccountScope(hex: String(repeating: "é", count: 16)) == nil)
        #expect(AccountScope(hex: String(repeating: "٣٣", count: 8)) == nil)
    }

    @Test func windowIDDependsOnScope() {
        let one = AccountScope(data: bytes(16, 1))!
        let two = AccountScope(data: bytes(16, 2))!
        let base = WindowID(product: .codex, scope: one, limitID: "codex", durationMinutes: 300)
        #expect(
            base == WindowID(product: .codex, scope: one, limitID: "codex", durationMinutes: 300))
        #expect(
            base != WindowID(product: .codex, scope: two, limitID: "codex", durationMinutes: 300))
        #expect(
            base != WindowID(product: .codex, scope: nil, limitID: "codex", durationMinutes: 300))
    }

    @Test func homeSlotAccessors() {
        #expect(HomeSlot.codexFiveHour.product == .codex)
        #expect(HomeSlot.claudeCodeWeekly.product == .claudeCode)
        #expect(HomeSlot.codexFiveHour.durationMinutes == 300)
        #expect(HomeSlot.claudeCodeWeekly.durationMinutes == 10_080)
        #expect(
            HomeSlot.allCases.map(\.rawValue) == [
                "codexFiveHour", "codexWeekly", "claudeCodeFiveHour", "claudeCodeWeekly",
            ])
    }

    @Test func closedIdentityThrowsOnUnknownValue() {
        #expect(throws: DecodingError.self) {
            try WireCoding.decoder().decode([ProductID].self, from: Data("[\"gemini\"]".utf8))
        }
    }

    @Test func unknownOptionalEnumDecodesToUnknown() throws {
        let decoder = WireCoding.decoder()
        #expect(
            try decoder.decode([ProviderLimitState].self, from: Data("[\"somethingNew\"]".utf8))
                == [.unknown])
        #expect(
            try decoder.decode([DiagnosticEvent.Category].self, from: Data("[\"x\"]".utf8)) == [
                .unknown
            ])
        #expect(
            try decoder.decode([ReportState].self, from: Data("[\"reported\"]".utf8)) == [.reported]
        )
    }

    @Test func schemaVersionAboveRangeThrows() {
        #expect(throws: SchemaError.unsupported(found: 2, supported: 1...1)) {
            try SchemaVersion(rawValue: 2).require(in: 1...1)
        }
        #expect(throws: Never.self) { try SchemaVersion(rawValue: 1).require(in: 1...1) }
    }
}

@Suite struct WireCodingTests {
    @Test func datesUseMillisecondISO8601() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000.123)
        let data = try WireCoding.encoder().encode([date])
        #expect(text(data) == "[\"2023-11-14T22:13:20.123Z\"]")
        let back = try WireCoding.decoder().decode([Date].self, from: data)
        #expect(abs(back[0].timeIntervalSince(date)) < 0.0005)
    }

    @Test func malformedDateIsRejected() {
        #expect(throws: DecodingError.self) {
            try WireCoding.decoder().decode([Date].self, from: Data("[\"yesterday\"]".utf8))
        }
    }

    @Test func wholeSecondsKeepZeroMilliseconds() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let data = try WireCoding.encoder().encode([date])
        #expect(text(data) == "[\"2023-11-14T22:13:20.000Z\"]")
        #expect(try WireCoding.decoder().decode([Date].self, from: data) == [date])
    }

    @Test func decoderToleratesDateWithoutMilliseconds() throws {
        let decoded = try WireCoding.decoder().decode(
            [Date].self, from: Data("[\"2023-11-14T22:13:20Z\"]".utf8))
        #expect(decoded == [Date(timeIntervalSince1970: 1_700_000_000)])
    }

    @Test(arguments: ["", "2023-11-14"])
    func incompleteDateIsRejected(value: String) {
        #expect(throws: DecodingError.self) {
            try WireCoding.decoder().decode([Date].self, from: Data("[\"\(value)\"]".utf8))
        }
    }

    @Test func keysAreSorted() throws {
        let data = try WireCoding.encoder().encode(["b": 1, "a": 2])
        #expect(text(data) == "{\"a\":2,\"b\":1}")
    }
}
