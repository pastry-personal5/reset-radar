import Foundation
import Testing

@testable import ResetRadarDomain

@Suite struct UsageSnapshotTests {
    static let goldenJSON = """
        {"diagnostics":[],"generatedAt":"2026-01-01T00:00:00.000Z","heartbeatSeconds":300,\
        "manualRefreshResults":[],"publisherID":"\(String(repeating: "01", count: 32))",\
        "schemaVersion":1,"sources":[\
        {"kind":"codexAppServer","product":"codex","state":"reporting","version":"1.0"},\
        {"kind":"claudeCodeStatusLine","product":"claudeCode","state":"reporting",\
        "version":"1.0"}],\
        "windows":[\
        {"durationMinutes":300,"isDefaultLimit":true,"limitID":"codex","observation":\
        {"fractionDigits":0,"observedAt":"2026-01-01T00:00:00.000Z",\
        "sourceVersion":"1.0","usedPercent":42},\
        "product":"codex","reportState":"reported","resetsAt":"2026-01-01T05:00:00.000Z"},\
        {"durationMinutes":10080,"isDefaultLimit":true,"limitID":"seven_day","observation":\
        {"fractionDigits":1,"observedAt":"2026-01-01T00:00:00.000Z",\
        "sourceVersion":"1.0","usedPercent":7.5},\
        "product":"claudeCode","reportState":"retained","resetsAt":"2026-01-08T00:00:00.000Z"}]}
        """

    static let base = Date(timeIntervalSince1970: 1_767_225_600)  // 2026-01-01T00:00:00Z

    static func golden() throws -> UsageSnapshot {
        let codex = try AllowanceWindow(
            validating: RawWindow(
                product: "codex", limitID: "codex", durationMinutes: 300, isDefaultLimit: true,
                reportState: .reported, resetsAt: base.addingTimeInterval(18_000),
                observation: RawObservation(
                    usedPercent: 42, observedAt: base, sourceVersion: "1.0", fractionDigits: 0)))
        let claude = try AllowanceWindow(
            validating: RawWindow(
                product: "claudeCode", limitID: "seven_day", durationMinutes: 10_080,
                isDefaultLimit: true,
                reportState: .retained, resetsAt: base.addingTimeInterval(604_800),
                observation: RawObservation(
                    usedPercent: 7.5, observedAt: base, sourceVersion: "1.0", fractionDigits: 1)))
        return snapshot(windows: [codex, claude], generatedAt: base)
    }

    @Test func goldenJSONRoundTrip() throws {
        let expected = try Self.golden()
        let data = try WireCoding.encoder().encode(expected)
        #expect(text(data) == Self.goldenJSON)
        #expect(
            try WireCoding.decoder().decode(UsageSnapshot.self, from: Data(Self.goldenJSON.utf8))
                == expected)
    }

    @Test func unsupportedSchemaRejectsWholeSnapshot() {
        let json = Self.goldenJSON.replacingOccurrences(
            of: "\"schemaVersion\":1", with: "\"schemaVersion\":2,\"futureField\":1")
        #expect(throws: SchemaError.unsupported(found: 2, supported: 1...1)) {
            try WireCoding.decoder().decode(UsageSnapshot.self, from: Data(json.utf8))
        }
    }

    @Test func oneBadWindowKeepsTheRest() throws {
        let json = Self.goldenJSON.replacingOccurrences(
            of: "\"usedPercent\":42", with: "\"usedPercent\":142")
        let decoded = try WireCoding.decoder().decode(UsageSnapshot.self, from: Data(json.utf8))
        #expect(decoded.windows.map(\.limitID) == ["seven_day"])
        #expect(decoded.diagnostics.map(\.category) == [.invalidPercentage])
        #expect(decoded.diagnostics.first?.timestamp == Self.base)
    }

    @Test(arguments: [0, -5, 3_601, Int.max]) func rejectsBadHeartbeat(seconds: Int) throws {
        #expect(throws: UsageSnapshotError.invalidHeartbeat) {
            try UsageSnapshot(
                publisherID: publisher, generatedAt: at(0), heartbeatSeconds: seconds, sources: [],
                windows: [])
        }
        let json = Self.goldenJSON.replacingOccurrences(
            of: "\"heartbeatSeconds\":300", with: "\"heartbeatSeconds\":\(seconds)")
        #expect(throws: UsageSnapshotError.invalidHeartbeat) {
            try WireCoding.decoder().decode(UsageSnapshot.self, from: Data(json.utf8))
        }
    }

    @Test func zeroWindowsIsValid() throws {
        let empty = snapshot(windows: [])
        let data = try WireCoding.encoder().encode(empty)
        #expect(try WireCoding.decoder().decode(UsageSnapshot.self, from: data) == empty)
    }

    @Test func unknownLimitStateDecodesToUnknown() throws {
        let json = Self.goldenJSON.replacingOccurrences(
            of: "\"product\":\"codex\",\"reportState\"",
            with: "\"product\":\"codex\",\"providerLimitState\":\"newState\",\"reportState\"")
        let decoded = try WireCoding.decoder().decode(UsageSnapshot.self, from: Data(json.utf8))
        #expect(decoded.windows[0].providerLimitState == .unknown)
    }
}
