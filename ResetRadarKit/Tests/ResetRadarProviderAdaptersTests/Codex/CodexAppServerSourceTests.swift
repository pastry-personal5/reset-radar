import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarProviderAdapters
import ResetRadarTestSupport
import Testing

private struct FailureCase {
    let failure: CodexSourceFailure
    let state: SourceState
    let diagnostic: ProviderFailureClass
    let retries: Bool
}

@Suite("Codex app-server source")
struct CodexAppServerSourceTests: CodexSourceTestHarness {
    @Test("start initializes once and emits one complete account-scoped report")
    func startAndRead() async throws {
        let rig = makeRig()
        var updates = rig.source.updates.makeAsyncIterator()
        try await rig.source.start()
        let report = try #require(await updates.next())

        #expect(rig.session.initializeParameters.count == 1)
        #expect(rig.session.statusReads == 1)
        #expect(rig.session.rateLimitReads == 1)
        #expect(report.isCompleteReport)
        #expect(report.source.accountID == accountID)
        #expect(report.source.providerScope != nil)
        #expect(report.windows.first?.observation?.usedPercent == 25)
        await rig.source.stop()
    }

    @Test("simultaneous explicit callers await one physical read and identical receipt")
    func coalescing() async throws {
        let rig = makeRig()
        try await rig.source.start()
        rig.session.holdRateLimitReads()
        let first = Task { await rig.source.refresh() }
        let second = Task { await rig.source.refresh() }
        await waitForRateLimitReads(2, session: rig.session)
        #expect(rig.session.rateLimitReads == 2)
        rig.session.releaseRateLimitRead()
        let firstReceipt = await first.value
        let secondReceipt = await second.value
        #expect(firstReceipt == secondReceipt)
        #expect(firstReceipt.performedSuccessfully)
        await rig.source.stop()
    }

    @Test("timeout emits one state-only result and active backoff defers without a read")
    func timeoutAndBackoff() async throws {
        let session = FakeCodexRPCSession(
            statuses: [.success(FakeCodexRPCSession.authenticated)],
            rateLimits: [.failure(.requestTimedOut)])
        let rig = makeRig(session: session)
        var updates = rig.source.updates.makeAsyncIterator()
        try await rig.source.start()
        let failure = try #require(await updates.next())
        #expect(failure.source.state == .sourceOffline)
        #expect(!failure.isCompleteReport)
        #expect(session.stops == 1)

        let receipt = await rig.source.refresh()
        #expect(
            receipt
                == .deferred(
                    retryAt: origin.addingTimeInterval(60), sourceState: .sourceOffline))
        #expect(session.rateLimitReads == 1)
        #expect(rig.diagnostics.recorded.last?.providerFailureClass == .timeout)
        await rig.source.stop()
    }

    @Test("every typed operational failure maps to its approved state and retry policy")
    func failureMatrix() async throws {
        let cases: [FailureCase] = [
            FailureCase(
                failure: .notConfigured, state: .unavailable, diagnostic: .notInstalled,
                retries: false),
            FailureCase(
                failure: .notInstalled, state: .unavailable, diagnostic: .notInstalled,
                retries: false),
            FailureCase(
                failure: .permissionDenied, state: .unavailable, diagnostic: .permissionDenied,
                retries: false),
            FailureCase(
                failure: .incompatible, state: .incompatible, diagnostic: .incompatible,
                retries: false),
            FailureCase(
                failure: .malformed, state: .incompatible, diagnostic: .malformed, retries: false),
            FailureCase(
                failure: .timeout, state: .sourceOffline, diagnostic: .timeout, retries: true),
            FailureCase(
                failure: .processExited, state: .sourceOffline, diagnostic: .processExited,
                retries: true),
            FailureCase(
                failure: .accountScope, state: .sourceOffline, diagnostic: .accountScope,
                retries: true),
            FailureCase(
                failure: .temporarilyUnavailable, state: .sourceOffline,
                diagnostic: .temporarilyUnavailable, retries: true),
        ]
        for item in cases { try await verify(item) }
    }

    private func verify(_ item: FailureCase) async throws {
        let (failure, state, diagnostic, retries) = (
            item.failure, item.state, item.diagnostic, item.retries
        )
        let session = FakeCodexRPCSession(statuses: [], rateLimits: [])
        let clock = FakeAppClock(start: origin)
        let diagnostics = FakeDiagnosticsSink()
        let source = CodexAppServerSource(
            accountID: accountID, sourceVersion: "codex 0.164.0",
            factory: FakeCodexRPCSessionFactory(session: session, failure: failure),
            scoper: FakeAccountScoper(), diagnostics: diagnostics, clock: clock)
        var updates = source.updates.makeAsyncIterator()
        try await source.start()
        let report = try #require(await updates.next())
        #expect(report.source.state == state)
        #expect(!report.isCompleteReport && report.windows.isEmpty)
        #expect(diagnostics.recorded.map(\.providerFailureClass) == [diagnostic])
        let next = await source.refresh()
        if retries {
            #expect(
                next
                    == .deferred(
                        retryAt: origin.addingTimeInterval(60), sourceState: state))
        } else {
            #expect(next == .unavailable(sourceState: state))
        }
    }

    @Test("a generic rate-limit error rechecks structured status and can prove signed-out")
    func authenticationRecheck() async throws {
        let session = FakeCodexRPCSession(
            statuses: [
                .success(FakeCodexRPCSession.authenticated),
                .success(FakeCodexRPCSession.signedOut),
            ],
            rateLimits: [.failure(.remoteError(code: -32_000))])
        let rig = makeRig(session: session)
        var updates = rig.source.updates.makeAsyncIterator()
        try await rig.source.start()
        let report = try #require(await updates.next())
        #expect(report.source.state == .signedOut)
        #expect(session.statusReads == 2)
        #expect(session.stops == 0)
        #expect(rig.diagnostics.recorded.last?.providerFailureClass == .signedOut)
        await rig.source.stop()
    }

    @Test("a known provider-scope change clears prior windows even when normalization fails")
    func scopeChangeWithStateOnlyFailure() async throws {
        let changedInvalidLimits = JSONValue.object([
            "accountId": .string("different-synthetic-account"),
            "ordinaryUsageAllowed": .boolean(true),
            "rateLimits": .object([
                "limitId": .string("codex"),
                "primary": .object([
                    "usedPercent": .integer(101),
                    "windowDurationMins": .integer(300),
                    "resetsAt": .integer(2_000_000_100),
                ]),
            ]),
        ])
        let session = FakeCodexRPCSession(
            statuses: [.success(FakeCodexRPCSession.authenticated)],
            rateLimits: [
                .success(FakeCodexRPCSession.successfulLimits),
                .success(changedInvalidLimits),
            ])
        let rig = makeRig(session: session)
        var updates = rig.source.updates.makeAsyncIterator()
        try await rig.source.start()
        let first = try #require(await updates.next())
        _ = await rig.source.refresh()
        let failed = try #require(await updates.next())
        #expect(failed.source.state == .incompatible)
        #expect(failed.source.providerScope != first.source.providerScope)
        #expect(failed.clearsWindows)
        #expect(failed.windows.isEmpty)
        await rig.source.stop()
    }

}
