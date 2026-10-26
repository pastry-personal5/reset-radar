import Foundation
import ResetRadarApplication
import ResetRadarDomain
import Testing
import UserNotifications

@testable import ResetRadarScheduling

private let account = AccountID(data: Data(repeating: 0x11, count: 16))!
private let scope = AccountScope(data: Data(repeating: 0x22, count: 16))!
private let fireAt = Date(timeIntervalSince1970: 1_700_000_123)

@Suite struct NotificationRequestCodecTests {
    @Test func standardIdentifiersStayLegacyStableAndAdditionalIdentifiersAreBoundedDigests() {
        let standard = ResetRequest(
            selection: .standard(AccountWindow(accountID: account, window: .fiveHour)),
            fireAt: fireAt)
        #expect(standard.identifier == "reset.\(account.hex).fiveHour")

        let first = WindowSelection.additional(
            WindowID(
                accountID: account, product: .codex, scope: scope,
                limitID: String(repeating: "scope.with.dots/and unicode 🛰️", count: 20),
                durationMinutes: 60))
        let second = WindowSelection.additional(
            WindowID(
                accountID: account, product: .codex, scope: nil,
                limitID: String(repeating: "scope.with.dots/and unicode 🛰️", count: 20),
                durationMinutes: 60))
        #expect(ResetRequest(selection: first, fireAt: fireAt).identifier.count == 73)
        #expect(
            ResetRequest(selection: first, fireAt: fireAt).identifier
                != ResetRequest(selection: second, fireAt: fireAt).identifier)
        #expect(WindowSelection(versionedID: first.versionedID) == first)
    }

    @Test func metadataRoundTripsTheCompleteDesiredRequestAndRejectsIdentifierMismatch() {
        let selection = WindowSelection.additional(
            WindowID(
                accountID: account, product: .claudeCode, scope: nil, limitID: "extra",
                durationMinutes: 120))
        let desired = ResetRequest(
            selection: selection, fireAt: fireAt, accountLabel: "Build account",
            product: .claudeCode, window: .additional(label: "Burst", durationMinutes: 120),
            sourceState: .sourceOffline, fractionDigits: 1)
        let metadata = NotificationRequestCodec.userInfo(for: desired)
        #expect(
            NotificationRequestCodec.request(
                identifier: desired.identifier, userInfo: metadata, fireAt: fireAt) == desired)
        #expect(
            NotificationRequestCodec.request(
                identifier: desired.identifier + ".wrong", userInfo: metadata, fireAt: fireAt)
                == nil)
        #expect(
            NotificationRequestCodec.request(
                identifier: desired.identifier, userInfo: metadata,
                fireAt: fireAt.addingTimeInterval(1)) == nil)

        var mismatchedKind = metadata
        mismatchedKind["resetRadar.window.kind"] = "standard"
        mismatchedKind["resetRadar.window.standard"] = "fiveHour"
        #expect(
            NotificationRequestCodec.request(
                identifier: desired.identifier, userInfo: mismatchedKind, fireAt: fireAt) == nil)
    }

    @Test func triggerComponentsAlwaysDescribeTheSameUTCInstant() throws {
        let subsecond = fireAt.addingTimeInterval(0.456)
        let components = NotificationRequestCodec.utcComponents(for: subsecond)
        #expect(components.timeZone?.secondsFromGMT() == 0)
        #expect(components.calendar?.timeZone.secondsFromGMT() == 0)
        let reconstructed = try #require(components.calendar?.date(from: components))
        #expect(abs(reconstructed.timeIntervalSince(subsecond)) < 0.001)
    }

    @Test func copyNamesAliasProductAndWindowWithoutTimeOrPercentage() {
        let request = ResetRequest(
            selection: .standard(AccountWindow(accountID: account, window: .weekly)),
            fireAt: fireAt, accountLabel: "Research", product: .claudeCode,
            window: .standard(.weekly), sourceState: .reporting, fractionDigits: 1)
        let copy = NotificationRequestCodec.copy(for: request)
        #expect(copy.title == "Allowance Reset")
        #expect(copy.body.contains("Research"))
        #expect(copy.body.contains("Claude Code"))
        #expect(copy.body.contains("weekly"))
        #expect(!copy.body.contains("%"))
        #expect(!copy.body.contains("2023"))
    }

    @Test func authorizationKeepsProvisionalStatesDistinct() {
        #expect(NotificationRequestCodec.authorization(.authorized) == .authorized)
        #expect(NotificationRequestCodec.authorization(.provisional) == .provisional)
        #expect(NotificationRequestCodec.authorization(.denied) == .denied)
        #expect(NotificationRequestCodec.authorization(.notDetermined) == .notDetermined)
    }

    @Test func foregroundPresentationIsOwnedAndFullyAuthorizedOnly() {
        #expect(
            ResetNotificationPresentationPolicy.shouldPresent(
                identifier: "reset.owned", authorizationStatus: .authorized))
        #expect(
            !ResetNotificationPresentationPolicy.shouldPresent(
                identifier: "reset.owned", authorizationStatus: .provisional))
        #expect(
            !ResetNotificationPresentationPolicy.shouldPresent(
                identifier: "other", authorizationStatus: .authorized))
    }
}
