import Darwin
import Foundation

public enum SessionScanError: Error, Equatable, Sendable {
    /// The directory or a record could not be read for lack of permission.
    case permissionDenied
    /// A temporary filesystem failure.
    case unavailable
    /// A malformed, incompatible, unsafe, or over-bound recognized record or directory.
    case incompatible
}

/// Streams the session directory and returns every recognized record. One bad recognized record
/// fails the whole physical scan; unrelated entries are ignored while enumeration stays in bound.
public struct SessionRecordReader: Sendable {
    private let file: SessionRecordFile
    private let maximumRecords: Int
    private let maximumEntries: Int

    public init(
        file: SessionRecordFile, maximumRecords: Int = StatusLineLimits.maximumRecords,
        maximumEntries: Int = StatusLineLimits.maximumDirectoryEntries
    ) {
        self.file = file
        self.maximumRecords = maximumRecords
        self.maximumEntries = maximumEntries
    }

    /// An absent directory is an empty scan: nothing has been recorded yet.
    public func scan() throws(SessionScanError) -> [SessionRecord] {
        let keys = try recognizedKeys()
        var records: [SessionRecord] = []
        for key in keys {
            do {
                if let record = try file.read(key: key) { records.append(record) }
            } catch let error as SessionRecordError {
                throw Self.map(error)
            } catch {
                throw .unavailable
            }
        }
        return records
    }

    /// Keys of every recognized record name, enumerated without materializing the directory.
    func recognizedKeys() throws(SessionScanError) -> [SessionKey] {
        guard let directory = try openDirectory() else { return [] }
        defer { closedir(directory) }
        var keys: [SessionKey] = []
        var visited = 0
        errno = 0
        while let entry = readdir(directory) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) {
                    String(cString: $0)
                }
            }
            if name == "." || name == ".." { continue }
            visited += 1
            guard visited <= maximumEntries else { throw .incompatible }
            if let key = Self.key(fromFileName: name) {
                keys.append(key)
                guard keys.count <= maximumRecords else { throw .incompatible }
            }
        }
        guard errno == 0 else { throw .unavailable }
        return keys.sorted { $0.hex < $1.hex }
    }

    static func key(fromFileName name: String) -> SessionKey? {
        guard name.hasSuffix(".json"), let key = SessionKey(hex: String(name.dropLast(5)))
        else { return nil }
        return key
    }

    private func openDirectory() throws(SessionScanError) -> UnsafeMutablePointer<DIR>? {
        var metadata = Darwin.stat()
        guard lstat(file.directoryURL.path, &metadata) == 0 else {
            switch errno {
            case ENOENT: return nil
            case EACCES, EPERM: throw .permissionDenied
            default: throw .unavailable
            }
        }
        guard (metadata.st_mode & S_IFMT) == S_IFDIR, metadata.st_uid == getuid(),
            metadata.st_mode & 0o022 == 0
        else { throw .incompatible }
        guard let directory = opendir(file.directoryURL.path) else {
            throw errno == EACCES || errno == EPERM ? .permissionDenied : .unavailable
        }
        return directory
    }

    private static func map(_ error: SessionRecordError) -> SessionScanError {
        switch error {
        case .unavailable, .notFound: .unavailable
        case .unsafeLocation, .incompatibleRecord, .recordTooLarge: .incompatible
        }
    }
}
