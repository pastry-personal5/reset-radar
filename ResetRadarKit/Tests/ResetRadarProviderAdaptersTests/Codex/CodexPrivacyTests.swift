import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarProviderAdapters
import ResetRadarTestSupport
import Testing

/// Proves the Codex source and decoder redact provider content. The frame reader, structural
/// preflight, and command runner are proven string-free by their own payload-less error types
/// and result shapes (`BoundedRPCFrameTests`, `JSONRPCProtocolTests`,
/// `CodexCommandRunnerTests`); this suite covers what those cannot: the account-identifier,
/// limit-identifier, unknown-field, and provider-reported-value path through the normalizer,
/// the source, and its diagnostics.
@Suite("Codex privacy")
struct CodexPrivacyTests: CodexSourceTestHarness {
    private static let providerAccountSentinel = "SENTINEL-PROVIDER-ACCOUNT"
    private static let limitIDSentinel = "SENTINEL-LIMIT-ID"
    private static let unknownFieldSentinel = "SENTINEL-PROMPT"
    /// Distinctive, not a round number, so an accidental substring match is implausible.
    private static let percentSentinel: Int64 = 73
    private static let resetSentinel: Int64 = 2_000_000_137

    /// Diagnostics must never carry any provider-reported value, approved or not.
    private static let diagnosticSentinels: [String] = [
        providerAccountSentinel, limitIDSentinel, unknownFieldSentinel,
        String(percentSentinel), String(resetSentinel),
    ]
    /// A typed report legitimately carries the approved percentage, reset, and limit identity;
    /// only the provider account identifier and an ignored unknown field must never cross into it.
    private static let reportSentinels: [String] = [providerAccountSentinel, unknownFieldSentinel]

    private func sentinelLimits() -> JSONValue {
        .object([
            "accountId": .string(Self.providerAccountSentinel),
            "ordinaryUsageAllowed": .boolean(true),
            "prompt": .string(Self.unknownFieldSentinel),
            "rateLimits": .object([
                "limitId": .string(Self.limitIDSentinel),
                "primary": .object([
                    "usedPercent": .integer(Self.percentSentinel),
                    "windowDurationMins": .integer(300),
                    "resetsAt": .integer(Self.resetSentinel),
                ]),
            ]),
        ])
    }

    private func assertNoSentinel(_ text: String, in sentinels: [String], _ comment: Comment) {
        for sentinel in sentinels {
            #expect(!text.contains(sentinel), "\(comment): leaked \(sentinel)")
        }
    }

    @Test("a complete report carries the provider value only inside its typed window")
    func successfulReportIsolatesProviderValues() async throws {
        let session = FakeCodexRPCSession(
            statuses: [.success(FakeCodexRPCSession.authenticated)],
            rateLimits: [.success(sentinelLimits())])
        let rig = makeRig(session: session)
        var updates = rig.source.updates.makeAsyncIterator()
        try await rig.source.start()
        let report = try #require(await updates.next())

        #expect(report.windows.first?.observation?.usedPercent == Double(Self.percentSentinel))
        // The provider account identifier and the ignored unknown field never cross into the
        // typed report; only the opaque scope (derived by the injected AccountScoper, never the
        // raw identifier) does, alongside the approved percentage, reset, and limit identity.
        assertNoSentinel(String(describing: report), in: Self.reportSentinels, "report")
        for event in rig.diagnostics.recorded {
            assertNoSentinel(String(describing: event), in: Self.diagnosticSentinels, "diagnostic")
        }
        await rig.source.stop()
    }

    @Test("an invalid percentage and a remote error redact every diagnostic and failure")
    func diagnosticsAndFailuresAreRedacted() async throws {
        let outOfRangeLimits = JSONValue.object([
            "accountId": .string(Self.providerAccountSentinel),
            "ordinaryUsageAllowed": .boolean(true),
            "prompt": .string(Self.unknownFieldSentinel),
            "rateLimits": .object([
                "limitId": .string(Self.limitIDSentinel),
                "primary": .object([
                    "usedPercent": .integer(250), "windowDurationMins": .integer(300),
                    "resetsAt": .integer(Self.resetSentinel),
                ]),
            ]),
        ])
        let malformedRig = makeRig(
            session: FakeCodexRPCSession(
                statuses: [.success(FakeCodexRPCSession.authenticated)],
                rateLimits: [.success(outOfRangeLimits)]))
        var malformedUpdates = malformedRig.source.updates.makeAsyncIterator()
        try await malformedRig.source.start()
        let malformedReport = try #require(await malformedUpdates.next())
        await malformedRig.source.stop()

        let remoteErrorRig = makeRig(
            session: FakeCodexRPCSession(
                statuses: [
                    .success(FakeCodexRPCSession.authenticated),
                    .success(FakeCodexRPCSession.authenticated),
                ],
                rateLimits: [.failure(.remoteError(code: -32_600))]))
        var remoteErrorUpdates = remoteErrorRig.source.updates.makeAsyncIterator()
        try await remoteErrorRig.source.start()
        let remoteErrorReport = try #require(await remoteErrorUpdates.next())
        await remoteErrorRig.source.stop()

        let diagnostics = malformedRig.diagnostics.recorded + remoteErrorRig.diagnostics.recorded
        #expect(!diagnostics.isEmpty)
        for event in diagnostics {
            assertNoSentinel(String(describing: event), in: Self.diagnosticSentinels, "diagnostic")
        }
        for failure in [
            CodexSourceFailure.signedOut, .incompatible, .malformed, .accountScope,
            .temporarilyUnavailable,
        ] {
            assertNoSentinel(
                String(describing: failure), in: Self.diagnosticSentinels, "typed failure case")
        }
        // The rejected-window report (percentage 250 is out of range, so no window survives) and
        // the remote-error failure report are both state-only: neither carries any sentinel.
        for report in [malformedReport, remoteErrorReport] {
            assertNoSentinel(String(describing: report), in: Self.diagnosticSentinels, "report")
        }
    }
}
