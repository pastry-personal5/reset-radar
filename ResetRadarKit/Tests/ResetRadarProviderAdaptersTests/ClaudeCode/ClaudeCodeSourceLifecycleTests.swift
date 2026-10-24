import Darwin
import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarTestSupport
import Testing

@testable import ResetRadarProviderAdapters

@Suite("Claude Code source lifecycle")
struct ClaudeCodeSourceLifecycleTests {
    @Test func stopIsTerminalIdempotentAndFencesLateWork() async throws {
        try await withAsyncTemporaryDirectory { root in
            let rig = SourceRig(root)
            try rig.record(10)
            let collector = UpdateCollector(rig.source.updates)
            try await rig.source.start()
            _ = await collector.waitForCount(1)
            let watch = try #require(rig.factory.current)
            await rig.source.stop()
            await rig.source.stop()
            #expect(watch.cancelled)
            let scans = await rig.source.scanCount
            watch.send(.changed)
            try await Task.sleep(for: .milliseconds(30))
            #expect(await rig.source.scanCount == scans)
            #expect(await rig.source.refresh() == .unavailable(sourceState: .unavailable))
            await #expect(throws: ClaudeCodeSourceError.stopped) { try await rig.source.start() }
            #expect(rig.factory.sessions.count == 1)
            var count = 0
            for await _ in rig.source.updates { count += 1 }
            #expect(count <= 1)
        }
    }

    @Test func startIsIdempotentAndPrunesStaleRecords() async throws {
        try await withAsyncTemporaryDirectory { root in
            let rig = SourceRig(root)
            try rig.record(10)
            try store(
                sessionRecord("ancient", invoked: 1, windows: [sessionWindow(observed: 1)]),
                in: rig.file)
            try await rig.source.start()
            try await rig.source.start()
            #expect(rig.factory.sessions.count == 1)
            let remaining = try SessionRecordReader(file: rig.file).scan()
            #expect(remaining.map(\.key) == [SessionKey(sessionID: "s")])
        }
    }

    @Test func stopDuringTheInstallationProbeNeverArmsAWatchOrDiagnoses() async throws {
        try await withAsyncTemporaryDirectory { root in
            let rig = SourceRig(root)
            let gate = GatedProbe()
            let source = ClaudeCodeSource(
                accountID: collectionAccount, file: rig.file, watchFactory: rig.factory,
                probe: gate, diagnostics: rig.sink, clock: rig.clock)
            let starting = Task { try await source.start() }
            try await Task.sleep(for: .milliseconds(50))
            await source.stop()
            gate.open()
            try await starting.value
            #expect(rig.factory.sessions.isEmpty)
            #expect(rig.sink.recorded.isEmpty)
            #expect(await source.scanCount == 0)
        }
    }

    @Test func anUnsafeRootIsReportedOnceThenRearmedByTheNextRefresh() async throws {
        try await withAsyncTemporaryDirectory { root in
            let rig = SourceRig(root)
            let support = root.appending(path: "ResetRadar")
            #expect(mkdir(support.path, 0o700) == 0)
            #expect(chmod(support.path, 0o777) == 0)
            let collector = UpdateCollector(rig.source.updates)
            try await rig.source.start()
            let first = await collector.waitForCount(1)
            #expect(first[0].source.state == .incompatible)
            #expect(rig.sink.recorded.count == 1)
            #expect(rig.factory.sessions.isEmpty)
            #expect(chmod(support.path, 0o700) == 0)
            try rig.record(33)
            let receipt = await rig.source.refresh()
            #expect(receipt.report?.source.state == .reporting)
            // The repaired directory is watched again, not only rescanned.
            #expect(rig.factory.sessions.count == 1)
        }
    }
}
