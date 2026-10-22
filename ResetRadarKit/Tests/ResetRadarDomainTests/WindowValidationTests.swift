import Foundation
import Testing

@testable import ResetRadarDomain

@Suite struct WindowValidationTests {
    @Test(arguments: [0, 0.1, 99.9, 100, 100.0])
    func acceptsPercent(value: Double) throws {
        let observation = try UsageObservation(
            validating: value, observedAt: at(0), sourceVersion: "1")
        #expect(observation.usedPercent == value)
    }

    @Test(arguments: [-0.0001, 100.0001, 100.00000001, Double.nan, .infinity, -.infinity])
    func rejectsPercentButKeepsSibling(value: Double) {
        let result = WindowValidation.validate(
            [rawWindow(limitID: "bad", percent: value), rawWindow(limitID: "good", percent: 10)],
            now: at(0))
        #expect(result.valid.map(\.limitID) == ["good"])
        #expect(result.diagnostics.map(\.category) == [.invalidPercentage])
        #expect(result.diagnostics.first?.product == .codex)
    }

    @Test func negativeZeroNormalizes() throws {
        let observation = try UsageObservation(
            validating: -0.0, observedAt: at(0), sourceVersion: "1")
        #expect(observation.usedPercent.sign == .plus)
    }

    @Test func rejectsNonFiniteTimestampsAndBadPrecision() {
        #expect(throws: WindowValidationError.invalidTimestamp) {
            try UsageObservation(
                validating: 1, observedAt: Date(timeIntervalSinceReferenceDate: .nan),
                sourceVersion: "")
        }
        #expect(throws: WindowValidationError.invalidTimestamp) {
            try AllowanceWindow(
                validating: rawWindow(resetsAt: Date(timeIntervalSinceReferenceDate: .infinity)))
        }
        #expect(throws: WindowValidationError.invalidPrecision) {
            try UsageObservation(
                validating: 1, observedAt: at(0), sourceVersion: "", fractionDigits: 2)
        }
    }

    @Test(arguments: [0, -300]) func rejectsNonPositiveDuration(minutes: Int) {
        let result = WindowValidation.validate(
            [rawWindow(minutes: minutes), rawWindow(limitID: "ok")], now: at(0))
        #expect(result.valid.count == 1)
        #expect(result.diagnostics.map(\.category) == [.invalidDuration])
    }

    @Test func rejectsBadIdentifiersAndReportState() {
        var badScope = rawWindow()
        badScope.accountScope = "abcd"
        let result = WindowValidation.validate(
            [rawWindow(limitID: ""), badScope, rawWindow(state: .unknown)], now: at(0))
        #expect(result.valid.isEmpty)
        #expect(
            result.diagnostics.map(\.category) == [
                .invalidIdentifier, .invalidIdentifier, .invalidReportState,
            ])
    }

    @Test func unknownProductIsIgnoredWithDiagnostic() {
        let result = WindowValidation.validate(
            [rawWindow(product: "gemini"), rawWindow(limitID: "ok")], now: at(5))
        #expect(result.valid.count == 1)
        #expect(result.diagnostics == [.unknownProduct(at: at(5))])
    }

    @Test func duplicateIDKeepsFirst() {
        var second = rawWindow(percent: 99)
        second.label = "second"
        let result = WindowValidation.validate([rawWindow(percent: 1), second], now: at(0))
        #expect(result.valid.map(\.observation?.usedPercent) == [1])
        #expect(result.diagnostics.map(\.category) == [.duplicateWindow])
    }

    @Test func invalidValuesNeverAppearInDiagnostics() throws {
        let result = WindowValidation.validate(
            [rawWindow(limitID: "secret-limit", percent: 100.0001)], now: at(0))
        let json = try wire(result.diagnostics)
        #expect(!json.contains("100.0001") && !json.contains("secret-limit"))
    }

    @Test func windowRoundTrips() throws {
        let value = window(percent: 12.5)
        let data = try WireCoding.encoder().encode(value)
        #expect(try WireCoding.decoder().decode(AllowanceWindow.self, from: data) == value)
    }
}
