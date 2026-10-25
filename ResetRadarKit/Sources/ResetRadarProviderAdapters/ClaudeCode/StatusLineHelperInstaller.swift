import CryptoKit
import Darwin
import Foundation

public enum StatusLineHelperInstallState: Equatable, Sendable {
    case missing
    case current
    case mismatch
}

public enum StatusLineHelperInstallerError: Error, Equatable, Sendable {
    case invalidSource
    case unsafeLocation
    case unavailable
    case versionMismatch
}

/// Copies the embedded helper to a stable owner-only path and verifies it. It never executes an
/// installed file until ownership, mode, type, and content identity have been proved.
public struct StatusLineHelperInstaller: Sendable {
    public static let binDirectoryName = "bin"
    public static let helperName = "reset-radar-statusline"
    public static let maximumHelperBytes: Int64 = 64 * 1_024 * 1_024

    private let sourceURL: URL
    private let rootURL: URL
    private let expectedVersion: String

    public init(
        embeddedHelper: URL, rootDirectory: URL,
        expectedVersion: String = StatusLineHelperVersion.current
    ) {
        sourceURL = embeddedHelper
        rootURL = rootDirectory.standardizedFileURL
        self.expectedVersion = expectedVersion
    }

    public var binDirectoryURL: URL { rootURL.appending(path: Self.binDirectoryName) }
    public var installedURL: URL { binDirectoryURL.appending(path: Self.helperName) }

    /// Compares installed content with the embedded helper without executing the installed file.
    public func state() throws -> StatusLineHelperInstallState {
        let source = try sourceDigest()
        var metadata = Darwin.stat()
        guard lstat(installedURL.path, &metadata) == 0 else {
            if errno == ENOENT { return .missing }
            throw StatusLineHelperInstallerError.unsafeLocation
        }
        guard (metadata.st_mode & S_IFMT) == S_IFREG, metadata.st_uid == getuid(),
            metadata.st_mode & 0o7777 == 0o700
        else { throw StatusLineHelperInstallerError.unsafeLocation }
        try validateDirectories(create: false)
        return try digest(of: installedURL) == source ? .current : .mismatch
    }

    /// Keeps the stable helper current without rewriting an already verified copy.
    public func ensureCurrent() throws {
        switch try state() {
        case .current:
            return
        case .missing, .mismatch:
            try install()
        }
    }

    /// Installs or refreshes the helper and verifies the installed copy's public version.
    public func install() throws {
        let sourceData = try readSource()
        try validateDirectories(create: true)
        let temporary = binDirectoryURL.appending(path: ".tmp-\(UUID().uuidString)")
        guard POSIXIO.writeExclusive(sourceData, to: temporary, mode: 0o700) else {
            throw StatusLineHelperInstallerError.unavailable
        }
        var cleanup = true
        defer { if cleanup { unlink(temporary.path) } }
        try requireReplaceableDestination()
        guard rename(temporary.path, installedURL.path) == 0 else {
            throw StatusLineHelperInstallerError.unavailable
        }
        cleanup = false
        guard try state() == .current else { throw StatusLineHelperInstallerError.unsafeLocation }
        guard try installedVersion() == expectedVersion else {
            throw StatusLineHelperInstallerError.versionMismatch
        }
    }

    /// A just-written executable can be briefly busy ("text file busy") when another thread
    /// forked while its descriptor was open, so retry a few times before giving up.
    private func launchRetryingBusyFile(_ process: Process) throws {
        for attempt in 0..<5 {
            do {
                try process.run()
                return
            } catch {
                guard attempt < 4 else { throw StatusLineHelperInstallerError.unavailable }
                usleep(50_000)
            }
        }
    }

    private func requireReplaceableDestination() throws {
        var existing = Darwin.stat()
        guard lstat(installedURL.path, &existing) == 0 else { return }
        guard (existing.st_mode & S_IFMT) == S_IFREG, existing.st_uid == getuid() else {
            throw StatusLineHelperInstallerError.unsafeLocation
        }
    }

    /// Runs the content-verified installed copy with `--version` under a short timeout.
    func installedVersion() throws -> String {
        guard try state() == .current else { throw StatusLineHelperInstallerError.versionMismatch }
        let process = Process()
        process.executableURL = installedURL
        process.arguments = ["--version"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        try launchRetryingBusyFile(process)
        guard done.wait(timeout: .now() + StatusLineLimits.syntheticCommandTimeout) == .success
        else {
            process.terminate()
            throw StatusLineHelperInstallerError.unavailable
        }
        let data = output.fileHandleForReading.readData(ofLength: 129)
        guard process.terminationStatus == 0, data.count <= 128,
            let text = String(data: data, encoding: .utf8)
        else { throw StatusLineHelperInstallerError.versionMismatch }
        return text.trimmingCharacters(in: .newlines)
    }

    private func readSource() throws -> Data {
        let descriptor = open(sourceURL.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw StatusLineHelperInstallerError.invalidSource }
        defer { close(descriptor) }
        var metadata = Darwin.stat()
        guard fstat(descriptor, &metadata) == 0, (metadata.st_mode & S_IFMT) == S_IFREG,
            metadata.st_size > 0, metadata.st_size <= Self.maximumHelperBytes,
            let data = try? POSIXIO.readAll(from: descriptor, limit: Int(Self.maximumHelperBytes))
        else { throw StatusLineHelperInstallerError.invalidSource }
        return data
    }

    private func sourceDigest() throws -> String { digestOf(try readSource()) }

    private func digest(of url: URL) throws -> String {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw StatusLineHelperInstallerError.unsafeLocation }
        defer { close(descriptor) }
        var hasher = SHA256()
        var total: Int64 = 0
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            guard count >= 0 else { throw StatusLineHelperInstallerError.unavailable }
            if count == 0 { break }
            total += Int64(count)
            guard total <= Self.maximumHelperBytes else {
                throw StatusLineHelperInstallerError.unsafeLocation
            }
            hasher.update(data: buffer.prefix(count))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func digestOf(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func validateDirectories(create: Bool) throws {
        for url in [rootURL, binDirectoryURL] {
            if create, mkdir(url.path, 0o700) != 0, errno != EEXIST {
                throw StatusLineHelperInstallerError.unavailable
            }
            var metadata = Darwin.stat()
            guard lstat(url.path, &metadata) == 0, (metadata.st_mode & S_IFMT) == S_IFDIR,
                metadata.st_uid == getuid(), metadata.st_mode & 0o022 == 0
            else { throw StatusLineHelperInstallerError.unsafeLocation }
        }
    }
}
