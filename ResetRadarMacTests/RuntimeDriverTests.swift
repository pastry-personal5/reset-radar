import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarTestSupport
import Testing

@testable import ResetRadarMac

func runtimeSnapshot(at date: Date) throws -> UsageSnapshot {
    let account = AccountID(data: Data(repeating: 0x11, count: AccountID.byteCount))!
    let publisher = PublisherID(data: Data(repeating: 0x22, count: PublisherID.byteCount))!
    return try UsageSnapshot(
        publisherID: publisher, generatedAt: date, heartbeatSeconds: 300,
        accounts: [AccountMetadata(id: account, product: .codex, number: 1)],
        sources: [
            AccountSource(
                accountID: account, product: .codex, kind: .codexAppServer, version: "synthetic",
                state: .reporting)
        ], windows: [])
}

private actor RuntimeRecorder {
    var reports = 0
    var collections = 0
    var publishes: [PublishTrigger] = []
    var handled = 0

    func recordReport() { reports += 1 }
    func recordCollection() { collections += 1 }
    func recordPublish(_ trigger: PublishTrigger) { publishes.append(trigger) }
    func recordHandle() { handled += 1 }
}

private actor PublicationOutcomeQueue {
    private var pending: [PublishOutcome]
    private(set) var reported = [PublicationStatusEvent]()

    init(_ pending: [PublishOutcome]) { self.pending = pending }

    func next() -> PublishOutcome { pending.removeFirst() }
    func record(_ event: PublicationStatusEvent) { reported.append(event) }
}

@Suite("Collector runtime")
struct RuntimeDriverTests {
    @Test func normalLaunchIsLiveAndFlagSelectsSynthetic() {
        #expect(PublishingMode.selected(arguments: ["ResetRadarMac"]) == .live)
        #expect(
            PublishingMode.selected(arguments: ["ResetRadarMac", "--synthetic"]) == .synthetic)
    }

    @Test func sourceStartIngestionRefreshAndStop() async throws {
        let clock = FakeAppClock()
        let source = FakeUsageSource(product: .codex, clock: clock)
        let snapshot = try runtimeSnapshot(at: clock.now)
        let report = SourceSnapshot(
            source: snapshot.sources[0], windows: [], isCompleteReport: true)
        let recorder = RuntimeRecorder()
        let runtime = SourceRuntime(
            sources: [source],
            ingest: { _ in
                await recorder.recordReport()
                return CollectResult(snapshot: snapshot, change: .material)
            }, didCollect: { _ in await recorder.recordCollection() })
        await runtime.start()
        source.emit(report)
        for _ in 0..<100 {
            if await recorder.reports > 0 { break }
            await Task.yield()
        }
        await runtime.refresh(.wake)
        await runtime.stop()
        #expect(source.startCount == 1)
        #expect(source.refreshCount == 1)
        #expect(source.stopCount == 1)
        #expect(await recorder.reports == 1)
        #expect(await recorder.collections == 1)
    }

    @Test func publicationReplacesTimerAndWakePublishesImmediately() async throws {
        let clock = FakeAppClock()
        let snapshot = try runtimeSnapshot(at: clock.now)
        let recorder = RuntimeRecorder()
        let driver = PublicationDriver(
            clock: clock, loadSnapshot: { snapshot },
            publish: { _, _, trigger in
                await recorder.recordPublish(trigger)
                return .published(sequence: 1)
            })
        await driver.collected(CollectResult(snapshot: snapshot, change: .material))
        let first = await driver.scheduledDate
        #expect(first == clock.now.addingTimeInterval(PublicationPolicy.heartbeat))
        await driver.collected(CollectResult(snapshot: snapshot, change: .transition))
        #expect(await driver.scheduledDate == first)
        await driver.trigger(.wake)
        #expect(await recorder.publishes == [.change, .change, .wake])
        await driver.stop()
        #expect(await driver.scheduledDate == nil)
    }

    @Test func lifecycleSuspendsPublication() async throws {
        let clock = FakeAppClock()
        let snapshot = try runtimeSnapshot(at: clock.now)
        let recorder = RuntimeRecorder()
        let driver = PublicationDriver(
            clock: clock, loadSnapshot: { snapshot },
            publish: { _, _, trigger in
                await recorder.recordPublish(trigger)
                return .published(sequence: 1)
            })
        await driver.setSuspended(true)
        await driver.trigger(.networkRestored)
        #expect(await recorder.publishes.isEmpty)
        await driver.setSuspended(false)
        await driver.trigger(.networkRestored)
        #expect(await recorder.publishes == [.networkRestored])
        await driver.stop()
    }

    @Test func publicationReportsNewFailClosedReasonsAndRecoveryOnce() async throws {
        let clock = FakeAppClock()
        let snapshot = try runtimeSnapshot(at: clock.now)
        let queue = PublicationOutcomeQueue([
            .stopped(.authorizationRequired), .stopped(.authorizationRequired),
            .envelopeTooLarge, .envelopeTooLarge, .published(sequence: 1),
            .stopped(.snapshotConflict),
        ])
        let driver = PublicationDriver(
            clock: clock, loadSnapshot: { snapshot },
            publish: { _, _, _ in await queue.next() },
            reportOutcome: { await queue.record($0) })

        for _ in 0..<6 { await driver.trigger(.wake) }

        #expect(
            await queue.reported == [
                .blocked(.stopped(.authorizationRequired)), .blocked(.envelopeTooLarge),
                .recovered, .blocked(.stopped(.snapshotConflict)),
            ])
        await driver.stop()
    }

    @Test func manualPublicationFailureReportsReasonAndRecovery() async throws {
        let clock = FakeAppClock()
        let snapshot = try runtimeSnapshot(at: clock.now)
        let queue = PublicationOutcomeQueue([])
        let driver = PublicationDriver(
            clock: clock, loadSnapshot: { snapshot },
            publish: { _, _, _ in .notDue(next: nil) },
            reportOutcome: { await queue.record($0) })

        await driver.reportManualOutcome(.publicationFailed(.stopped(.payloadRejected)))
        await driver.reportManualOutcome(.publicationFailed(.stopped(.payloadRejected)))
        await driver.reportManualOutcome(.handled(count: 1))
        await driver.reportManualOutcome(.publicationFailed(.stopped(.payloadRejected)))

        #expect(
            await queue.reported == [
                .blocked(.stopped(.payloadRejected)), .recovered,
                .blocked(.stopped(.payloadRejected)),
            ])
        await driver.stop()
    }

    @Test func manualRequestsPollOnlyWhenRunnableAndCoalesceTicks() async {
        let recorder = RuntimeRecorder()
        let request = PendingRefreshRequest(
            id: RequestID(data: Data(repeating: 1, count: RequestID.byteCount))!,
            readerID: ReaderID(data: Data(repeating: 2, count: ReaderID.byteCount))!,
            target: .allCodex, expiresAt: Date().addingTimeInterval(60))
        let driver = ManualRequestDriver(
            poll: { [request] },
            handle: { _ in
                await recorder.recordHandle()
                try? await Task.sleep(for: .milliseconds(20))
                return .handled(count: 1)
            })
        await driver.update(ready: true, hasReaders: false, sleeping: false)
        await driver.tick()
        #expect(await recorder.handled == 0)
        await driver.update(ready: true, hasReaders: true, sleeping: false)
        async let first: Void = driver.tick()
        async let second: Void = driver.tick()
        _ = await (first, second)
        #expect(await recorder.handled == 1)
        await driver.update(ready: true, hasReaders: true, sleeping: true)
        await driver.tick()
        #expect(await recorder.handled == 1)
        await driver.wake()
        #expect(await recorder.handled == 2)
        await driver.stop()
    }

    @Test func manualPollingFollowsReaderChangesAndPreservesSleepAndSuspension() async {
        let recorder = RuntimeRecorder()
        let request = PendingRefreshRequest(
            id: RequestID(data: Data(repeating: 3, count: RequestID.byteCount))!,
            readerID: ReaderID(data: Data(repeating: 4, count: ReaderID.byteCount))!,
            target: .allCodex, expiresAt: Date().addingTimeInterval(60))
        let driver = ManualRequestDriver(
            poll: { [request] },
            handle: { _ in
                await recorder.recordHandle()
                return .handled(count: 1)
            })
        await driver.update(ready: true, hasReaders: false, sleeping: false)
        await driver.updateReadiness(ready: true, hasReaders: true)
        await driver.tick()
        #expect(await recorder.handled == 1)

        await driver.setSleeping(true)
        await driver.updateReadiness(ready: false, hasReaders: false)
        await driver.wake()
        #expect(await recorder.handled == 1)

        await driver.updateReadiness(ready: true, hasReaders: true)
        await driver.setSuspended(true)
        await driver.tick()
        #expect(await recorder.handled == 1)
        await driver.updateReadiness(ready: true, hasReaders: true)
        await driver.setSuspended(false)
        await driver.tick()
        #expect(await recorder.handled == 2)
        await driver.stop()
    }
}
