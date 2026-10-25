import Darwin
import Foundation
import ResetRadarDomain
import Testing

@testable import ResetRadarProviderAdapters

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ start: TimeInterval) { value = Date(timeIntervalSince1970: start) }
    var now: Date { lock.withLock { value } }
    func set(_ seconds: TimeInterval) {
        lock.withLock { value = Date(timeIntervalSince1970: seconds) }
    }
}

private func recorder(_ root: URL, _ clock: TestClock) -> (SessionRecordFile, StatusLineRecorder) {
    let file = SessionRecordFile(rootDirectory: root.appending(path: "ResetRadar"))
    return (file, StatusLineRecorder(file: file, clock: { clock.now }))
}

private func rate(_ kinds: [(String, String)]) -> String {
    "{" + kinds.map { "\"\($0.0)\":\(windowJSON($0.1))" }.joined(separator: ",") + "}"
}

@Suite("Claude Code status-line recorder")
struct StatusLineRecorderTests {
    @Test func firstAppearanceStampsObservationThenIdleRedrawsKeepIt() throws {
        try withTemporaryDirectory { root in
            let clock = TestClock(1_000)
            let (file, recorder) = recorder(root, clock)
            let first = try recorder.record(
                decoded(statusPayload(rateLimits: rate([("five_hour", "10")]))))
            #expect(first.windows.map(\.observedAt) == [Date(timeIntervalSince1970: 1_000)])
            clock.set(2_000)
            // Same counter: an idle redraw, with a changed value.
            let idle = try recorder.record(
                decoded(statusPayload(rateLimits: rate([("five_hour", "11")]))))
            #expect(idle.windows[0].observedAt == Date(timeIntervalSince1970: 1_000))
            #expect(idle.windows[0].usedPercent == 11)
            #expect(idle.lastInvokedAt == Date(timeIntervalSince1970: 2_000))
            clock.set(3_000)
            let active = try recorder.record(
                decoded(
                    statusPayload(
                        cost: "{\"total_api_duration_ms\":2000}",
                        rateLimits: rate([("five_hour", "12")]))))
            #expect(active.windows[0].observedAt == Date(timeIntervalSince1970: 3_000))
            #expect(try file.read(key: active.key) == active)
        }
    }

    @Test func missingActivityNeverAdvancesAfterAReading() throws {
        try withTemporaryDirectory { root in
            let clock = TestClock(1_000)
            let (_, recorder) = recorder(root, clock)
            _ = try recorder.record(
                decoded(statusPayload(cost: nil, rateLimits: rate([("five_hour", "1")]))))
            clock.set(5_000)
            let later = try recorder.record(
                decoded(statusPayload(cost: nil, rateLimits: rate([("five_hour", "9")]))))
            #expect(later.windows[0].observedAt == Date(timeIntervalSince1970: 1_000))
            // Activity first appearing establishes a baseline; it is not an increase.
            clock.set(6_000)
            let baseline = try recorder.record(
                decoded(statusPayload(rateLimits: rate([("five_hour", "9")]))))
            #expect(baseline.windows[0].observedAt == Date(timeIntervalSince1970: 1_000))
            #expect(baseline.lastActivity == 1_000)
        }
    }

    @Test func droppedWindowsAreRetainedAndMissingLimitsNeverErase() throws {
        try withTemporaryDirectory { root in
            let clock = TestClock(1_000)
            let (_, recorder) = recorder(root, clock)
            _ = try recorder.record(
                decoded(
                    statusPayload(rateLimits: rate([("five_hour", "10"), ("seven_day", "20")]))))
            clock.set(2_000)
            let dropped = try recorder.record(
                decoded(
                    statusPayload(
                        cost: "{\"total_api_duration_ms\":2000}",
                        rateLimits: rate([("seven_day", "21")]))))
            let byKind = Dictionary(uniqueKeysWithValues: dropped.windows.map { ($0.kind, $0) })
            #expect(byKind["five_hour"]?.reportState == .retained)
            #expect(byKind["five_hour"]?.observedAt == Date(timeIntervalSince1970: 1_000))
            #expect(byKind["seven_day"]?.reportState == .reported)
            clock.set(3_000)
            let none = try recorder.record(
                decoded(statusPayload(cost: "{\"total_api_duration_ms\":2000}", rateLimits: nil)))
            #expect(none.windows.count == 2)
            #expect(none.windows.allSatisfy { $0.reportState == .retained })
            clock.set(4_000)
            let back = try recorder.record(
                decoded(
                    statusPayload(
                        cost: "{\"total_api_duration_ms\":3000}",
                        rateLimits: rate([("five_hour", "5"), ("seven_day", "22")]))))
            #expect(back.windows.allSatisfy { $0.reportState == .reported })
            #expect(back.windows.allSatisfy { $0.observedAt == Date(timeIntervalSince1970: 4_000) })
        }
    }

    @Test func newKindWithoutASignalIsNotAddedUntilOneArrives() throws {
        try withTemporaryDirectory { root in
            let clock = TestClock(1_000)
            let (_, recorder) = recorder(root, clock)
            _ = try recorder.record(
                decoded(statusPayload(rateLimits: rate([("five_hour", "10")]))))
            clock.set(2_000)
            let unsignaled = try recorder.record(
                decoded(
                    statusPayload(
                        rateLimits: rate([("five_hour", "10"), ("seven_day", "5")]))))
            #expect(unsignaled.windows.map(\.kind) == ["five_hour"])
            clock.set(3_000)
            let signaled = try recorder.record(
                decoded(
                    statusPayload(
                        cost: "{\"total_api_duration_ms\":1500}",
                        rateLimits: rate([("five_hour", "10"), ("seven_day", "6")]))))
            #expect(signaled.windows.map(\.kind) == ["five_hour", "seven_day"])
        }
    }

    @Test func noWindowsYetKeepsTheNeverObservedAnchor() throws {
        try withTemporaryDirectory { root in
            let clock = TestClock(1_000)
            let (_, recorder) = recorder(root, clock)
            let record = try recorder.record(decoded(statusPayload(rateLimits: nil)))
            #expect(record.windows.isEmpty)
            #expect(!record.hasHadNormalWindows)
            #expect(record.pruneAnchor == Date(timeIntervalSince1970: 1_000))
            clock.set(2_000)
            let first = try recorder.record(
                decoded(
                    statusPayload(
                        cost: "{\"total_api_duration_ms\":2000}",
                        rateLimits: rate([("five_hour", "1")]))))
            #expect(first.windows[0].observedAt == Date(timeIntervalSince1970: 2_000))
            #expect(first.pruneAnchor == Date(timeIntervalSince1970: 2_000))
        }
    }

    @Test func versionProvenanceFollowsTheObservationNotTheLatestInvocation() throws {
        try withTemporaryDirectory { root in
            let clock = TestClock(1_000)
            let (_, recorder) = recorder(root, clock)
            _ = try recorder.record(
                decoded(
                    statusPayload(version: "2.0.0", rateLimits: rate([("five_hour", "1")]))))
            clock.set(2_000)
            let idle = try recorder.record(
                decoded(
                    statusPayload(version: "2.1.0", rateLimits: rate([("five_hour", "1")]))))
            #expect(idle.windows[0].sourceVersion == "2.0.0")
            clock.set(3_000)
            let active = try recorder.record(
                decoded(
                    statusPayload(
                        version: "2.1.0", cost: "{\"total_api_duration_ms\":9999}",
                        rateLimits: rate([("five_hour", "2")]))))
            #expect(active.windows[0].sourceVersion == "2.1.0")
        }
    }

    @Test func backwardClocksLeaveTheRecordUntouched() throws {
        try withTemporaryDirectory { root in
            let clock = TestClock(5_000)
            let (file, recorder) = recorder(root, clock)
            let record = try recorder.record(
                decoded(statusPayload(rateLimits: rate([("five_hour", "1")]))))
            let path = file.directoryURL.appending(path: record.key.fileName)
            let before = try Data(contentsOf: path)
            clock.set(4_999)
            #expect(throws: StatusLineRecorderError.clockRegressed) {
                try recorder.record(
                    decoded(
                        statusPayload(
                            cost: "{\"total_api_duration_ms\":5000}",
                            rateLimits: rate([("five_hour", "60")]))))
            }
            #expect(try Data(contentsOf: path) == before)
            // An equal clock is accepted.
            clock.set(5_000)
            _ = try recorder.record(
                decoded(statusPayload(rateLimits: rate([("five_hour", "1")]))))
        }
    }

    @Test func decreasedActivityResetsTheBaselineWithoutAdvancingObservation() throws {
        try withTemporaryDirectory { root in
            let clock = TestClock(5_000)
            let (_, recorder) = recorder(root, clock)
            func record(_ millis: Int, _ percent: String) throws -> SessionRecord {
                try recorder.record(
                    decoded(
                        statusPayload(
                            cost: "{\"total_api_duration_ms\":\(millis)}",
                            rateLimits: rate([("five_hour", percent)]))))
            }
            _ = try record(500, "1")
            clock.set(6_000)
            let reset = try record(10, "50")
            #expect(reset.lastActivity == 10 && reset.windows[0].usedPercent == 50)
            #expect(reset.windows[0].observedAt == Date(timeIntervalSince1970: 5_000))
            clock.set(7_000)
            #expect(
                try record(20, "51").windows[0].observedAt == Date(timeIntervalSince1970: 7_000))
        }
    }

    @Test func recordsContainOnlyAllowlistedValues() throws {
        try withTemporaryDirectory { root in
            let clock = TestClock(1_000)
            let (file, recorder) = recorder(root, clock)
            let payload = statusPayload(
                cost: "{\"total_api_duration_ms\":42,\"total_cost_usd\":9.99}",
                rateLimits:
                    "{\"spend_limit\":{\"used_percentage\":777,\"currency\":\"SENTINEL-usd\"},"
                    + "\"five_hour\":\(windowJSON("3"))}",
                extra: "\"prompt\":\"\(sentinelPrompt)\",\"cwd\":\"/Users/SENTINEL-path\"")
            let record = try recorder.record(decoded(payload))
            let text = try String(
                contentsOf: file.directoryURL.appending(path: record.key.fileName),
                encoding: .utf8)
            for forbidden in [sentinelSessionID, sentinelPrompt, "SENTINEL", "777", "9.99", "cwd"] {
                #expect(!text.contains(forbidden), "\(forbidden)")
            }
            #expect(text.contains("\"schemaVersion\":1"))
            let allowed: Set<String> = [
                "schemaVersion", "key", "lastInvokedAtMs", "lastActivity", "hasHadNormalWindows",
                "windows", "kind", "usedPercent", "resetsAt", "observedAtMs", "sourceVersion",
                "retained",
            ]
            let object = try #require(
                JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
            #expect(Set(object.keys).isSubset(of: allowed))
        }
    }

    @Test func concurrentWritersNeverLoseTheNewestObservation() async throws {
        try await withAsyncTemporaryDirectory { root in
            let clock = TestClock(1_000)
            let (file, recorder) = recorder(root, clock)
            let key = SessionKey(sessionID: sentinelSessionID)
            _ = try recorder.record(decoded(statusPayload(rateLimits: rate([("five_hour", "1")]))))
            await withTaskGroup(of: Void.self) { group in
                for offset in 1...20 {
                    group.addTask {
                        let local = StatusLineRecorder(
                            file: file,
                            clock: { Date(timeIntervalSince1970: 1_000 + Double(offset)) })
                        let payload = statusPayload(
                            cost: "{\"total_api_duration_ms\":\(1_000 + offset)}",
                            rateLimits: rate([("five_hour", "\(offset)")]))
                        _ = try? local.record(decoded(payload))
                    }
                }
            }
            let stored = try #require(try file.read(key: key))
            // Whatever the interleaving, the counter and time never regressed.
            let counter = try #require(stored.lastActivity)
            let window = try #require(stored.windows.first)
            #expect(counter >= 1_001)
            #expect(window.observedAt <= stored.lastInvokedAt)
            #expect(stored.lastInvokedAt >= Date(timeIntervalSince1970: 1_001))
        }
    }
}

@Suite("Claude Code session record file")
struct SessionRecordFileTests {
    private func makeRecord(_ id: String = "s") -> SessionRecord {
        SessionRecord(
            key: SessionKey(sessionID: id), lastInvokedAt: Date(timeIntervalSince1970: 100),
            lastActivity: 5, hasHadNormalWindows: true,
            windows: [
                SessionWindow(
                    kind: "five_hour", usedPercent: 3.5,
                    resetsAt: Date(timeIntervalSince1970: 200),
                    observedAt: Date(timeIntervalSince1970: 100), sourceVersion: "2.1.0",
                    reportState: .reported)
            ])
    }

    @Test func codecRoundTripsAndRejectsStrictKeyAndSchemaViolations() throws {
        let record = makeRecord()
        let data = try SessionRecordCodec.encode(record)
        #expect(try SessionRecordCodec.decode(data) == record)
        let text = utf8String(data)
        let mutations = [
            text.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":2"),
            text.replacingOccurrences(
                of: "\"schemaVersion\":1", with: "\"schemaVersion\":1,\"extra\":1"),
            text.replacingOccurrences(
                of: "\"retained\":false", with: "\"retained\":false,\"prompt\":\"x\""),
            text.replacingOccurrences(of: "\"usedPercent\":3.5", with: "\"usedPercent\":300"),
            text.replacingOccurrences(of: "five_hour", with: "Five Hour"),
            text.replacingOccurrences(of: "\"windows\":[{", with: "\"windows\":[{\"kind\":\"x\","),
            "{}", "[]", "not json",
        ]
        for mutated in mutations {
            #expect(throws: SessionRecordError.incompatibleRecord) {
                try SessionRecordCodec.decode(Data(mutated.utf8))
            }
        }
        #expect(throws: SessionRecordError.recordTooLarge) {
            try SessionRecordCodec.decode(
                Data(repeating: 0x20, count: StatusLineLimits.maximumRecordBytes + 1))
        }
    }

    @Test func directoriesFilesAndLockAreOwnerOnlyAndSymlinksAreRefused() throws {
        try withTemporaryDirectory { root in
            let support = root.appending(path: "ResetRadar")
            let file = SessionRecordFile(rootDirectory: support)
            let record = makeRecord()
            try file.update(key: record.key) { _ in record }
            func mode(_ url: URL) -> mode_t {
                var metadata = Darwin.stat()
                precondition(lstat(url.path, &metadata) == 0)
                return metadata.st_mode & 0o777
            }
            #expect(mode(support) == 0o700)
            #expect(mode(file.directoryURL) == 0o700)
            #expect(mode(file.directoryURL.appending(path: record.key.fileName)) == 0o600)
            #expect(mode(file.directoryURL.appending(path: ".lock")) == 0o600)
            // A symlink in place of the record is refused rather than followed.
            let victim = root.appending(path: "victim.txt")
            try Data("untouched".utf8).write(to: victim)
            let other = makeRecord("other")
            try FileManager.default.createSymbolicLink(
                at: file.directoryURL.appending(path: other.key.fileName),
                withDestinationURL: victim)
            #expect(throws: SessionRecordError.unsafeLocation) {
                try file.read(key: other.key)
            }
            #expect(throws: SessionRecordError.unsafeLocation) {
                try file.update(key: other.key) { _ in other }
            }
            #expect(try Data(contentsOf: victim) == Data("untouched".utf8))
        }
    }

    @Test func unsafeModesAndIncompatibleFilesAreRejected() throws {
        try withTemporaryDirectory { root in
            let file = SessionRecordFile(rootDirectory: root.appending(path: "ResetRadar"))
            let record = makeRecord()
            try file.update(key: record.key) { _ in record }
            let path = file.directoryURL.appending(path: record.key.fileName)
            #expect(chmod(path.path, 0o644) == 0)
            #expect(throws: SessionRecordError.unsafeLocation) { try file.read(key: record.key) }
            #expect(chmod(path.path, 0o600) == 0)
            try Data("{\"schemaVersion\":9}".utf8).write(to: path)
            #expect(throws: SessionRecordError.incompatibleRecord) {
                try file.read(key: record.key)
            }
            #expect(try file.read(key: SessionKey(sessionID: "absent")) == nil)
            // A record stored under the wrong name is incompatible.
            let wrong = makeRecord("wrong")
            let wrongPath = file.directoryURL.appending(path: wrong.key.fileName)
            try SessionRecordCodec.encode(record).write(to: wrongPath)
            #expect(chmod(wrongPath.path, 0o600) == 0)
            #expect(throws: SessionRecordError.incompatibleRecord) {
                try file.read(key: wrong.key)
            }
        }
    }

    @Test func aHeldLockTimesOutInsteadOfBlockingForever() throws {
        try withTemporaryDirectory { root in
            let file = SessionRecordFile(rootDirectory: root.appending(path: "ResetRadar"))
            try file.prepare()
            let lockPath = file.directoryURL.appending(path: ".lock").path
            let descriptor = open(lockPath, O_RDWR | O_CREAT, 0o600)
            #expect(descriptor >= 0)
            defer { close(descriptor) }
            #expect(flock(descriptor, LOCK_EX) == 0)
            let started = Date()
            #expect(throws: SessionRecordError.unavailable) {
                try file.update(key: makeRecord().key) { _ in makeRecord() }
            }
            #expect(Date().timeIntervalSince(started) < 5)
        }
    }

    @Test func aReplacedDirectoryOrWideParentIsRefused() throws {
        try withTemporaryDirectory { root in
            let support = root.appending(path: "ResetRadar")
            #expect(mkdir(support.path, 0o777) == 0)
            #expect(chmod(support.path, 0o777) == 0)
            let file = SessionRecordFile(rootDirectory: support)
            #expect(throws: SessionRecordError.unsafeLocation) { try file.prepare() }
        }
    }
}
