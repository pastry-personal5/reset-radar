import CryptoKit
import Darwin
import Foundation

public enum ExecutableTrustError: Error, Equatable, Sendable {
    case invalidPath
    case unavailable
    case notRegularFile
    case notExecutable
    /// Owner, mode, ancestor chain, or home containment fails the owner-only trust rule.
    case untrusted
    case tooLarge
    case changed
}

/// What preview and synthetic validation bind to, and apply revalidates.
public struct ExecutableIdentity: Codable, Equatable, Sendable {
    public let canonicalPath: String
    public let device: UInt64
    public let inode: UInt64
    public let ownerID: UInt32
    public let permissions: UInt16
    public let size: Int64
    public let modifiedSeconds: Int64
    public let modifiedNanoseconds: Int64
    public let sha256: String
}

/// The approved owner-only trust test: a regular executable owned by the current user inside the
/// owner's home directory, whose resolved ancestor chain is owned by the current user or root and
/// is not writable by group or other. A path prefix alone is never trusted.
public struct ExecutableIdentityValidator: Sendable {
    private let homePath: String
    private let ownerID: UInt32
    private let maximumDigestBytes: Int64

    public init(
        homeDirectory: URL, ownerID: UInt32 = getuid(),
        maximumDigestBytes: Int64 = Int64(StatusLineLimits.maximumExecutableBytes)
    ) {
        homePath = Self.resolve(homeDirectory.path) ?? homeDirectory.standardizedFileURL.path
        self.ownerID = ownerID
        self.maximumDigestBytes = maximumDigestBytes
    }

    /// Runtime check: path, type, ownership, modes, ancestors. Permits a legitimate upgrade.
    @discardableResult
    public func validatePath(_ path: String) throws(ExecutableTrustError) -> String {
        guard path.hasPrefix("/"), !path.contains("\0"), path.utf8.count <= 4_096 else {
            throw .invalidPath
        }
        guard let canonical = Self.resolve(path) else { throw .unavailable }
        guard canonical.hasPrefix(homePath + "/") else { throw .untrusted }
        var metadata = Darwin.stat()
        guard lstat(canonical, &metadata) == 0 else { throw .unavailable }
        guard (metadata.st_mode & S_IFMT) == S_IFREG else { throw .notRegularFile }
        guard metadata.st_uid == ownerID, metadata.st_mode & 0o022 == 0 else { throw .untrusted }
        guard metadata.st_mode & 0o100 != 0, access(canonical, X_OK) == 0 else {
            throw .notExecutable
        }
        guard Self.ancestorsAreTrusted(of: canonical, ownerID: ownerID) else { throw .untrusted }
        return canonical
    }

    /// Full identity including a streamed content digest, bounded by the approved ceiling.
    public func identity(of path: String) throws(ExecutableTrustError) -> ExecutableIdentity {
        let canonical = try validatePath(path)
        let descriptor = open(canonical, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw .unavailable }
        defer { close(descriptor) }
        var metadata = Darwin.stat()
        guard fstat(descriptor, &metadata) == 0 else { throw .unavailable }
        try validateOpenedMetadata(metadata)
        guard metadata.st_size <= maximumDigestBytes else { throw .tooLarge }
        let digest = try digestStableFile(descriptor, initialMetadata: metadata)
        try validatePathStillNamesDescriptor(canonical, metadata: metadata)
        return ExecutableIdentity(
            canonicalPath: canonical, device: UInt64(metadata.st_dev),
            inode: UInt64(metadata.st_ino), ownerID: metadata.st_uid,
            permissions: UInt16(metadata.st_mode & 0o7777), size: metadata.st_size,
            modifiedSeconds: Int64(metadata.st_mtimespec.tv_sec),
            modifiedNanoseconds: Int64(metadata.st_mtimespec.tv_nsec), sha256: digest)
    }

    private func digestStableFile(
        _ descriptor: Int32, initialMetadata: Darwin.stat
    ) throws(ExecutableTrustError) -> String {
        var hasher = SHA256()
        var total: Int64 = 0
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw .unavailable }
            if count == 0 { break }
            total += Int64(count)
            guard total <= maximumDigestBytes else { throw .tooLarge }
            hasher.update(data: buffer.prefix(count))
        }
        var after = Darwin.stat()
        guard fstat(descriptor, &after) == 0, after.st_size == total,
            Self.sameIdentity(initialMetadata, after)
        else { throw .changed }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func validatePathStillNamesDescriptor(
        _ canonical: String, metadata: Darwin.stat
    ) throws(ExecutableTrustError) {
        // The path must still name the exact descriptor we hashed. This also rechecks the path and
        // ancestor trust rules after the read, narrowing replacement races around preview/apply.
        guard (try? validatePath(canonical)) == canonical else { throw .changed }
        var currentPath = Darwin.stat()
        guard lstat(canonical, &currentPath) == 0,
            currentPath.st_dev == metadata.st_dev, currentPath.st_ino == metadata.st_ino
        else { throw .changed }
    }

    private func validateOpenedMetadata(
        _ metadata: Darwin.stat
    ) throws(ExecutableTrustError) {
        guard (metadata.st_mode & S_IFMT) == S_IFREG else { throw .notRegularFile }
        guard metadata.st_uid == ownerID, metadata.st_mode & 0o022 == 0 else { throw .untrusted }
        guard metadata.st_mode & 0o100 != 0 else { throw .notExecutable }
    }

    private static func sameIdentity(_ lhs: Darwin.stat, _ rhs: Darwin.stat) -> Bool {
        lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino && lhs.st_uid == rhs.st_uid
            && lhs.st_mode == rhs.st_mode && lhs.st_size == rhs.st_size
            && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec
            && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
            && lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec
            && lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
    }

    public func revalidate(
        _ expected: ExecutableIdentity
    ) throws(ExecutableTrustError) -> ExecutableIdentity {
        let current = try identity(of: expected.canonicalPath)
        guard current == expected else { throw .changed }
        return current
    }

    /// Every directory from the parent up to `/` is owned by `ownerID` or root and is not
    /// writable by group or other.
    static func ancestorsAreTrusted(of canonical: String, ownerID: UInt32) -> Bool {
        var ancestor = (canonical as NSString).deletingLastPathComponent
        while true {
            var directory = Darwin.stat()
            guard lstat(ancestor, &directory) == 0, (directory.st_mode & S_IFMT) == S_IFDIR,
                directory.st_uid == ownerID || directory.st_uid == 0,
                directory.st_mode & 0o022 == 0
            else { return false }
            if ancestor == "/" { return true }
            ancestor = (ancestor as NSString).deletingLastPathComponent
        }
    }

    static func resolve(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
