import Darwin
import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarTestSupport
import Testing

@testable import ResetRadarProviderAdapters

@Suite("Claude Code source")
struct ClaudeCodeSourceTests {
    @Test func notConfiguredEmitsOneUnavailableStateAndRefreshStaysUnavailable() async throws {
        try await withAsyncTemporaryDirectory { root in
            let rig = SourceRig(root)
            rig.probe.set(.notConfigured)
            let collector = UpdateCollector(rig.source.updates)
            try await rig.source.start()
            let updates = await collector.waitForCount(1)
            #expect(updates.count == 1)
            #expect(updates[0].source.state == .unavailable)
            #expect(updates[0].source.version == ClaudeCodeSource.unobservedVersion)
            #expect(updates[0].source.providerScope == nil)
            #expect(updates[0].windows.isEmpty && !updates[0].isCompleteReport)
            #expect(await rig.source.refresh() == .unavailable(sourceState: .unavailable))
            #expect(await rig.source.refresh() == .unavailable(sourceState: .unavailable))
            #expect(await collector.updates.count == 1)
            #expect(rig.factory.sessions.isEmpty)
            #expect(
                rig.sink.recorded.map(\.providerFailureClass) == [
                    .notInstalled, .notInstalled, .notInstalled,
                ])
            // Installing later activates collection.
            try rig.record(25)
            rig.probe.set(.ready)
            await rig.source.configurationChanged()
            let after = await collector.waitForCount(2)
            #expect(after[1].source.state == .reporting)
            #expect(after[1].windows.first?.observation?.usedPercent == 25)
            #expect(rig.factory.sessions.count == 1)
        }
    }

    @Test func aMismatchedHelperIsUnavailableToo() async throws {
        try await withAsyncTemporaryDirectory { root in
            let rig = SourceRig(root)
            rig.probe.set(.helperUnavailable)
            try await rig.source.start()
            #expect(await rig.source.refresh() == .unavailable(sourceState: .unavailable))
            #expect(rig.factory.sessions.isEmpty)
        }
    }

    @Test func theWatchIsArmedBeforeTheInitialScan() async throws {
        try await withAsyncTemporaryDirectory { root in
            let rig = SourceRig(root)
            let file = rig.file
            // A record that lands exactly when the watch is armed must be in the first scan.
            rig.factory.onWatch {
                try? store(
                    sessionRecord(
                        "racer", windows: [sessionWindow(percent: 42, observed: 999_000)]),
                    in: file)
            }
            let collector = UpdateCollector(rig.source.updates)
            try await rig.source.start()
            let updates = await collector.waitForCount(1)
            #expect(updates[0].source.state == .reporting)
            #expect(updates[0].windows.first?.observation?.usedPercent == 42)
            #expect(rig.factory.sessions.count == 1)
            #expect(await rig.source.scanCount == 1)
        }
    }

    @Test func noUsableReadingYetIsUnavailableThenEventsCoalesceIntoOneScan() async throws {
        try await withAsyncTemporaryDirectory { root in
            let rig = SourceRig(root)
            let collector = UpdateCollector(rig.source.updates)
            try await rig.source.start()
            let first = await collector.waitForCount(1)
            #expect(first[0].source.state == .unavailable)
            #expect(rig.sink.recorded.isEmpty)
            #expect(await rig.source.scanCount == 1)
            try rig.record(10)
            let watch = try #require(rig.factory.current)
            for _ in 0..<50 { watch.send(.changed) }
            await rig.clock.waitForSleepers(1)
            rig.clock.advance(by: 1.9)
            try await Task.sleep(for: .milliseconds(50))
            #expect(await rig.source.scanCount == 1)
            rig.clock.advance(by: 0.2)
            let updates = await collector.waitForCount(2)
            #expect(updates[1].source.state == .reporting)
            #expect(await rig.source.scanCount == 2)
            #expect(rig.clock.sleeperCount == 0)
        }
    }

    @Test func anUnchangedProjectionEmitsNothingButRefreshStillReturnsTheReport() async throws {
        try await withAsyncTemporaryDirectory { root in
            let rig = SourceRig(root)
            try rig.record(10)
            let collector = UpdateCollector(rig.source.updates)
            try await rig.source.start()
            let first = await collector.waitForCount(1)
            let receipt = await rig.source.refresh()
            #expect(receipt.performedSuccessfully)
            #expect(receipt.report == first[0])
            try await Task.sleep(for: .milliseconds(50))
            #expect(await collector.updates.count == 1)
            try rig.record(11, observed: 999_500)
            let changed = await rig.source.refresh()
            #expect(changed.report?.windows.first?.observation?.usedPercent == 11)
            #expect(await collector.waitForCount(2).count == 2)
        }
    }

    @Test func simultaneousRefreshCallersShareOnePhysicalScanAndReceipt() async throws {
        try await withAsyncTemporaryDirectory { root in
            let rig = SourceRig(root)
            try rig.record(10)
            try await rig.source.start()
            let before = await rig.source.scanCount
            async let one = rig.source.refresh()
            async let two = rig.source.refresh()
            async let three = rig.source.refresh()
            let receipts = await [one, two, three]
            #expect(receipts[0] == receipts[1] && receipts[1] == receipts[2])
            #expect(await rig.source.scanCount <= before + 2)
            #expect(await rig.source.scanCount >= before + 1)
        }
    }

    @Test func malformedRecordsAndConflictsAreIncompatibleAndRecover() async throws {
        try await withAsyncTemporaryDirectory { root in
            let rig = SourceRig(root)
            try rig.record(10)
            let collector = UpdateCollector(rig.source.updates)
            try await rig.source.start()
            _ = await collector.waitForCount(1)
            let bad = sessionRecord("bad")
            try store(bad, in: rig.file)
            try Data("{\"schemaVersion\":9}".utf8).write(
                to: rig.file.directoryURL.appending(path: bad.key.fileName))
            let receipt = await rig.source.refresh()
            #expect(!receipt.performedSuccessfully)
            #expect(receipt.report?.source.state == .incompatible)
            #expect(receipt.report?.windows.isEmpty == true)
            #expect(rig.sink.recorded.last?.providerFailureClass == .malformed)
            // A repeated failed attempt is diagnosed again but not republished.
            _ = await rig.source.refresh()
            #expect(await collector.updates.count == 2)
            #expect(rig.sink.recorded.count == 2)
            try FileManager.default.removeItem(
                at: rig.file.directoryURL.appending(path: bad.key.fileName))
            let healed = await rig.source.refresh()
            #expect(healed.report?.source.state == .reporting)
            // Two sessions disagreeing at the same instant are incompatible.
            try store(
                sessionRecord("x", windows: [sessionWindow(percent: 1, observed: 999_000)]),
                in: rig.file)
            try store(
                sessionRecord("y", windows: [sessionWindow(percent: 2, observed: 999_000)]),
                in: rig.file)
            try store(sessionRecord("s"), in: rig.file)
            let conflict = await rig.source.refresh()
            #expect(conflict.report?.source.state == .incompatible)
            #expect(rig.sink.recorded.last?.providerFailureClass == .incompatible)
        }
    }

    @Test func watcherFailuresAreOfflineWithTheBackoffLadderAndDeferredRefreshes() async throws {
        try await withAsyncTemporaryDirectory { root in
            let rig = SourceRig(root)
            try rig.record(10)
            rig.factory.failNext(
                .unavailable, .unavailable, .unavailable, .unavailable, .unavailable)
            let collector = UpdateCollector(rig.source.updates)
            try await rig.source.start()
            let first = await collector.waitForCount(1)
            #expect(first[0].source.state == .sourceOffline)
            #expect(rig.sink.recorded.last?.providerFailureClass == .temporarilyUnavailable)
            for delay in [60.0, 120, 300, 900, 900] {
                let deferred = await rig.source.refresh()
                guard case .deferred(let retryAt, let state) = deferred else {
                    Issue.record("expected a deferred receipt")
                    return
                }
                #expect(state == .sourceOffline)
                #expect(retryAt.timeIntervalSince(rig.clock.now) == delay)
                await rig.clock.waitForSleepers(1)
                rig.clock.set(retryAt)
                try await Task.sleep(for: .milliseconds(80))
            }
            // Fifth retry succeeded (the six attempts consumed five failures).
            let recovered = await collector.waitForCount(2)
            #expect(recovered.last?.source.state == .reporting)
            #expect(rig.factory.sessions.count == 1)
        }
    }

    @Test func permissionDeniedIsOfflineAndDiagnosedAsSuch() async throws {
        try await withAsyncTemporaryDirectory { root in
            let rig = SourceRig(root)
            rig.factory.failNext(.permissionDenied)
            let collector = UpdateCollector(rig.source.updates)
            try await rig.source.start()
            let updates = await collector.waitForCount(1)
            #expect(updates[0].source.state == .sourceOffline)
            #expect(rig.sink.recorded.last?.providerFailureClass == .permissionDenied)
        }
    }

    @Test func aReplacedRootInvalidatesTheGenerationAndFencesOldCallbacks() async throws {
        try await withAsyncTemporaryDirectory { root in
            let rig = SourceRig(root)
            try rig.record(10)
            let collector = UpdateCollector(rig.source.updates)
            try await rig.source.start()
            _ = await collector.waitForCount(1)
            let old = try #require(rig.factory.current)
            old.send(.rootInvalidated)
            let offline = await collector.waitForCount(2)
            #expect(offline[1].source.state == .sourceOffline)
            #expect(old.cancelled)
            let scans = await rig.source.scanCount
            old.send(.changed)
            await rig.clock.waitForSleepers(1)  // only the revalidation timer
            try await Task.sleep(for: .milliseconds(50))
            #expect(await rig.source.scanCount == scans)
            // After the backoff a new generation is armed before rescanning.
            rig.clock.advance(by: 60)
            let healed = await collector.waitForCount(3)
            #expect(healed[2].source.state == .reporting)
            #expect(rig.factory.sessions.count == 2)
            #expect(rig.factory.current !== old)
        }
    }
}
