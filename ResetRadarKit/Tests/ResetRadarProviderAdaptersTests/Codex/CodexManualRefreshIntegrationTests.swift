import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarProviderAdapters
import ResetRadarTestSupport
import Testing

/// Proves the real `CodexAppServerSource` satisfies M5's manual-refresh seam end to end: no
/// fake `UsageSource` stands in for the adapter. `HandleManualRefreshRequests` calls
/// `refresh()` on the actual actor, and the resulting `ReadReceipt` must drive `CollectUsage`
/// and `ManualRefreshResult` the same way the Application-layer tests assume.
@Suite("Codex manual refresh with the real adapter seam")
struct CodexManualRefreshIntegrationTests: CodexSourceTestHarness {
    private func makeHandler(
        source: CodexAppServerSource, clock: FakeAppClock, diagnostics: FakeDiagnosticsSink
    ) -> (handler: HandleManualRefreshRequests, snapshots: FakeSnapshotStore) {
        let publisherStore = FakePublisherStore()
        publisherStore.seed {
            $0.lifecycle = .active
            $0.endpoint = URL(string: "https://example.workers.dev")!
            $0.publisherID = PublisherID(data: Data(repeating: 0x09, count: 32))!
        }
        let secrets = FakeSecretStore()
        secrets.seed(.contentKey, SecretValue(Data(repeating: 0x11, count: 32)))
        secrets.seed(.writeToken, SecretValue(Data(repeating: 0x22, count: 32)))
        let snapshots = FakeSnapshotStore()
        let catalogStore = FakeAccountCatalogStore(accounts: [
            AccountMetadata(id: accountID, product: .codex, number: 1)
        ])
        let collector = CollectUsage(
            snapshots: snapshots, diagnostics: diagnostics, clock: clock,
            catalogStore: catalogStore,
            publisherID: PublisherID(data: Data(repeating: 0x09, count: 32))!,
            heartbeatSeconds: 300)
        let publishing = PublishSnapshot(
            publisher: publisherStore, secrets: secrets, cipher: FakeEnvelopeCipher(),
            relay: FakeRelayGateway(), diagnostics: diagnostics, clock: clock,
            random: FakeSecretGenerator())
        let handler = HandleManualRefreshRequests(
            publisher: publisherStore, snapshots: snapshots, collector: collector,
            sources: [source], publishing: publishing, secrets: secrets,
            relay: FakeRelayGateway(), clock: clock)
        return (handler, snapshots)
    }

    private func request(clock: FakeAppClock) -> PendingRefreshRequest {
        PendingRefreshRequest(
            id: RequestID(data: Data(repeating: 0x01, count: 16))!,
            readerID: ReaderID(data: Data(repeating: 0x02, count: 16))!,
            target: .allCodex, expiresAt: clock.now.addingTimeInterval(60))
    }

    @Test("a successful real-adapter read satisfies codexRead and commits the account scope")
    func successfulReadSatisfiesCodexRead() async throws {
        let rig = makeRig()
        try await rig.source.start()
        let (handler, snapshots) = makeHandler(
            source: rig.source, clock: rig.clock, diagnostics: rig.diagnostics)

        let outcome = await handler.handle(pending: [request(clock: rig.clock)])

        #expect(outcome == .handled(count: 1))
        #expect(
            snapshots.current?.manualRefreshResults.flatMap(\.accountResults).map(\.outcome)
                == [.codexRead])
        #expect(snapshots.current?.windows.isEmpty == false)
        await rig.source.stop()
    }

    @Test("a backoff-deferred receipt never satisfies codexRead")
    func deferredReceiptDoesNotSatisfyCodexRead() async throws {
        let session = FakeCodexRPCSession(
            statuses: [.success(FakeCodexRPCSession.authenticated)],
            rateLimits: [.failure(.requestTimedOut)])
        let rig = makeRig(session: session)
        var updates = rig.source.updates.makeAsyncIterator()
        try await rig.source.start()
        _ = try #require(await updates.next())
        let (handler, snapshots) = makeHandler(
            source: rig.source, clock: rig.clock, diagnostics: rig.diagnostics)

        let outcome = await handler.handle(pending: [request(clock: rig.clock)])

        #expect(outcome == .handled(count: 1))
        #expect(
            snapshots.current?.manualRefreshResults.flatMap(\.accountResults).map(\.outcome)
                == [.sourceUnavailable])
        #expect(session.rateLimitReads == 1)
        await rig.source.stop()
    }
}
