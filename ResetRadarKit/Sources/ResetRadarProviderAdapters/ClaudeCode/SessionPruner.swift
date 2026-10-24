import Foundation

public enum SessionPruneError: Error, Equatable, Sendable {
    /// A lock, read, or deletion failed; cleanup never broadens after a failure.
    case unavailable
}

/// Deletes only regular, exactly named record files inside the validated session directory, under
/// the recorder's lock, after reopening and revalidating each candidate.
public struct SessionPruner: Sendable {
    private let file: SessionRecordFile
    private let reader: SessionRecordReader
    private let maximumAge: TimeInterval

    public init(
        file: SessionRecordFile, maximumAge: TimeInterval = StatusLineLimits.pruneAge
    ) {
        self.file = file
        reader = SessionRecordReader(file: file)
        self.maximumAge = maximumAge
    }

    /// Returns how many records were removed.
    @discardableResult
    public func prune(now: Date) throws(SessionPruneError) -> Int {
        let keys: [SessionKey]
        do {
            keys = try reader.recognizedKeys()
        } catch {
            throw .unavailable
        }
        guard !keys.isEmpty else { return 0 }
        do {
            return try file.withLock {
                var removed = 0
                for key in keys {
                    // A concurrent fresh write must win over stale enumeration metadata.
                    // An unreadable record is left for the scan to report; it is never deleted.
                    guard let record = try? file.read(key: key),
                        now.timeIntervalSince(record.pruneAnchor) > maximumAge
                    else { continue }
                    try file.remove(key: key)
                    removed += 1
                }
                return removed
            }
        } catch {
            throw .unavailable
        }
    }
}
