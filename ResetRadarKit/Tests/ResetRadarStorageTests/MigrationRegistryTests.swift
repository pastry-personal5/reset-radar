import Foundation
import ResetRadarDomain
import Testing

@testable import ResetRadarStorage

private final class Order: @unchecked Sendable {
    private let lock = NSLock()
    private var steps: [Int] = []
    func record(_ step: Int) {
        lock.lock()
        defer { lock.unlock() }
        steps.append(step)
    }

    var all: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return steps
    }
}

private func replacing(_ target: String, with replacement: String) -> MigrationRegistry.Step {
    { data in
        let text = String(bytes: data, encoding: .utf8) ?? ""
        return Data(text.replacingOccurrences(of: target, with: replacement).utf8)
    }
}

/// Writes `payload` at schema version 1 and returns the file as it would read at version 2 after
/// a v1 to v2 step.
private func versionOneFile<Value: Codable & Sendable>(
    _ type: Value.Type, payload: Data, step: @escaping MigrationRegistry.Step,
    in directory: TemporaryDirectory,
    validate: @escaping @Sendable (Value) throws -> Void = { _ in }
) throws -> VersionedCodableFile<Value> {
    let url = directory.url.appending(path: "value.json")
    try FileManager.default.createDirectory(at: directory.url, withIntermediateDirectories: true)
    var document = Data("{\"payload\":".utf8)
    document.append(payload)
    document.append(Data(",\"schemaVersion\":1}".utf8))
    try document.write(to: url)
    return VersionedCodableFile(
        url: url, currentVersion: 2, registry: MigrationRegistry(steps: [1: step]),
        writer: AtomicFileWriter(protection: .ownerOnly), validate: validate)
}

struct MigrationRegistryTests {
    @Test func chainRunsOneVersionAtATimeInOrder() throws {
        let order = Order()
        let registry = MigrationRegistry(steps: [
            0: { data in
                order.record(0)
                return data
            },
            1: { data in
                order.record(1)
                return data
            },
        ])
        _ = try registry.migrate(Data("{}".utf8), from: 0, to: 2)
        #expect(order.all == [0, 1])
    }

    @Test func throwingMiddleStepIsCorruptAndLeavesTheFileBytes() throws {
        struct Boom: Error {}
        let directory = TemporaryDirectory()
        let payload = try WireCoding.encoder().encode(sampleValue)
        let file = try versionOneFile(
            Sample.self, payload: payload, step: { _ in throw Boom() }, in: directory)
        let before = try contents(directory, "value.json")
        #expect(throws: StorageFailure.corrupt) { try file.read() }
        #expect(try contents(directory, "value.json") == before)
    }

    @Test func missingStepIsIncompatible() {
        let registry = MigrationRegistry()
        #expect(throws: StorageFailure.incompatible(foundVersion: 0)) {
            try registry.migrate(Data("{}".utf8), from: 0, to: 1)
        }
    }

    @Test func cleanMigrationReadsTheMigratedValue() throws {
        let directory = TemporaryDirectory()
        let payload = try WireCoding.encoder().encode(sampleValue)
        let file = try versionOneFile(
            Sample.self, payload: payload,
            step: replacing("\"name\":\"a\"", with: "\"name\":\"b\""),
            in: directory)
        #expect(try file.read()?.name == "b")
    }

    @Test func percentageOf101IsRejected() throws {
        let directory = TemporaryDirectory()
        let payload = try WireCoding.encoder().encode(snapshot(percent: 42))
        let file = try versionOneFile(
            UsageSnapshot.self, payload: payload,
            step: replacing("\"usedPercent\":42", with: "\"usedPercent\":101"), in: directory)
        let before = try contents(directory, "value.json")
        #expect(throws: StorageFailure.corrupt) { try file.read() }
        #expect(try contents(directory, "value.json") == before)
    }

    @Test func negativeTimestampIsRejected() throws {
        let directory = TemporaryDirectory()
        let payload = try WireCoding.encoder().encode(sampleValue)
        let text = String(bytes: payload, encoding: .utf8) ?? ""
        let date = try #require(text.split(separator: "\"").first { $0.hasPrefix("20") })
        let file = try versionOneFile(
            Sample.self, payload: payload,
            step: replacing(String(date), with: "1969-12-31T23:59:59.000Z"), in: directory)
        #expect(throws: StorageFailure.corrupt) { try file.read() }
    }

    @Test func emptyPublisherIDIsRejected() throws {
        let directory = TemporaryDirectory()
        let payload = try WireCoding.encoder().encode(snapshot())
        let file = try versionOneFile(
            UsageSnapshot.self, payload: payload,
            step: replacing("\"publisherID\":\"\(publisher.hex)\"", with: "\"publisherID\":\"\""),
            in: directory)
        #expect(throws: StorageFailure.corrupt) { try file.read() }
    }

    @Test func sequenceBelowTheStoredFloorIsRejected() throws {
        let directory = TemporaryDirectory()
        let payload = try WireCoding.encoder().encode(sampleValue)
        let file = try versionOneFile(
            Sample.self, payload: payload,
            step: replacing("\"sequence\":5", with: "\"sequence\":0"), in: directory,
            validate: { if $0.sequence < $0.floor { throw StorageFailure.corrupt } })
        #expect(throws: StorageFailure.corrupt) { try file.read() }
    }
}
