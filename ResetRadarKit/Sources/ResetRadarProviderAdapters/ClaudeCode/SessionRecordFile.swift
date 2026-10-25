import Darwin
import Foundation

/// Reads and atomically replaces `<key>.json` records under one fixed cross-process lock. The
/// directory, lock, temporary files, and records are owner-only and never follow a symlink.
public struct SessionRecordFile: Sendable {
    public static let directoryName = "claude-status"

    public let directoryURL: URL
    private let rootURL: URL
    private let files: OwnerOnlyConfigurationFiles

    /// `rootDirectory` is the Reset Radar support directory; records live in `claude-status`.
    public init(rootDirectory: URL) {
        rootURL = rootDirectory.standardizedFileURL
        directoryURL = rootURL.appending(path: Self.directoryName)
        files = OwnerOnlyConfigurationFiles(
            directoryURL: directoryURL, maximumBytes: StatusLineLimits.maximumRecordBytes,
            lockTimeout: StatusLineLimits.lockTimeout)
    }

    /// Creates the owner-only directory chain below an existing parent and validates it.
    public func prepare() throws {
        try Self.ensureOwnerOnlyDirectory(rootURL)
        try Self.ensureOwnerOnlyDirectory(directoryURL)
    }

    /// One locked read-modify-write. Returning nil from `body` leaves the stored bytes untouched.
    @discardableResult
    public func update(
        key: SessionKey, _ body: (SessionRecord?) throws -> SessionRecord?
    ) throws -> SessionRecord? {
        try prepare()
        return try map {
            try files.withLock {
                let current = try readLocked(key: key)
                guard let next = try body(current) else { return current }
                guard next.key == key else { throw SessionRecordError.incompatibleRecord }
                try files.write(try SessionRecordCodec.encode(next), named: key.fileName)
                return next
            }
        }
    }

    public func read(key: SessionKey) throws -> SessionRecord? {
        try map { try readLocked(key: key) }
    }

    /// Takes the same lock as `update`; `body` sees a stable directory.
    public func withLock<T>(_ body: () throws -> T) throws -> T {
        try prepare()
        return try map { try files.withLock(body) }
    }

    func remove(key: SessionKey) throws {
        try map { try files.remove(named: key.fileName) }
    }

    private func readLocked(key: SessionKey) throws -> SessionRecord? {
        let data: Data
        do {
            data = try files.read(named: key.fileName)
        } catch ProviderAccountCatalogStoreError.accountNotFound {
            return nil
        }
        let record = try SessionRecordCodec.decode(data)
        guard record.key == key else { throw SessionRecordError.incompatibleRecord }
        return record
    }

    private func map<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let error as ProviderAccountCatalogStoreError {
            switch error {
            case .unsafeLocation: throw SessionRecordError.unsafeLocation
            case .accountNotFound: throw SessionRecordError.notFound
            case .incompatibleConfiguration: throw SessionRecordError.recordTooLarge
            default: throw SessionRecordError.unavailable
            }
        }
    }

    static func ensureOwnerOnlyDirectory(_ url: URL) throws {
        if mkdir(url.path, mode_t(0o700)) != 0, errno != EEXIST {
            throw SessionRecordError.unavailable
        }
        var metadata = Darwin.stat()
        guard lstat(url.path, &metadata) == 0, (metadata.st_mode & S_IFMT) == S_IFDIR,
            metadata.st_uid == getuid(), metadata.st_mode & 0o022 == 0
        else { throw SessionRecordError.unsafeLocation }
    }
}
