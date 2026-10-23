import Foundation
import ResetRadarDomain

/// One JSON file holding `{"schemaVersion": Int, "payload": …}`, read with validation and
/// replaced atomically. Callers hold the store's `ProcessFileLock` around read-modify-write.
public struct VersionedCodableFile<Value: Codable & Sendable>: Sendable {
    private struct Header: Decodable {
        let schemaVersion: Int
    }

    private struct Envelope<Payload: Codable>: Codable {
        let schemaVersion: Int
        let payload: Payload
    }

    private let url: URL
    private let currentVersion: Int
    private let registry: MigrationRegistry
    private let writer: AtomicFileWriter
    private let maxBytes: Int
    private let validate: @Sendable (Value) throws -> Void

    /// `validate` checks the invariants a single decode cannot, such as a sequence that must not
    /// fall below its floor. A value that fails it is `corrupt`.
    public init(
        url: URL, currentVersion: Int, registry: MigrationRegistry = MigrationRegistry(),
        writer: AtomicFileWriter = AtomicFileWriter(), maxBytes: Int = 5 * 1024 * 1024,
        validate: @escaping @Sendable (Value) throws -> Void = { _ in }
    ) {
        self.url = url
        self.currentVersion = currentVersion
        self.registry = registry
        self.writer = writer
        self.maxBytes = maxBytes
        self.validate = validate
    }

    /// `nil` when the file does not exist. Undecodable or invalid content is moved aside as
    /// `<name>.corrupt` (or a numbered sibling when it exists) and throws `corrupt` once.
    /// An unknown newer version throws `incompatible` and leaves the file untouched; an
    /// oversized file throws `tooLarge` without being read. An older version is migrated and
    /// replaced before the read returns.
    public func read() throws -> Value? {
        guard let data = try loadBytes() else { return nil }
        let version: Int
        do {
            version = try WireCoding.decoder().decode(Header.self, from: data).schemaVersion
        } catch {
            throw quarantine()
        }
        if version > currentVersion { throw StorageError.incompatible(foundVersion: version) }
        if version < currentVersion {
            let value = try migrated(data, from: version)
            try write(value)
            return value
        }
        do {
            let value = try WireCoding.decoder().decode(Envelope<Value>.self, from: data).payload
            try validate(value)
            return value
        } catch {
            throw quarantine()
        }
    }

    /// Replaces the file. On macOS the first write in a newer schema first copies the previous
    /// file to `<name>.v<oldVersion>.bak`. A file written by a newer build is never overwritten.
    public func write(_ value: Value) throws {
        do {
            try validate(value)
        } catch {
            throw StorageError.corrupt
        }
        let encoded: Data
        do {
            encoded = try WireCoding.encoder().encode(
                Envelope(schemaVersion: currentVersion, payload: value))
        } catch {
            throw StorageError.corrupt
        }
        guard encoded.count <= maxBytes else { throw StorageError.tooLarge }
        try backUpOlderSchema()
        try writer.write(encoded, to: url)
    }

    private func loadBytes() throws -> Data? {
        let path = url.path(percentEncoded: false)
        var info = stat()
        guard stat(path, &info) == 0 else {
            if errno == ENOENT { return nil }
            throw StorageError.io(code: Int(errno))
        }
        guard info.st_size <= maxBytes else { throw StorageError.tooLarge }
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= maxBytes else { throw StorageError.tooLarge }
            return data
        } catch let error as StorageError {
            throw error
        } catch {
            throw StorageError.io(code: AtomicFileWriter.code(of: error))
        }
    }

    private func quarantine() -> StorageError {
        let path = url.path(percentEncoded: false)
        let base = path + ".corrupt"
        var destination = base
        var suffix = 1
        while FileManager.default.fileExists(atPath: destination) {
            destination = base + ".\(suffix)"
            suffix += 1
        }
        if rename(path, destination) != 0 { return .io(code: Int(errno)) }
        return .corrupt
    }

    /// A migrated payload must decode, validate, and re-encode to the same JSON, so a step that
    /// yields a percentage the decoder would drop, or a pre-epoch time, is rejected instead of
    /// accepted. The stored file is untouched on any failure.
    private func migrated(_ data: Data, from version: Int) throws -> Value {
        do {
            guard
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let payload = object["payload"]
            else { throw StorageError.corrupt }
            let input = try JSONSerialization.data(
                withJSONObject: payload, options: [.fragmentsAllowed])
            let output = try registry.migrate(input, from: version, to: currentVersion)
            let value = try WireCoding.decoder().decode(Value.self, from: output)
            try validate(value)
            let reencoded = try WireCoding.encoder().encode(value)
            let expected = try JSONSerialization.jsonObject(
                with: output, options: [.fragmentsAllowed])
            let actual = try JSONSerialization.jsonObject(
                with: reencoded, options: [.fragmentsAllowed])
            guard (expected as AnyObject).isEqual(actual), !Self.hasPreEpochDate(expected) else {
                throw StorageError.corrupt
            }
            return value
        } catch let error as StorageError {
            throw error
        } catch {
            throw StorageError.corrupt
        }
    }

    private static func hasPreEpochDate(_ node: Any) -> Bool {
        if let text = node as? String {
            guard text.count >= 20, text.first?.isNumber == true,
                let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true)
                    .parse(text)
            else { return false }
            return date.timeIntervalSince1970 < 0
        }
        if let array = node as? [Any] { return array.contains(where: hasPreEpochDate) }
        if let dictionary = node as? [String: Any] {
            return dictionary.values.contains(where: hasPreEpochDate)
        }
        return false
    }

    private func backUpOlderSchema() throws {
        guard let existing = try loadBytes(),
            let version = try? WireCoding.decoder().decode(Header.self, from: existing)
                .schemaVersion
        else { return }
        if version > currentVersion { throw StorageError.incompatible(foundVersion: version) }
        #if os(macOS)
            if version < currentVersion {
                let name = url.lastPathComponent
                try writer.write(
                    existing,
                    to: url.deletingLastPathComponent().appending(path: "\(name).v\(version).bak"))
            }
        #endif
    }
}
