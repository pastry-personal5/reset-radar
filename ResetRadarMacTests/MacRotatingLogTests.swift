import Foundation
import ResetRadarDomain
import Testing

@testable import ResetRadarMac

@Suite("Mac rotating troubleshooting log")
struct MacRotatingLogTests {
    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value) ?? .distantPast
    }

    private func segmentNames(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".jsonl") }.sorted()
    }

    @Test func buildFlavorsHaveSeparateAgentReadableLocationsAndOSLogSubsystems() {
        let development = MacBuildFlavor.development
        let release = MacBuildFlavor.release
        #expect(development.logDirectory.lastPathComponent == "ResetRadar.dev")
        #expect(release.logDirectory.lastPathComponent == "ResetRadar")
        #expect(development.logDirectory.deletingLastPathComponent().lastPathComponent == "Logs")
        #expect(development.logSubsystem != release.logSubsystem)
    }

    @Test func writesRedactedTypedLinesWithOwnerOnlyPermissions() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = MacBuildFlavor.test(root: root).logDirectory
        let log = MacRotatingLog(directoryURL: directory, subsystem: "test")
        let now = date("2026-10-25T12:00:00Z")
        guard let account = AccountID(data: Data(repeating: 0x7A, count: AccountID.byteCount))
        else {
            Issue.record("Could not create test account ID")
            return
        }
        let event = DiagnosticEvent.providerFailure(
            .permissionDenied, accountID: account, product: .codex, at: now)
        #expect(await log.record(.diagnostic(event), at: now))
        #expect(await log.record(.startupFailure(.unsafeSourceLocation), at: now))
        let files = try segmentNames(in: directory)
        #expect(files == ["events-2026-10-25-0.jsonl"])
        let contents = try String(contentsOf: directory.appending(path: files[0]), encoding: .utf8)
        let lines = contents.split(separator: "\n")
        #expect(lines.count == 2)
        let objects = try lines.map { line in
            try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        }
        #expect(objects[0]["event"] as? String == "diagnostic.providerFailure")
        #expect(objects[0]["reason"] as? String == "permissionDenied")
        #expect(objects[1]["reason"] as? String == "unsafeSourceLocation")
        for object in objects {
            #expect(object["accountID"] == nil)
            #expect(object["product"] == nil)
            #expect(object["path"] == nil)
            #expect(object["usage"] == nil)
            #expect(object["secret"] == nil)
        }
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        let fileAttributes = try FileManager.default.attributesOfItem(
            atPath: directory.appending(path: files[0]).path)
        #expect((directoryAttributes[.posixPermissions] as? Int) == 0o700)
        #expect((fileAttributes[.posixPermissions] as? Int) == 0o600)
    }

    @Test func retainsEightUtcDaysAndBoundsSizeSegmentsAcrossRestarts() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = MacBuildFlavor.test(root: root).logDirectory
        let log = MacRotatingLog(
            directoryURL: directory, subsystem: "test", maximumSegmentBytes: 256,
            maximumSegmentsPerDay: 2)
        for day in 16...25 {
            let now = date(String(format: "2026-10-%02dT12:00:00Z", day))
            #expect(await log.record(.lifecycle(.ready), at: now))
        }
        let today = date("2026-10-25T12:00:00Z")
        for _ in 0..<8 {
            #expect(await log.record(.startupFailure(.publisherIO), at: today))
        }
        let restarted = MacRotatingLog(
            directoryURL: directory, subsystem: "test", maximumSegmentBytes: 256,
            maximumSegmentsPerDay: 2)
        #expect(await restarted.record(.lifecycle(.ready), at: today))
        let files = try segmentNames(in: directory)
        #expect(!files.contains { $0.contains("2026-10-16") || $0.contains("2026-10-17") })
        #expect(files.contains { $0.contains("2026-10-18") })
        #expect(files.filter { $0.contains("2026-10-25") }.count <= 2)
        for file in files {
            let attributes = try FileManager.default.attributesOfItem(
                atPath: directory.appending(path: file).path)
            #expect((attributes[.size] as? Int ?? 0) <= 256)
        }
    }

    @Test func refusesUnsafeLogDirectory() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let directory = root.appending(path: "Logs")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o755])
        let log = MacRotatingLog(directoryURL: directory, subsystem: "test")
        #expect(!(await log.record(.lifecycle(.starting))))
        #expect(try segmentNames(in: directory).isEmpty)
    }
}
