import Foundation

public enum RPCFrameError: Error, Equatable, Sendable {
    case payloadTooLarge
    case unterminatedPayload
}

/// Incrementally splits app-server JSON-lines output without decoding an oversized payload.
public struct BoundedRPCFrame: Sendable {
    public static let maximumPayloadBytes = 1_048_576

    private let maximumPayloadBytes: Int
    private var buffer = Data()
    private var failed = false

    public init(maximumPayloadBytes: Int = Self.maximumPayloadBytes) {
        precondition(maximumPayloadBytes > 0)
        self.maximumPayloadBytes = maximumPayloadBytes
    }

    public mutating func consume(_ chunk: Data) throws(RPCFrameError) -> [Data] {
        guard !failed else { throw .payloadTooLarge }
        buffer.append(chunk)
        var frames: [Data] = []
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            var payload = buffer[..<newline]
            if payload.last == UInt8(ascii: "\r") { payload = payload.dropLast() }
            guard payload.count <= maximumPayloadBytes else {
                failed = true
                buffer.removeAll(keepingCapacity: false)
                throw .payloadTooLarge
            }
            if !payload.isEmpty { frames.append(Data(payload)) }
            buffer.removeSubrange(...newline)
        }
        let pendingCR = buffer.last == UInt8(ascii: "\r")
        let countedBytes = buffer.count - (pendingCR ? 1 : 0)
        guard countedBytes <= maximumPayloadBytes else {
            failed = true
            buffer.removeAll(keepingCapacity: false)
            throw .payloadTooLarge
        }
        return frames
    }

    public mutating func finish() throws(RPCFrameError) {
        guard buffer.isEmpty else {
            failed = true
            buffer.removeAll(keepingCapacity: false)
            throw .unterminatedPayload
        }
    }
}
