import Darwin
import Foundation
import ResetRadarDomain
import Testing

@testable import ResetRadarProviderAdapters

let collectionAccount = AccountID(data: Data(repeating: 0xC1, count: 16))!

func sessionWindow(
    _ kind: String = "five_hour", percent: Double = 10, observed: TimeInterval,
    resets: TimeInterval? = 2_000_000_000, version: String = "2.1.0",
    state: ReportState = .reported
) -> SessionWindow {
    SessionWindow(
        kind: kind, usedPercent: percent, resetsAt: resets.map { Date(timeIntervalSince1970: $0) },
        observedAt: Date(timeIntervalSince1970: observed), sourceVersion: version,
        reportState: state)
}

func sessionRecord(
    _ id: String, invoked: TimeInterval = 100, windows: [SessionWindow] = [],
    observedBefore: Bool? = nil
) -> SessionRecord {
    SessionRecord(
        key: SessionKey(sessionID: id), lastInvokedAt: Date(timeIntervalSince1970: invoked),
        lastActivity: 1, hasHadNormalWindows: observedBefore ?? !windows.isEmpty, windows: windows)
}

func store(_ record: SessionRecord, in file: SessionRecordFile) throws {
    try file.update(key: record.key) { _ in record }
}

@Suite("Claude Code session merge")
struct SessionMergerTests {
    private let merger = SessionMerger(accountID: collectionAccount)

    @Test func selectsEachKindsNewestObservationAcrossSessions() throws {
        let merged = try merger.merge([
            sessionRecord(
                "a",
                windows: [
                    sessionWindow("five_hour", percent: 10, observed: 100),
                    sessionWindow("seven_day", percent: 50, observed: 900),
                ]),
            sessionRecord("b", windows: [sessionWindow("five_hour", percent: 20, observed: 500)]),
        ])
        let byID = Dictionary(uniqueKeysWithValues: merged.windows.map { ($0.limitID, $0) })
        #expect(byID["five_hour"]?.observation?.usedPercent == 20)
        #expect(byID["seven_day"]?.observation?.usedPercent == 50)
        #expect(merged.windows.map(\.limitID) == ["five_hour", "seven_day"])
        #expect(merged.windows.allSatisfy { $0.accountID == collectionAccount })
        #expect(merged.windows.allSatisfy { $0.scope == nil && $0.isDefaultLimit })
        #expect(byID["five_hour"]?.durationMinutes == 300)
        #expect(byID["seven_day"]?.durationMinutes == 10_080)
        #expect(byID["five_hour"]?.observation?.fractionDigits == 1)
    }

    @Test func aMissingKindInOneSessionNeverErasesAnotherSessionsValue() throws {
        let merged = try merger.merge([
            sessionRecord("a", windows: [sessionWindow("seven_day", percent: 40, observed: 100)]),
            sessionRecord("b", windows: [sessionWindow("five_hour", percent: 5, observed: 900)]),
        ])
        #expect(merged.windows.count == 2)
    }

    @Test func aNewerReportedValueReplacesAnOlderRetainedOne() throws {
        let merged = try merger.merge([
            sessionRecord(
                "a", windows: [sessionWindow(percent: 10, observed: 100, state: .retained)]),
            sessionRecord("b", windows: [sessionWindow(percent: 30, observed: 200)]),
        ])
        #expect(merged.windows[0].reportState == .reported)
        #expect(merged.windows[0].observation?.usedPercent == 30)
    }

    @Test func unknownKindsKeepNoDuration() throws {
        let merged = try merger.merge([
            sessionRecord("a", windows: [sessionWindow("seven_day_opus", observed: 100)])
        ])
        #expect(merged.windows[0].durationMinutes == nil)
        #expect(merged.windows[0].limitID == "seven_day_opus")
    }

    @Test func exactTimeTiesAreResolvedByValueNotByOrder() throws {
        let reported = sessionWindow(observed: 100)
        let retained = sessionWindow(observed: 100, state: .retained)
        for order in [[reported, retained], [retained, reported]] {
            let merged = try merger.merge([
                sessionRecord("a", windows: [order[0]]), sessionRecord("b", windows: [order[1]]),
            ])
            #expect(merged.windows[0].reportState == .reported)
        }
        // Field-for-field equivalent entries collapse.
        let twin = try merger.merge([
            sessionRecord("a", windows: [reported]), sessionRecord("b", windows: [reported]),
        ])
        #expect(twin.windows.count == 1)
        // Every other disagreement is incompatible, whatever the order.
        let conflicts = [
            sessionWindow(percent: 11, observed: 100),
            sessionWindow(observed: 100, resets: 2_000_000_001),
            sessionWindow(observed: 100, version: "2.2.0"),
        ]
        for conflict in conflicts {
            for order in [[reported, conflict], [conflict, reported]] {
                #expect(throws: SessionMergeError.conflictingObservations) {
                    try merger.merge([
                        sessionRecord("a", windows: [order[0]]),
                        sessionRecord("b", windows: [order[1]]),
                    ])
                }
            }
        }
    }

    @Test func theSummaryVersionFollowsTheNewestObservationNotAnIdleUpgrade() throws {
        let merged = try merger.merge([
            sessionRecord(
                "a", invoked: 9_999, windows: [sessionWindow(observed: 100, version: "2.0.0")]),
            sessionRecord(
                "b",
                windows: [
                    sessionWindow("seven_day", observed: 50, version: "1.9.0"),
                    sessionWindow("five_hour", observed: 300, version: "2.1.0"),
                ]),
        ])
        #expect(merged.version == "2.1.0")
        #expect(
            merged.windows.first { $0.limitID == "five_hour" }?.observation?.sourceVersion
                == "2.1.0")
        #expect(try merger.merge([]).version == nil)
        #expect(try merger.merge([sessionRecord("a")]).windows.isEmpty)
    }

    @Test func mergeIsIndependentOfRecordOrder() throws {
        let records = (0..<5).map { index in
            sessionRecord(
                "s\(index)",
                windows: [sessionWindow(percent: Double(index), observed: TimeInterval(index))])
        }
        #expect(try merger.merge(records) == merger.merge(records.reversed()))
    }
}

@Suite("Claude Code record reader and pruner")
struct SessionReaderPrunerTests {
    private func file(_ root: URL) -> SessionRecordFile {
        SessionRecordFile(rootDirectory: root.appending(path: "ResetRadar"))
    }

    @Test func anAbsentDirectoryIsAnEmptyScanAndRecordsAreReadSorted() throws {
        try withTemporaryDirectory { root in
            let file = file(root)
            #expect(try SessionRecordReader(file: file).scan().isEmpty)
            for id in ["a", "b", "c"] { try store(sessionRecord(id), in: file) }
            let scanned = try SessionRecordReader(file: file).scan()
            #expect(scanned.count == 3)
            #expect(scanned.map(\.key.hex) == scanned.map(\.key.hex).sorted())
        }
    }

    @Test func unrelatedEntriesAreIgnoredAndNeverRead() throws {
        try withTrustedHome { home in
            let file = file(home)
            try store(sessionRecord("a"), in: file)
            try Data("garbage".utf8).write(to: file.directoryURL.appending(path: "notes.txt"))
            try Data("garbage".utf8).write(to: file.directoryURL.appending(path: ".tmp-123"))
            try Data("{}".utf8).write(
                to: file.directoryURL.appending(path: "NOTHEX0000000000000000000000000000.json"))
            try FileManager.default.createDirectory(
                at: file.directoryURL.appending(path: "subdir"), withIntermediateDirectories: false)
            #expect(try SessionRecordReader(file: file).scan().count == 1)
        }
    }

    @Test func oneBadRecognizedRecordFailsTheWholeScan() throws {
        try withTemporaryDirectory { root in
            let file = file(root)
            try store(sessionRecord("good"), in: file)
            let bad = sessionRecord("bad")
            try store(bad, in: file)
            let path = file.directoryURL.appending(path: bad.key.fileName)
            try Data("{\"schemaVersion\":7}".utf8).write(to: path)
            #expect(throws: SessionScanError.incompatible) {
                try SessionRecordReader(file: file).scan()
            }
            try FileManager.default.removeItem(at: path)
            try store(bad, in: file)
            #expect(chmod(path.path, 0o644) == 0)
            #expect(throws: SessionScanError.incompatible) {
                try SessionRecordReader(file: file).scan()
            }
            #expect(chmod(path.path, 0o600) == 0)
            let link = file.directoryURL.appending(path: SessionKey(sessionID: "link").fileName)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: path)
            #expect(throws: SessionScanError.incompatible) {
                try SessionRecordReader(file: file).scan()
            }
        }
    }

    @Test func recordAndEntryBoundsAreExact() throws {
        try withTemporaryDirectory { root in
            let file = file(root)
            for id in ["a", "b", "c"] { try store(sessionRecord(id), in: file) }
            #expect(
                try SessionRecordReader(file: file, maximumRecords: 3, maximumEntries: 100).scan()
                    .count == 3)
            #expect(throws: SessionScanError.incompatible) {
                try SessionRecordReader(file: file, maximumRecords: 2, maximumEntries: 100).scan()
            }
            // The fixed lock file counts as an entry, so 3 records + .lock = 4 visited.
            #expect(throws: Never.self) {
                try SessionRecordReader(file: file, maximumRecords: 10, maximumEntries: 4).scan()
            }
            #expect(throws: SessionScanError.incompatible) {
                try SessionRecordReader(file: file, maximumRecords: 10, maximumEntries: 3).scan()
            }
        }
    }

    @Test func prunesObservedAndNeverObservedRecordsAtTheEightDayBoundary() throws {
        try withTemporaryDirectory { root in
            let file = file(root)
            let day: TimeInterval = 86_400
            let now = Date(timeIntervalSince1970: 1_000_000_000)
            let oldObserved = sessionRecord(
                "old", invoked: 1_000_000_000 - 1,
                windows: [sessionWindow(observed: 1_000_000_000 - 8 * day - 1)])
            let edgeObserved = sessionRecord(
                "edge", windows: [sessionWindow(observed: 1_000_000_000 - 8 * day)])
            let freshObserved = sessionRecord(
                "fresh", windows: [sessionWindow(observed: 1_000_000_000 - day)])
            // Invoked recently but observed long ago: the observation anchors pruning.
            let oldNeverObserved = sessionRecord("never-old", invoked: 1_000_000_000 - 9 * day)
            let freshNeverObserved = sessionRecord("never-fresh", invoked: 1_000_000_000 - day)
            let future = sessionRecord("future", invoked: 1_000_000_000 + 99 * day)
            for record in [
                oldObserved, edgeObserved, freshObserved, oldNeverObserved, freshNeverObserved,
                future,
            ] { try store(record, in: file) }
            #expect(try SessionPruner(file: file).prune(now: now) == 2)
            let remaining = Set(try SessionRecordReader(file: file).scan().map(\.key))
            #expect(
                remaining
                    == Set([edgeObserved, freshObserved, freshNeverObserved, future].map(\.key)))
        }
    }

    @Test func aFreshWriteBetweenEnumerationAndDeletionIsNeverDeleted() throws {
        try withTemporaryDirectory { root in
            let file = file(root)
            let now = Date(timeIntervalSince1970: 1_000_000_000)
            try store(sessionRecord("s", windows: [sessionWindow(observed: 1)]), in: file)
            let key = SessionKey(sessionID: "s")
            // The pruner rereads under the lock, so a record refreshed before deletion survives.
            try store(
                sessionRecord("s", windows: [sessionWindow(observed: 1_000_000_000 - 10)]),
                in: file)
            #expect(try SessionPruner(file: file).prune(now: now) == 0)
            #expect(try file.read(key: key) != nil)
        }
    }

    @Test func pruningNeverTouchesUnrelatedOrUnreadableFiles() throws {
        try withTrustedHome { home in
            let file = file(home)
            try file.prepare()
            let bystander = file.directoryURL.appending(path: "keep.txt")
            try Data("keep".utf8).write(to: bystander)
            let bad = sessionRecord("bad")
            try store(bad, in: file)
            try Data("{\"schemaVersion\":9}".utf8).write(
                to: file.directoryURL.appending(path: bad.key.fileName))
            #expect(try SessionPruner(file: file).prune(now: Date(timeIntervalSince1970: 9e9)) == 0)
            #expect(FileManager.default.fileExists(atPath: bystander.path))
            #expect(
                FileManager.default.fileExists(
                    atPath: file.directoryURL.appending(path: bad.key.fileName).path))
        }
    }
}
