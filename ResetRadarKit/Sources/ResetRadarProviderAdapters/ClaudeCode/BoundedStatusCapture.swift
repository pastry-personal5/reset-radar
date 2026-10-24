import Foundation

/// Retains a complete status-line input only while it stays within the ceiling. It never returns a
/// truncated payload and never decides whether a composed child keeps receiving bytes.
public struct BoundedStatusCapture: Sendable {
    private let maximumBytes: Int
    private var buffer = Data()
    public private(set) var isAbandoned = false

    public init(maximumBytes: Int = StatusLineLimits.maximumInputBytes) {
        precondition(maximumBytes > 0)
        self.maximumBytes = maximumBytes
    }

    public mutating func append(_ chunk: Data) {
        guard !isAbandoned else { return }
        guard chunk.count <= maximumBytes - buffer.count else {
            isAbandoned = true
            buffer = Data()
            return
        }
        buffer.append(chunk)
    }

    /// The complete in-bound input, or nil once any byte exceeded the ceiling.
    public var completeInput: Data? { isAbandoned ? nil : buffer }
}
