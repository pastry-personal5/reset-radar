import Foundation
import ResetRadarApplication
import ResetRadarDomain
import Testing

@testable import ResetRadarStorage

typealias StorageFailure = ResetRadarStorage.StorageError

struct Sample: Codable, Sendable, Equatable {
    var name: String
    var observedAt: Date
    var floor: UInt64
    var sequence: UInt64
}

let sampleValue = Sample(name: "a", observedAt: at(0), floor: 1, sequence: 5)

func sampleFile(
    _ directory: TemporaryDirectory, version: Int = 1, maxBytes: Int = 5 * 1024 * 1024,
    registry: MigrationRegistry = MigrationRegistry()
) -> VersionedCodableFile<Sample> {
    VersionedCodableFile(
        url: directory.url.appending(path: "sample.json"), currentVersion: version,
        registry: registry, writer: AtomicFileWriter(protection: .ownerOnly), maxBytes: maxBytes,
        validate: { value in
            if value.sequence < value.floor { throw StorageFailure.corrupt }
        })
}

func contents(_ directory: TemporaryDirectory, _ name: String = "sample.json") throws -> Data {
    try Data(contentsOf: directory.url.appending(path: name))
}

func exists(_ directory: TemporaryDirectory, _ name: String) -> Bool {
    FileManager.default.fileExists(atPath: directory.url.appending(path: name).path)
}

struct VersionedCodableFileTests {
    @Test func missingFileReadsAsNil() throws {
        let directory = TemporaryDirectory()
        #expect(try sampleFile(directory).read() == nil)
    }

    @Test func roundTrips() throws {
        let directory = TemporaryDirectory()
        let file = sampleFile(directory)
        try file.write(sampleValue)
        #expect(try file.read() == sampleValue)
    }

    @Test func publisherStateWithHandledRequestsRoundTripsAndToleratesAnExtraField() throws {
        let directory = TemporaryDirectory()
        let url = directory.url.appending(path: "publisher.json")
        let file = VersionedCodableFile<PublisherState>(
            url: url, currentVersion: 1, writer: AtomicFileWriter(protection: .ownerOnly))
        var state = PublisherState()
        state.lifecycle = .active
        state.publisherID = publisher
        state.endpoint = endpoint
        state.sequence = 9
        state.handledRequests = [requestID(1): at(10), requestID(2): at(20)]
        state.devices = [PairedDevice(readerID: readerA, name: "Phone", pairedAt: at(5))]
        try file.write(state)
        #expect(try file.read() == state)

        var object = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var payload = try #require(object["payload"] as? [String: Any])
        payload["futureField"] = 7
        object["payload"] = payload
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        #expect(try file.read() == state)
    }

    @Test(arguments: [
        "", "not json", "{\"schemaVersion\":1}", "{\"schemaVersion\":1,\"payload\":{}}",
    ])
    func corruptContentIsMovedAsideOnceThenReadsEmpty(_ text: String) throws {
        let directory = TemporaryDirectory()
        let file = sampleFile(directory)
        try file.write(sampleValue)
        try Data(text.utf8).write(to: directory.url.appending(path: "sample.json"))
        #expect(throws: StorageFailure.corrupt) { try file.read() }
        #expect(!exists(directory, "sample.json"))
        #expect(try contents(directory, "sample.json.corrupt") == Data(text.utf8))
        #expect(try file.read() == nil)
    }

    @Test func laterCorruptionPreservesTheEarlierQuarantine() throws {
        let directory = TemporaryDirectory()
        try FileManager.default.createDirectory(
            at: directory.url, withIntermediateDirectories: true)
        let file = sampleFile(directory)
        let first = Data("first corrupt file".utf8)
        let second = Data("second corrupt file".utf8)
        try first.write(to: directory.url.appending(path: "sample.json"))
        #expect(throws: StorageFailure.corrupt) { try file.read() }
        try second.write(to: directory.url.appending(path: "sample.json"))
        #expect(throws: StorageFailure.corrupt) { try file.read() }
        #expect(try contents(directory, "sample.json.corrupt") == first)
        #expect(try contents(directory, "sample.json.corrupt.1") == second)
    }

    @Test func invalidValueIsRefusedBeforeReplacingTheFile() throws {
        let directory = TemporaryDirectory()
        let file = sampleFile(directory)
        try file.write(sampleValue)
        let before = try contents(directory)
        var bad = sampleValue
        bad.sequence = 0
        #expect(throws: StorageFailure.corrupt) { try file.write(bad) }
        #expect(try contents(directory) == before)
        #expect(try file.read() == sampleValue)
    }

    @Test func oversizedByOneByteIsTooLargeAndExactSizeDecodes() throws {
        let directory = TemporaryDirectory()
        let url = directory.url.appending(path: "sample.json")
        let probe = sampleFile(directory)
        try probe.write(sampleValue)
        let base = try contents(directory)
        let limit = base.count + 10
        let file = sampleFile(directory, maxBytes: limit)
        try (base + Data(repeating: 0x20, count: 10)).write(to: url)
        #expect(try file.read() == sampleValue)
        let over = base + Data(repeating: 0x20, count: 11)
        try over.write(to: url)
        #expect(throws: StorageFailure.tooLarge) { try file.read() }
        #expect(try contents(directory) == over)
    }

    @Test func writeRefusesAValueThatWouldNotReadBack() throws {
        let directory = TemporaryDirectory()
        let file = sampleFile(directory, maxBytes: 20)
        #expect(throws: StorageFailure.tooLarge) { try file.write(sampleValue) }
        #expect(!exists(directory, "sample.json"))
    }

    @Test func unknownMandatoryVersionIsIncompatibleAndUntouched() throws {
        let directory = TemporaryDirectory()
        try sampleFile(directory, version: 3).write(sampleValue)
        let before = try contents(directory)
        let older = sampleFile(directory, version: 2)
        #expect(throws: StorageFailure.incompatible(foundVersion: 3)) { try older.read() }
        #expect(throws: StorageFailure.incompatible(foundVersion: 3)) {
            try older.write(sampleValue)
        }
        #expect(try contents(directory) == before)
    }

    #if os(macOS)
        @Test func newerSchemaWriteBacksUpThePreviousFileOnce() throws {
            let directory = TemporaryDirectory()
            try sampleFile(directory, version: 1).write(sampleValue)
            let old = try contents(directory)
            let registry = MigrationRegistry(steps: [1: { $0 }])
            let upgraded = sampleFile(directory, version: 2, registry: registry)
            #expect(try upgraded.read() == sampleValue)
            #expect(try contents(directory, "sample.json.v1.bak") == old)
            try upgraded.write(sampleValue)
            #expect(try upgraded.read() == sampleValue)
        }

        @Test func sameVersionWriteLeavesNoBackup() throws {
            let directory = TemporaryDirectory()
            let file = sampleFile(directory)
            try file.write(sampleValue)
            try file.write(sampleValue)
            #expect(!exists(directory, "sample.json.v1.bak"))
        }
    #endif
}
