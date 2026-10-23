import Foundation
import ResetRadarDomain
import ResetRadarTestSupport
import Testing

@testable import ResetRadarApplication

final class ManualRig: @unchecked Sendable {
    let base = PublishRig()
    let store = FakeSnapshotStore()
    let codex: FakeUsageSource
    let claude: FakeUsageSource
    let publishing: PublishSnapshot
    let collector: CollectUsage

    var clock: FakeAppClock { base.clock }

    init() {
        codex = FakeUsageSource(product: .codex, clock: base.clock)
        claude = FakeUsageSource(product: .claudeCode, clock: base.clock)
        publishing = base.makePublisher()
        collector = CollectUsage(
            snapshots: store, diagnostics: base.sink, clock: base.clock, publisherID: publisher,
            heartbeatSeconds: 300)
    }

    func makeHandler() -> HandleManualRefreshRequests {
        HandleManualRefreshRequests(
            publisher: base.store, snapshots: store, collector: collector,
            sources: [codex, claude], publishing: publishing, secrets: base.secrets,
            relay: base.relay, clock: clock, heartbeatSeconds: 300)
    }

    func request(
        _ id: UInt8, reader: ReaderID = readerA, expires: TimeInterval = 60
    ) -> PendingRefreshRequest {
        PendingRefreshRequest(
            id: requestID(id), readerID: reader, expiresAt: clock.now.addingTimeInterval(expires))
    }

    func receipt(
        _ start: TimeInterval, _ finish: TimeInterval, succeeded: Bool = true
    ) -> ReadReceipt {
        ReadReceipt(
            startedAt: epoch.addingTimeInterval(start),
            finishedAt: epoch.addingTimeInterval(finish),
            succeeded: succeeded, report: succeeded ? report(windows: [window()]) : nil)
    }
}

@Suite struct HandleManualRefreshRequestsTests {
    let rig = ManualRig()

    @Test func severalIDsCoalesceIntoOneReadWithAResultPerReader() async {
        let handler = rig.makeHandler()
        let outcome = await handler.handle(pending: [
            rig.request(1), rig.request(2, reader: readerB), rig.request(3),
        ])
        #expect(outcome == .handled(count: 3))
        #expect(rig.codex.refreshCount == 1)
        let results = rig.store.current?.manualRefreshResults ?? []
        #expect(results.count == 3)
        #expect(results.first { $0.requestID == requestID(2) }?.readerID == readerB)
        #expect(rig.base.relay.calls(.putSnapshot).count == 1)
        #expect(rig.base.relay.calls(.deleteRefreshRequest).count == 3)
    }

    @Test func aReadBeforeTheObservationDoesNotSatisfyTheRequest() async {
        rig.codex.queueReceipts(rig.receipt(-10, -1), rig.receipt(0, 1))
        _ = await rig.makeHandler().handle(pending: [rig.request(1)])
        #expect(rig.codex.refreshCount == 2)
    }

    @Test func aReadInFlightAtTheObservationOrStartedAtItSatisfiesIt() async {
        rig.codex.queueReceipts(rig.receipt(-5, 2))
        _ = await rig.makeHandler().handle(pending: [rig.request(1)])
        #expect(rig.codex.refreshCount == 1)
        let other = ManualRig()
        other.codex.queueReceipts(other.receipt(0, 0))
        _ = await other.makeHandler().handle(pending: [other.request(1)])
        #expect(other.codex.refreshCount == 1)
    }

    @Test func aSecondForcedReadInsideThirtySecondsWaits() async {
        let handler = rig.makeHandler()
        _ = await handler.handle(pending: [rig.request(1)])
        rig.clock.advance(by: 29.999)
        let waiting = await handler.handle(pending: [rig.request(2)])
        #expect(waiting == .waiting(until: epoch.addingTimeInterval(30)))
        #expect(rig.codex.refreshCount == 1)
        rig.clock.set(epoch.addingTimeInterval(30))
        #expect(await handler.handle(pending: [rig.request(2)]) == .handled(count: 1))
        #expect(rig.codex.refreshCount == 2)
    }

    @Test func aFailedReadIsPublishedAsSourceUnavailable() async {
        rig.codex.queueReceipts(rig.receipt(0, 1, succeeded: false))
        let outcome = await rig.makeHandler().handle(pending: [rig.request(1)])
        #expect(outcome == .handled(count: 1))
        #expect(rig.store.current?.manualRefreshResults.map(\.outcome) == [.sourceUnavailable])
    }

    @Test func aSuccessfulReadIsPublishedEvenWhenThePercentageIsUnchanged() async {
        _ = try? await rig.collector.ingest(report(windows: [window()]))
        let before = rig.base.relay.calls(.putSnapshot).count
        _ = await rig.makeHandler().handle(pending: [rig.request(1)])
        #expect(rig.base.relay.calls(.putSnapshot).count == before + 1)
        #expect(rig.store.current?.manualRefreshResults.map(\.outcome) == [.codexRead])
    }

    @Test func acknowledgementWaitsForPublicationAndARepeatPollDoesNotReadAgain() async {
        let handler = rig.makeHandler()
        rig.base.relay.queuePut(.offline)
        let failed = await handler.handle(pending: [rig.request(1)])
        guard case .publicationFailed(.backoff) = failed else {
            Issue.record("expected a failed publication, got \(failed)")
            return
        }
        #expect(rig.base.relay.calls(.deleteRefreshRequest).isEmpty)
        rig.clock.advance(by: 31)
        #expect(await handler.handle(pending: [rig.request(1)]) == .handled(count: 1))
        #expect(rig.codex.refreshCount == 1)
        #expect(rig.base.relay.calls(.deleteRefreshRequest).count == 1)
    }

    @Test func aRestartDoesNotReadAgain() async {
        _ = await rig.makeHandler().handle(pending: [rig.request(1)])
        rig.clock.advance(by: 40)
        _ = await rig.makeHandler().handle(pending: [rig.request(1)])
        #expect(rig.codex.refreshCount == 1)
    }

    @Test func resultsStayForTwoMinutesAndThenDrop() async throws {
        _ = await rig.makeHandler().handle(pending: [rig.request(1)])
        rig.clock.advance(by: 120)
        #expect(try await rig.collector.heartbeat().snapshot.manualRefreshResults.count == 1)
        rig.clock.advance(by: 1)
        #expect(try await rig.collector.heartbeat().snapshot.manualRefreshResults.isEmpty)
    }

    @Test func claudeCodeIsNeverRefreshedAndExpiredRequestsAreIgnored() async {
        let handler = rig.makeHandler()
        #expect(await handler.handle(pending: [rig.request(1, expires: 0)]) == .idle)
        _ = await handler.handle(pending: [rig.request(2)])
        #expect(rig.claude.refreshCount == 0)
        #expect(rig.codex.refreshCount == 1)
    }
}
