import Darwin
import Foundation
import ResetRadarApplication
import ResetRadarDomain

struct OwnerOnlyConfigurationFiles: Sendable {
    let directoryURL: URL

    init(directoryURL: URL) {
        self.directoryURL = directoryURL.standardizedFileURL
    }

    func withLock<T>(_ body: () throws -> T) throws -> T {
        try prepareDirectory()
        let descriptor = open(lockURL.path, O_RDWR | O_CREAT | O_NOFOLLOW, mode_t(0o600))
        guard descriptor >= 0 else {
            throw ProviderAccountCatalogStoreError.unsafeLocation
        }
        defer { close(descriptor) }
        try validate(descriptor: descriptor, kind: S_IFREG, permissions: 0o600)
        guard flock(descriptor, LOCK_EX) == 0 else {
            throw ProviderAccountCatalogStoreError.unavailable
        }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }

    func read(named name: String) throws -> Data {
        let url = try child(named: name)
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else {
            if errno == ENOENT { throw ProviderAccountCatalogStoreError.accountNotFound }
            throw ProviderAccountCatalogStoreError.unsafeLocation
        }
        defer { close(descriptor) }
        try validate(descriptor: descriptor, kind: S_IFREG, permissions: 0o600)
        var metadata = Darwin.stat()
        guard fstat(descriptor, &metadata) == 0,
            metadata.st_size >= 0,
            metadata.st_size <= ProviderAccountCatalogStore.maximumFileBytes
        else { throw ProviderAccountCatalogStoreError.incompatibleConfiguration }
        var result = Data()
        var bytes = [UInt8](repeating: 0, count: 8_192)
        while true {
            let count = Darwin.read(descriptor, &bytes, bytes.count)
            guard count >= 0 else { throw ProviderAccountCatalogStoreError.unavailable }
            if count == 0 { break }
            result.append(bytes, count: count)
            guard result.count <= ProviderAccountCatalogStore.maximumFileBytes else {
                throw ProviderAccountCatalogStoreError.incompatibleConfiguration
            }
        }
        return result
    }

    func write(_ data: Data, named name: String) throws {
        guard data.count <= ProviderAccountCatalogStore.maximumFileBytes else {
            throw ProviderAccountCatalogStoreError.incompatibleConfiguration
        }
        let destination = try child(named: name)
        try validateExistingDestination(destination)
        let temporary = try child(named: ".tmp-\(UUID().uuidString)")
        let descriptor = open(
            temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard descriptor >= 0 else { throw ProviderAccountCatalogStoreError.unavailable }
        var shouldRemove = true
        defer {
            close(descriptor)
            if shouldRemove { unlink(temporary.path) }
        }
        try validate(descriptor: descriptor, kind: S_IFREG, permissions: 0o600)
        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
                let count = Darwin.write(
                    descriptor, base.advanced(by: offset), rawBuffer.count - offset)
                guard count > 0 else { throw ProviderAccountCatalogStoreError.unavailable }
                offset += count
            }
        }
        guard fsync(descriptor) == 0, rename(temporary.path, destination.path) == 0 else {
            throw ProviderAccountCatalogStoreError.unavailable
        }
        shouldRemove = false
        try syncDirectory()
    }

    func remove(named name: String) throws {
        let url = try child(named: name)
        var metadata = Darwin.stat()
        guard lstat(url.path, &metadata) == 0 else {
            if errno == ENOENT { throw ProviderAccountCatalogStoreError.accountNotFound }
            throw ProviderAccountCatalogStoreError.unsafeLocation
        }
        guard (metadata.st_mode & S_IFMT) == S_IFREG, metadata.st_uid == getuid(),
            metadata.st_mode & 0o777 == 0o600
        else { throw ProviderAccountCatalogStoreError.unsafeLocation }
        guard unlink(url.path) == 0 else {
            throw ProviderAccountCatalogStoreError.unavailable
        }
        try syncDirectory()
    }

    private var lockURL: URL { directoryURL.appending(path: ".lock") }

    private func prepareDirectory() throws {
        guard directoryURL.path.hasPrefix("/") else {
            throw ProviderAccountCatalogStoreError.unsafeLocation
        }
        if mkdir(directoryURL.path, mode_t(0o700)) != 0, errno != EEXIST {
            throw ProviderAccountCatalogStoreError.unavailable
        }
        var metadata = Darwin.stat()
        guard lstat(directoryURL.path, &metadata) == 0,
            (metadata.st_mode & S_IFMT) == S_IFDIR,
            metadata.st_uid == getuid(), metadata.st_mode & 0o777 == 0o700
        else { throw ProviderAccountCatalogStoreError.unsafeLocation }
    }

    private func child(named name: String) throws -> URL {
        guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else {
            throw ProviderAccountCatalogStoreError.unsafeLocation
        }
        return directoryURL.appending(path: name)
    }

    private func validateExistingDestination(_ url: URL) throws {
        var metadata = Darwin.stat()
        guard lstat(url.path, &metadata) == 0 else {
            if errno == ENOENT { return }
            throw ProviderAccountCatalogStoreError.unsafeLocation
        }
        guard (metadata.st_mode & S_IFMT) == S_IFREG, metadata.st_uid == getuid(),
            metadata.st_mode & 0o777 == 0o600
        else { throw ProviderAccountCatalogStoreError.unsafeLocation }
    }

    private func validate(
        descriptor: Int32, kind: mode_t, permissions: mode_t
    ) throws {
        var metadata = Darwin.stat()
        guard fstat(descriptor, &metadata) == 0,
            (metadata.st_mode & S_IFMT) == kind,
            metadata.st_uid == getuid(), metadata.st_mode & 0o777 == permissions
        else { throw ProviderAccountCatalogStoreError.unsafeLocation }
    }

    private func syncDirectory() throws {
        let descriptor = open(directoryURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw ProviderAccountCatalogStoreError.unsafeLocation }
        defer { close(descriptor) }
        try validate(descriptor: descriptor, kind: S_IFDIR, permissions: 0o700)
        guard fsync(descriptor) == 0 else {
            throw ProviderAccountCatalogStoreError.unavailable
        }
    }
}
