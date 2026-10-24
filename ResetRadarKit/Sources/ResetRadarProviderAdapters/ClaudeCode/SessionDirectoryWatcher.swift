import Darwin
import Foundation

public enum DirectoryWatchEvent: Equatable, Sendable {
    /// Directory contents changed (a record was created, replaced, or removed).
    case changed
    /// The watched directory itself was renamed, deleted, revoked, or otherwise invalidated.
    case rootInvalidated
}

/// One armed watch. Cancelling is idempotent and finishes `events`.
public protocol DirectoryWatchSession: Sendable {
    var events: AsyncStream<DirectoryWatchEvent> { get }
    func cancel()
}

public enum DirectoryWatchError: Error, Equatable, Sendable {
    case permissionDenied
    case unavailable
}

public protocol DirectoryWatchFactory: Sendable {
    func watch(directory: URL) throws(DirectoryWatchError) -> any DirectoryWatchSession
}

/// Watches the directory, not individual files, because atomic replacement swaps a file out from
/// under a file-level watch.
public struct DispatchDirectoryWatchFactory: DirectoryWatchFactory {
    public init() {}

    public func watch(directory: URL) throws(DirectoryWatchError) -> any DirectoryWatchSession {
        let descriptor = open(directory.path, O_EVTONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw errno == EACCES || errno == EPERM ? .permissionDenied : .unavailable
        }
        return DispatchDirectoryWatchSession(descriptor: descriptor)
    }
}

private final class DispatchDirectoryWatchSession: DirectoryWatchSession, @unchecked Sendable {
    let events: AsyncStream<DirectoryWatchEvent>
    private let source: any DispatchSourceFileSystemObject
    private let continuation: AsyncStream<DirectoryWatchEvent>.Continuation

    init(descriptor: Int32) {
        let pair = AsyncStream<DirectoryWatchEvent>.makeStream(bufferingPolicy: .bufferingNewest(8))
        events = pair.stream
        continuation = pair.continuation
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .link, .delete, .rename, .revoke],
            queue: DispatchQueue(label: "reset-radar.claude-session-watch"))
        let continuation = pair.continuation
        let source = source
        source.setEventHandler {
            let data = source.data
            if data.contains(.delete) || data.contains(.rename) || data.contains(.revoke) {
                continuation.yield(.rootInvalidated)
            } else {
                continuation.yield(.changed)
            }
        }
        source.setCancelHandler {
            close(descriptor)
            continuation.finish()
        }
        source.resume()
    }

    func cancel() {
        source.cancel()
    }

    deinit {
        source.cancel()
    }
}
