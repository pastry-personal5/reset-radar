import Darwin
import Foundation

public enum CodexExecutableValidationError: Error, Equatable, Sendable {
    case invalidPath
    case unavailable
    case unsafePermissions
    case unsupportedLauncher
    case missingNode
    case changed
}

public struct CodexExecutableFileIdentity: Codable, Hashable, Sendable {
    public let canonicalPath: String
    public let device: UInt64
    public let inode: UInt64
    public let size: Int64
    public let modifiedSeconds: Int64
    public let modifiedNanoseconds: Int64
    public let ownerID: UInt32
    public let permissions: UInt16

    public init(
        canonicalPath: String, device: UInt64, inode: UInt64, size: Int64,
        modifiedSeconds: Int64, modifiedNanoseconds: Int64, ownerID: UInt32,
        permissions: UInt16
    ) {
        self.canonicalPath = canonicalPath
        self.device = device
        self.inode = inode
        self.size = size
        self.modifiedSeconds = modifiedSeconds
        self.modifiedNanoseconds = modifiedNanoseconds
        self.ownerID = ownerID
        self.permissions = permissions
    }
}

public struct CodexValidatedExecutable: Codable, Equatable, Sendable {
    public let invocationPath: String
    public let executable: CodexExecutableFileIdentity
    public let node: CodexExecutableFileIdentity?

    public init(
        invocationPath: String, executable: CodexExecutableFileIdentity,
        node: CodexExecutableFileIdentity?
    ) {
        self.invocationPath = invocationPath
        self.executable = executable
        self.node = node
    }
}

public struct CodexExecutableValidator: Sendable {
    public static let maximumShebangBytes = 4_096

    private let ownerID: UInt32

    public init(ownerID: UInt32 = getuid()) {
        self.ownerID = ownerID
    }

    public func validate(
        invocationPath: String, pathEnvironment: String
    ) throws(CodexExecutableValidationError) -> CodexValidatedExecutable {
        guard invocationPath.hasPrefix("/"), !invocationPath.contains("\0") else {
            throw .invalidPath
        }
        let pathComponents = try validatePathEnvironment(pathEnvironment)
        let executable = try identity(for: invocationPath)
        let node: CodexExecutableFileIdentity?
        switch try launcherKind(at: invocationPath) {
        case .native:
            node = nil
        case .environmentNode:
            node = try resolveNode(in: pathComponents)
        }
        return CodexValidatedExecutable(
            invocationPath: invocationPath, executable: executable, node: node)
    }

    public func revalidate(
        _ expected: CodexValidatedExecutable, pathEnvironment: String
    ) throws(CodexExecutableValidationError) -> CodexValidatedExecutable {
        let current = try validate(
            invocationPath: expected.invocationPath, pathEnvironment: pathEnvironment)
        guard current == expected else { throw .changed }
        return current
    }

    private enum LauncherKind {
        case native
        case environmentNode
    }

    private func validatePathEnvironment(
        _ value: String
    ) throws(CodexExecutableValidationError) -> [String] {
        let components = value.split(separator: ":", omittingEmptySubsequences: false).map(
            String.init)
        guard !components.isEmpty,
            components.allSatisfy({ !$0.isEmpty && $0.hasPrefix("/") && !$0.contains("\0") })
        else { throw .invalidPath }
        return components
    }

    private func identity(
        for path: String
    ) throws(CodexExecutableValidationError) -> CodexExecutableFileIdentity {
        let canonical = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
            .path
        var metadata = Darwin.stat()
        guard lstat(canonical, &metadata) == 0,
            (metadata.st_mode & S_IFMT) == S_IFREG,
            access(canonical, X_OK) == 0
        else { throw .unavailable }
        let owner = metadata.st_uid
        let permissions = metadata.st_mode & 0o7777
        guard owner == ownerID || owner == 0, permissions & 0o022 == 0 else {
            throw .unsafePermissions
        }
        return CodexExecutableFileIdentity(
            canonicalPath: canonical,
            device: UInt64(metadata.st_dev),
            inode: UInt64(metadata.st_ino),
            size: metadata.st_size,
            modifiedSeconds: Int64(metadata.st_mtimespec.tv_sec),
            modifiedNanoseconds: Int64(metadata.st_mtimespec.tv_nsec),
            ownerID: owner,
            permissions: UInt16(permissions))
    }

    private func launcherKind(
        at path: String
    ) throws(CodexExecutableValidationError) -> LauncherKind {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        } catch {
            throw .unavailable
        }
        defer { try? handle.close() }
        let data: Data
        do {
            data = try handle.read(upToCount: Self.maximumShebangBytes + 1) ?? Data()
        } catch {
            throw .unavailable
        }
        guard data.starts(with: Data("#!".utf8)) else { return .native }
        guard data.count <= Self.maximumShebangBytes,
            let newline = data.firstIndex(of: UInt8(ascii: "\n"))
        else { throw .unsupportedLauncher }
        var line = data[..<newline]
        if line.last == UInt8(ascii: "\r") { line = line.dropLast() }
        guard String(data: line, encoding: .utf8) == "#!/usr/bin/env node" else {
            throw .unsupportedLauncher
        }
        return .environmentNode
    }

    private func resolveNode(
        in pathComponents: [String]
    ) throws(CodexExecutableValidationError) -> CodexExecutableFileIdentity {
        for directory in pathComponents {
            let candidate = URL(fileURLWithPath: directory, isDirectory: true)
                .appending(path: "node").path
            do {
                return try identity(for: candidate)
            } catch .unavailable {
                continue
            } catch {
                throw error
            }
        }
        throw .missingNode
    }
}
