import Foundation
import ResetRadarDomain
import ResetRadarTestSupport
import Testing

@testable import ResetRadarApplication

@Suite struct CollectUsageTests {
    struct Rig {
        let clock = FakeAppClock(start: epoch)
        let store = FakeSnapshotStore()
        let sink = FakeDiagnosticsSink()
        let publisherStore = FakePublisherStore()
        let collector: CollectUsage

        init() {
            collector = CollectUsage(
                snapshots: store, diagnostics: sink, clock: clock,
                catalogStore: FakeAccountCatalogStore(accounts: [
                    AccountMetadata(id: codexAccountID, product: .codex, number: 1),
                    AccountMetadata(id: claudeAccountID, product: .claudeCode, number: 2),
                ]), publisherID: publisher, heartbeatSeconds: 300)
        }
    }

    @Test func ingestCommitsLocallyAndNeverAssignsASequence() async throws {
        let rig = Rig()
        let result = try await rig.collector.ingest(report(windows: [window()]))
        #expect(result.change == .transition)
        #expect(rig.store.commits == [result.snapshot])
        #expect(rig.publisherStore.nextSequenceCalls == 0)
        #expect(rig.publisherStore.state.sequence == 0)
    }

    @Test func eachIngestMergesOntoTheCommittedSnapshot() async throws {
        let rig = Rig()
        _ = try await rig.collector.ingest(report(windows: [window()]))
        rig.clock.advance(by: 60)
        let claude = report(.claudeCode, windows: [window(product: .claudeCode)])
        let result = try await rig.collector.ingest(claude)
        #expect(Set(result.snapshot.windows.map(\.product)) == [.codex, .claudeCode])
        #expect(result.snapshot.generatedAt == epoch.addingTimeInterval(60))
        #expect(rig.store.commits.count == 2)
    }

    @Test func aHeartbeatRestampsWithoutChangingContent() async throws {
        let rig = Rig()
        _ = try await rig.collector.ingest(report(windows: [window()]))
        rig.clock.advance(by: 300)
        let beat = try await rig.collector.heartbeat()
        #expect(beat.change == .none)
        #expect(beat.snapshot.generatedAt == epoch.addingTimeInterval(300))
    }

    @Test func droppedWindowsAreRecordedInTheSink() async throws {
        let rig = Rig()
        _ = try await rig.collector.ingest(
            report(windows: [window(), window(product: .claudeCode)]))
        #expect(rig.sink.categories() == [.unknownProduct])
    }

    @Test func anInvalidHeartbeatConfigurationFailsTheIngest() async {
        let rig = Rig()
        let bad = CollectUsage(
            snapshots: rig.store, diagnostics: rig.sink, clock: rig.clock,
            catalogStore: FakeAccountCatalogStore(accounts: []), publisherID: publisher,
            heartbeatSeconds: 0)
        await #expect(throws: UsageSnapshotError.invalidHeartbeat) {
            try await bad.ingest(report(windows: [window()]))
        }
        #expect(rig.store.commits.isEmpty)
    }
}
