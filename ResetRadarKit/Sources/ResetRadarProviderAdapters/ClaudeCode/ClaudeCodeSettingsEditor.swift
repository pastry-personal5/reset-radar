import CryptoKit
import Darwin
import Foundation

public enum ClaudeSettingsError: Error, Equatable, Sendable {
    /// The file or its directories are not owner-only regular files and directories.
    case unsafeFile
    case tooLarge
    /// Invalid JSON, a duplicate member, or nesting past the bound.
    case malformed
    case unavailable
    /// The bytes changed before replacement.
    case conflict
    /// Replacement occurred, but the installed bytes no longer matched during verification.
    case postWriteConflict
}

public enum ExistingStatusLine: Equatable, Sendable {
    case absent
    /// An object whose `type` is `command` and whose `command` is one string.
    case command(String)
    /// Present but not a shape this editor can safely edit.
    case unsupported
}

/// An in-memory reading of the user settings. The bytes never leave this module.
public struct ClaudeSettingsSnapshot: Equatable, Sendable {
    public static let absentRevision = "absent"

    public let exists: Bool
    /// SHA-256 of the exact original bytes, or `absentRevision`; opaque to callers.
    public let revision: String
    public let statusLine: ExistingStatusLine
    let bytes: Data
}

/// Reads, edits, and conditionally replaces only the default user `settings.json` `statusLine`
/// value. Edits are byte-range replacements so every other byte survives.
public struct ClaudeCodeSettingsEditor: Sendable {
    private let settingsURL: URL
    private let transactionFiles: OwnerOnlyConfigurationFiles
    private let ownerID: UInt32
    private let transactionRoot: URL
    private let afterReplacement: @Sendable () throws -> Void

    /// `transactionDirectory` holds the one fixed settings-transaction lock.
    public init(settingsURL: URL, transactionDirectory: URL, ownerID: UInt32 = getuid()) {
        self.init(
            settingsURL: settingsURL, transactionDirectory: transactionDirectory, ownerID: ownerID,
            afterReplacement: {})
    }

    init(
        settingsURL: URL, transactionDirectory: URL, ownerID: UInt32 = getuid(),
        afterReplacement: @escaping @Sendable () throws -> Void
    ) {
        self.settingsURL = settingsURL.standardizedFileURL
        transactionRoot = transactionDirectory.standardizedFileURL
        self.ownerID = ownerID
        self.afterReplacement = afterReplacement
        transactionFiles = OwnerOnlyConfigurationFiles(
            directoryURL: transactionDirectory, maximumBytes: StatusLineLimits.maximumRecordBytes,
            lockTimeout: StatusLineLimits.lockTimeout)
    }

    // MARK: Reading

    public func read() throws -> ClaudeSettingsSnapshot {
        guard try parentDirectoryExists() else { return Self.absent }
        let descriptor = open(settingsURL.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else {
            guard errno == ENOENT else { throw ClaudeSettingsError.unsafeFile }
            return Self.absent
        }
        defer { close(descriptor) }
        var metadata = Darwin.stat()
        guard fstat(descriptor, &metadata) == 0, (metadata.st_mode & S_IFMT) == S_IFREG,
            metadata.st_uid == ownerID, metadata.st_mode & 0o022 == 0
        else { throw ClaudeSettingsError.unsafeFile }
        guard metadata.st_size <= StatusLineLimits.maximumSettingsBytes else {
            throw ClaudeSettingsError.tooLarge
        }
        do {
            let data = try POSIXIO.readAll(
                from: descriptor, limit: StatusLineLimits.maximumSettingsBytes)
            return try Self.snapshot(of: data)
        } catch POSIXIO.ReadFailure.overLimit {
            throw ClaudeSettingsError.tooLarge
        } catch POSIXIO.ReadFailure.failed {
            throw ClaudeSettingsError.unavailable
        }
    }

    /// False when `~/.claude` does not exist yet; throws when it exists but is not owner-only.
    private func parentDirectoryExists() throws -> Bool {
        let parent = settingsURL.deletingLastPathComponent().path
        var directory = Darwin.stat()
        guard lstat(parent, &directory) == 0 else {
            guard errno == ENOENT else { throw ClaudeSettingsError.unsafeFile }
            return false
        }
        guard (directory.st_mode & S_IFMT) == S_IFDIR, directory.st_uid == ownerID,
            directory.st_mode & 0o022 == 0,
            let canonical = ExecutableIdentityValidator.resolve(parent),
            ExecutableIdentityValidator.ancestorsAreTrusted(
                of: canonical + "/x", ownerID: ownerID)
        else { throw ClaudeSettingsError.unsafeFile }
        return true
    }

    static func snapshot(of data: Data) throws -> ClaudeSettingsSnapshot {
        do {
            try JSONStructuralPreflight.validate(
                data, maximumStringBytes: StatusLineLimits.maximumSettingsBytes,
                maximumNestingDepth: StatusLineLimits.maximumNestingDepth)
        } catch {
            throw ClaudeSettingsError.malformed
        }
        let scanner = SettingsScanner(bytes: Array(data))
        guard let root = scanner.rootOpen, let top = scanner.members(ofObjectAt: root) else {
            throw ClaudeSettingsError.malformed
        }
        let revision = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let status: ExistingStatusLine
        if let member = top.members.first(where: { $0.key == "statusLine" }) {
            status = Self.classify(member, scanner: scanner)
        } else {
            status = .absent
        }
        return ClaudeSettingsSnapshot(
            exists: true, revision: revision, statusLine: status, bytes: data)
    }

    private static var absent: ClaudeSettingsSnapshot {
        ClaudeSettingsSnapshot(
            exists: false, revision: ClaudeSettingsSnapshot.absentRevision, statusLine: .absent,
            bytes: Data())
    }

    private static func classify(
        _ member: JSONMember, scanner: SettingsScanner
    ) -> ExistingStatusLine {
        guard scanner.isObject(member.value),
            let inner = scanner.members(ofObjectAt: member.value.lowerBound),
            let type = inner.members.first(where: { $0.key == "type" }),
            scanner.decodeStringValue(type.value) == "command",
            let command = inner.members.first(where: { $0.key == "command" }),
            let text = scanner.decodeStringValue(command.value)
        else { return .unsupported }
        return .command(text)
    }

    // MARK: Pure edits

    /// Adds `"statusLine": {"type": "command", "command": …}` after the last top-level member.
    static func inserting(
        statusLineCommand command: String, into snapshot: ClaudeSettingsSnapshot
    ) throws -> Data {
        let member =
            "\"statusLine\": {\"type\": \"command\", \"command\": \(JSONTokens.string(command))}"
        guard snapshot.exists else { return Data("{\n  \(member)\n}\n".utf8) }
        let scanner = SettingsScanner(bytes: Array(snapshot.bytes))
        guard let root = scanner.rootOpen, let top = scanner.members(ofObjectAt: root),
            !top.members.contains(where: { $0.key == "statusLine" })
        else { throw ClaudeSettingsError.malformed }
        var bytes = scanner.bytes
        if let last = top.members.last {
            bytes.insert(contentsOf: Array(",\n  \(member)".utf8), at: last.value.upperBound)
        } else {
            bytes.insert(contentsOf: Array(member.utf8), at: root + 1)
        }
        return Data(bytes)
    }

    /// Replaces only the string token of an accepted `statusLine.command`.
    static func replacingCommand(
        in snapshot: ClaudeSettingsSnapshot, with command: String
    ) throws -> Data {
        let scanner = SettingsScanner(bytes: Array(snapshot.bytes))
        guard let root = scanner.rootOpen, let top = scanner.members(ofObjectAt: root),
            let member = top.members.first(where: { $0.key == "statusLine" }),
            let inner = scanner.members(ofObjectAt: member.value.lowerBound),
            let target = inner.members.first(where: { $0.key == "command" })
        else { throw ClaudeSettingsError.malformed }
        var bytes = scanner.bytes
        bytes.replaceSubrange(target.value, with: Array(JSONTokens.string(command).utf8))
        return Data(bytes)
    }

    /// Removes a `statusLine` member that is exactly Reset Radar's minimal object.
    static func removingMinimalStatusLine(
        in snapshot: ClaudeSettingsSnapshot, command: String
    ) -> Data? {
        let scanner = SettingsScanner(bytes: Array(snapshot.bytes))
        guard let root = scanner.rootOpen, let top = scanner.members(ofObjectAt: root),
            let index = top.members.firstIndex(where: { $0.key == "statusLine" }),
            let inner = scanner.members(ofObjectAt: top.members[index].value.lowerBound),
            inner.members.count == 2,
            Set(inner.members.map(\.key)) == ["type", "command"],
            case .command(let current) = classify(top.members[index], scanner: scanner),
            current == command
        else { return nil }
        let member = top.members[index]
        var bytes = scanner.bytes
        if index > 0 {
            bytes.removeSubrange(top.members[index - 1].value.upperBound..<member.value.upperBound)
        } else if index + 1 < top.members.count {
            bytes.removeSubrange(member.keyStart..<top.members[index + 1].keyStart)
        } else {
            bytes.removeSubrange(member.keyStart..<member.value.upperBound)
        }
        return Data(bytes)
    }

    // MARK: Conditional replacement

    /// Replaces the file only if its bytes still match `expected`, checking immediately before
    /// the rename and again afterwards. This serializes Reset Radar's own transactions; it is not
    /// a compare-and-swap against an uncooperative external writer.
    public func replace(
        expecting expected: ClaudeSettingsSnapshot, with newBytes: Data
    ) throws {
        guard newBytes.count <= StatusLineLimits.maximumSettingsBytes else {
            throw ClaudeSettingsError.tooLarge
        }
        guard (try? Self.snapshot(of: newBytes)) != nil else { throw ClaudeSettingsError.malformed }
        try withTransactionLock { try performReplace(expecting: expected, with: newBytes) }
    }

    private func requireRevision(_ revision: String) throws {
        guard try read().revision == revision else { throw ClaudeSettingsError.conflict }
    }

    private func performReplace(
        expecting expected: ClaudeSettingsSnapshot, with newBytes: Data
    ) throws {
        try requireRevision(expected.revision)
        let directory = settingsURL.deletingLastPathComponent()
        if mkdir(directory.path, 0o700) != 0, errno != EEXIST {
            throw ClaudeSettingsError.unavailable
        }
        _ = try read()  // revalidates the directory after a possible creation
        let mode = expected.exists ? Self.existingMode(settingsURL) : 0o600
        let temporary = directory.appending(path: ".reset-radar-\(UUID().uuidString).tmp")
        guard POSIXIO.writeExclusive(newBytes, to: temporary, mode: mode) else {
            throw ClaudeSettingsError.unavailable
        }
        var cleanup = true
        defer { if cleanup { unlink(temporary.path) } }
        try requireRevision(expected.revision)
        guard rename(temporary.path, settingsURL.path) == 0 else {
            throw ClaudeSettingsError.unavailable
        }
        cleanup = false
        do {
            try afterReplacement()
            try requireRevision(
                SHA256.hash(data: newBytes).map { String(format: "%02x", $0) }.joined())
        } catch {
            throw ClaudeSettingsError.postWriteConflict
        }
    }

    private static func existingMode(_ url: URL) -> mode_t {
        var metadata = Darwin.stat()
        guard lstat(url.path, &metadata) == 0 else { return 0o600 }
        return metadata.st_mode & 0o7777
    }

    private func withTransactionLock<T>(_ body: () throws -> T) throws -> T {
        do {
            try SessionRecordFile.ensureOwnerOnlyDirectory(
                transactionRoot.deletingLastPathComponent())
            return try transactionFiles.withLock(body)
        } catch let error as ProviderAccountCatalogStoreError {
            throw error == .unsafeLocation ? ClaudeSettingsError.unsafeFile : .unavailable
        } catch let error as SessionRecordError {
            throw error == .unsafeLocation ? ClaudeSettingsError.unsafeFile : .unavailable
        }
    }
}
