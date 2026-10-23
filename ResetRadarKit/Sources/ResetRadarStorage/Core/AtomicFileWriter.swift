import Foundation

/// Replaces a file whole: write a temporary sibling, `fsync` it, apply the protection policy,
/// then `rename`. A reader sees the old bytes or the new bytes, never a partial file.
public struct AtomicFileWriter: Sendable {
    private let protection: ProtectionPolicy
    private let beforeRename: (@Sendable () throws -> Void)?

    public init(protection: ProtectionPolicy = .forCurrentPlatform()) {
        self.protection = protection
        self.beforeRename = nil
    }

    /// `beforeRename` runs after the temporary file is durable and before it replaces the
    /// target; tests use it to stand in for a crash or a failed write.
    init(protection: ProtectionPolicy, beforeRename: @escaping @Sendable () throws -> Void) {
        self.protection = protection
        self.beforeRename = beforeRename
    }

    public func write(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: protection.directoryAttributes)
            try FileManager.default.setAttributes(
                protection.directoryAttributes, ofItemAtPath: directory.path(percentEncoded: false))
        } catch {
            throw StorageError.io(code: Self.code(of: error))
        }
        // A fixed temporary name: the store lock serializes writers, and a leftover from a
        // crash is truncated by the next write instead of piling up.
        let temporary = directory.appending(path: url.lastPathComponent + ".tmp")
        try writeDurably(data, to: temporary)
        do {
            try FileManager.default.setAttributes(
                protection.fileAttributes, ofItemAtPath: temporary.path(percentEncoded: false))
            try syncFile(temporary)
            try beforeRename?()
        } catch {
            _ = unlink(temporary.path(percentEncoded: false))
            throw Self.storageError(error)
        }
        guard rename(temporary.path(percentEncoded: false), url.path(percentEncoded: false)) == 0
        else {
            let code = errno
            _ = unlink(temporary.path(percentEncoded: false))
            throw StorageError.io(code: Int(code))
        }
        try syncDirectory(directory)
    }

    private func writeDurably(_ data: Data, to url: URL) throws {
        let descriptor = open(
            url.path(percentEncoded: false), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw StorageError.io(code: Int(errno)) }
        defer { close(descriptor) }
        var failure: Int32?
        data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(
                    descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    failure = errno
                    return
                }
                offset += written
            }
        }
        if failure == nil, fsync(descriptor) != 0 { failure = errno }
        if let failure {
            _ = unlink(url.path(percentEncoded: false))
            throw StorageError.io(code: Int(failure))
        }
    }

    private func syncFile(_ url: URL) throws {
        let descriptor = open(url.path(percentEncoded: false), O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { throw StorageError.io(code: Int(errno)) }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw StorageError.io(code: Int(errno)) }
    }

    /// A failed sync cannot undo the rename, but the caller must not report a durable commit.
    private func syncDirectory(_ directory: URL) throws {
        let descriptor = open(directory.path(percentEncoded: false), O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { throw StorageError.io(code: Int(errno)) }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw StorageError.io(code: Int(errno)) }
    }

    static func storageError(_ error: any Error) -> StorageError {
        (error as? StorageError) ?? .io(code: code(of: error))
    }

    static func code(of error: any Error) -> Int {
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain { return nsError.code }
        let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        if let underlying, underlying.domain == NSPOSIXErrorDomain { return underlying.code }
        return Int(EIO)
    }
}
