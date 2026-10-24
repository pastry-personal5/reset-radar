import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarTestSupport
import Testing

@testable import ResetRadarProviderAdapters

private struct CollectRig {
    let source: SourceRig
    let snapshots = FakeSnapshotStore()
    let collector: CollectUsage

    init(_ root: URL) {
        source = SourceRig(root)
        collector = CollectUsage(
            snapshots: snapshots, diagnostics: source.sink, clock: source.clock,
            catalogStore: FakeAccountCatalogStore(accounts: [
                AccountMetadata(id: collectionAccount, product: .claudeCode, number: 1)
            ]), publisherID: PublisherID(data: Data(repeating: 7, count: 32))!,
            heartbeatSeconds: 300)
    }

    func bothWindows(percent: Double, observed: TimeInterval = 999_000) throws {
        try store(
            sessionRecord(
                "s",
                windows: [
                    sessionWindow("five_hour", percent: percent, observed: observed),
                    sessionWindow("seven_day", percent: percent + 40, observed: observed),
                ]), in: source.file)
    }
}

@Suite("Claude Code source with CollectUsage")
struct ClaudeCodeCollectUsageTests {
    @Test func completeReportsReplaceWindowsAndDuplicateIngestionIsIdempotent() async throws {
        try await withAsyncTemporaryDirectory { root in
            let rig = CollectRig(root)
            try rig.bothWindows(percent: 10)
            let collector = UpdateCollector(rig.source.source.updates)
            try await rig.source.source.start()
            let streamed = try #require(await collector.waitForCount(1).first)
            let first = try await rig.collector.ingest(streamed)
            #expect(first.snapshot.windows.count == 2)
            #expect(first.snapshot.windows.allSatisfy { $0.scope == nil })
            #expect(first.snapshot.windows.allSatisfy { $0.product == .claudeCode })
            #expect(first.snapshot.windows.allSatisfy { $0.reportState == .reported })
            #expect(first.snapshot.sources.first?.providerScope == nil)
            #expect(first.snapshot.sources.first?.state == .reporting)
            // The same report through the receipt path changes nothing.
            let receipt = await rig.source.source.refresh()
            let again = try await rig.collector.ingest(try #require(receipt.report))
            #expect(again.change == .none)
            #expect(again.snapshot.windows == first.snapshot.windows)
            // A newer observation replaces both windows completely.
            try rig.bothWindows(percent: 20, observed: 999_500)
            let updated = try #require(await rig.source.source.refresh().report)
            let replaced = try await rig.collector.ingest(updated)
            #expect(
                replaced.snapshot.windows.map { $0.observation?.usedPercent }.sorted {
                    ($0 ?? 0) < ($1 ?? 0)
                } == [20, 60])
        }
    }

    @Test func missingKindsAreRetainedAndStateOnlyFailuresPreserveWindows() async throws {
        try await withAsyncTemporaryDirectory { root in
            let rig = CollectRig(root)
            try rig.bothWindows(percent: 10)
            try await rig.source.source.start()
            let complete = try #require(await rig.source.source.refresh().report)
            let base = try await rig.collector.ingest(complete)
            // A report that lacks seven_day keeps it, marked retained, with its old observation.
            let partial = SourceSnapshot(
                source: complete.source,
                windows: complete.windows.filter { $0.limitID == "five_hour" },
                isCompleteReport: true)
            let retained = try await rig.collector.ingest(partial)
            let seven = try #require(retained.snapshot.windows.first { $0.limitID == "seven_day" })
            #expect(seven.reportState == .retained)
            #expect(
                seven.observation
                    == base.snapshot.windows.first { $0.limitID == "seven_day" }?.observation)
            // A malformed record yields a state-only report that preserves every window.
            let bad = sessionRecord("bad")
            try store(bad, in: rig.source.file)
            try Data("{\"schemaVersion\":9}".utf8).write(
                to: rig.source.file.directoryURL.appending(path: bad.key.fileName))
            let failed = try #require(await rig.source.source.refresh().report)
            #expect(!failed.isCompleteReport && failed.source.state == .incompatible)
            let preserved = try await rig.collector.ingest(failed)
            #expect(preserved.snapshot.windows == retained.snapshot.windows)
            #expect(preserved.snapshot.sources.first?.state == .incompatible)
        }
    }

    @Test func expiredRetainedWindowsFollowApplicationRules() async throws {
        try await withAsyncTemporaryDirectory { root in
            let rig = CollectRig(root)
            try store(
                sessionRecord(
                    "s",
                    windows: [
                        sessionWindow("five_hour", observed: 999_000, resets: 1_000_050),
                        sessionWindow("seven_day", observed: 999_000, resets: 2_000_000_000),
                        sessionWindow("seven_day_opus", observed: 999_000, resets: 1_000_050),
                    ]), in: rig.source.file)
            try await rig.source.source.start()
            let complete = try #require(await rig.source.source.refresh().report)
            _ = try await rig.collector.ingest(complete)
            rig.source.clock.advance(by: 120)
            let partial = SourceSnapshot(
                source: complete.source,
                windows: complete.windows.filter { $0.limitID == "seven_day" },
                isCompleteReport: true)
            let result = try await rig.collector.ingest(partial)
            // An unknown kind past its reset is dropped; the expired standard ring stays as a
            // retained entry that Home resolves to unavailable.
            #expect(result.snapshot.windows.map(\.limitID).sorted() == ["five_hour", "seven_day"])
            let five = try #require(result.snapshot.windows.first { $0.limitID == "five_hour" })
            #expect(five.reportState == .retained)
            #expect(try #require(five.resetsAt) <= rig.source.clock.now)
            #expect(result.snapshot.windows.allSatisfy { $0.scope == nil })
        }
    }
}
