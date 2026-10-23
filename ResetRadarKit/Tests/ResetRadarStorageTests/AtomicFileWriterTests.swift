import Foundation
import Testing

@testable import ResetRadarStorage

struct AtomicFileWriterTests {
    private struct Injected: Error {}

    @Test func replacesTheFileWhole() throws {
        let directory = TemporaryDirectory()
        let file = directory.url.appending(path: "value.json")
        let writer = AtomicFileWriter(protection: .ownerOnly)
        try writer.write(Data("one".utf8), to: file)
        try writer.write(Data("two".utf8), to: file)
        #expect(try Data(contentsOf: file) == Data("two".utf8))
    }

    @Test func failureBeforeRenameKeepsPreviousBytesAndNoPartialTarget() throws {
        let directory = TemporaryDirectory()
        let file = directory.url.appending(path: "value.json")
        try AtomicFileWriter(protection: .ownerOnly).write(Data("old".utf8), to: file)
        let failing = AtomicFileWriter(protection: .ownerOnly, beforeRename: { throw Injected() })
        #expect(throws: StorageError.self) { try failing.write(Data("new".utf8), to: file) }
        #expect(try Data(contentsOf: file) == Data("old".utf8))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.url.path)
        #expect(leftovers == ["value.json"])
    }

    @Test func failureOnFirstWriteLeavesNoTarget() throws {
        let directory = TemporaryDirectory()
        let file = directory.url.appending(path: "value.json")
        let failing = AtomicFileWriter(protection: .ownerOnly, beforeRename: { throw Injected() })
        #expect(throws: StorageError.self) { try failing.write(Data("new".utf8), to: file) }
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func leftoverTemporaryFileDoesNotBlockTheNextWrite() throws {
        let directory = TemporaryDirectory()
        let file = directory.url.appending(path: "value.json")
        try FileManager.default.createDirectory(
            at: directory.url, withIntermediateDirectories: true)
        let stale = directory.url.appending(path: "value.json.tmp")
        try Data("half-writt".utf8).write(to: stale)
        try AtomicFileWriter(protection: .ownerOnly).write(Data("fresh".utf8), to: file)
        #expect(try Data(contentsOf: file) == Data("fresh".utf8))
        #expect(!FileManager.default.fileExists(atPath: stale.path))
    }
}
