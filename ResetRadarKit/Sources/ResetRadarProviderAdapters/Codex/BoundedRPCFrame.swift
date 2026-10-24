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

public enum JSONPreflightError: Error, Equatable, Sendable {
    case malformed
    case duplicateObjectKey
    case stringTooLarge
    case nestingTooDeep
}

/// A redacted lexical/structural pass that runs before semantic response decoding.
public enum JSONStructuralPreflight {
    public static let maximumStringBytes = 4_096
    public static let maximumNestingDepth = 32

    public static func validate(
        _ data: Data, maximumStringBytes: Int = Self.maximumStringBytes,
        maximumNestingDepth: Int = Self.maximumNestingDepth
    ) throws(JSONPreflightError) {
        guard String(data: data, encoding: .utf8) != nil else { throw .malformed }
        var parser = Parser(
            bytes: Array(data), maximumStringBytes: maximumStringBytes,
            maximumNestingDepth: maximumNestingDepth)
        try parser.parseDocument()
    }
}

private struct Parser {
    private static let whitespace = Set(" \t\r\n".utf8)

    let bytes: [UInt8]
    let maximumStringBytes: Int
    let maximumNestingDepth: Int
    var index = 0

    mutating func parseDocument() throws(JSONPreflightError) {
        skipWhitespace()
        try parseValue(depth: 0)
        skipWhitespace()
        guard index == bytes.count else { throw .malformed }
    }

    private mutating func parseValue(depth: Int) throws(JSONPreflightError) {
        guard index < bytes.count else { throw .malformed }
        switch bytes[index] {
        case UInt8(ascii: "{"):
            try parseObject(depth: depth + 1)
        case UInt8(ascii: "["):
            try parseArray(depth: depth + 1)
        case UInt8(ascii: "\""):
            _ = try parseString()
        case UInt8(ascii: "t"):
            try parseLiteral("true")
        case UInt8(ascii: "f"):
            try parseLiteral("false")
        case UInt8(ascii: "n"):
            try parseLiteral("null")
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"):
            try parseNumber()
        default:
            throw .malformed
        }
    }

    private mutating func parseObject(depth: Int) throws(JSONPreflightError) {
        guard depth <= maximumNestingDepth else { throw .nestingTooDeep }
        index += 1
        skipWhitespace()
        if take(UInt8(ascii: "}")) { return }
        var keys: Set<String> = []
        while true {
            guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else {
                throw .malformed
            }
            let key = try parseString()
            guard keys.insert(key).inserted else { throw .duplicateObjectKey }
            skipWhitespace()
            guard take(UInt8(ascii: ":")) else { throw .malformed }
            skipWhitespace()
            try parseValue(depth: depth)
            skipWhitespace()
            if take(UInt8(ascii: "}")) { return }
            guard take(UInt8(ascii: ",")) else { throw .malformed }
            skipWhitespace()
        }
    }

    private mutating func parseArray(depth: Int) throws(JSONPreflightError) {
        guard depth <= maximumNestingDepth else { throw .nestingTooDeep }
        index += 1
        skipWhitespace()
        if take(UInt8(ascii: "]")) { return }
        while true {
            try parseValue(depth: depth)
            skipWhitespace()
            if take(UInt8(ascii: "]")) { return }
            guard take(UInt8(ascii: ",")) else { throw .malformed }
            skipWhitespace()
        }
    }

    private mutating func parseString() throws(JSONPreflightError) -> String {
        let start = index
        index += 1
        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "\"") {
                index += 1
                let encoded = Data(bytes[start..<index])
                let wrapped = Data([UInt8(ascii: "[")]) + encoded + Data([UInt8(ascii: "]")])
                guard
                    let decoded = try? JSONSerialization.jsonObject(with: wrapped) as? [String],
                    let string = decoded.first
                else { throw .malformed }
                guard string.utf8.count <= maximumStringBytes else { throw .stringTooLarge }
                return string
            }
            guard byte >= 0x20 else { throw .malformed }
            if byte == UInt8(ascii: "\\") {
                index += 1
                guard index < bytes.count else { throw .malformed }
                if bytes[index] == UInt8(ascii: "u") {
                    guard index + 4 < bytes.count else { throw .malformed }
                    index += 4
                }
            }
            index += 1
        }
        throw .malformed
    }

    private mutating func parseLiteral(_ literal: StaticString) throws(JSONPreflightError) {
        let expected = Array(String(describing: literal).utf8)
        guard index + expected.count <= bytes.count,
            Array(bytes[index..<(index + expected.count)]) == expected
        else { throw .malformed }
        index += expected.count
    }

    private mutating func parseNumber() throws(JSONPreflightError) {
        if take(UInt8(ascii: "-")), index == bytes.count { throw .malformed }
        try parseInteger()
        try parseFraction()
        try parseExponent()
    }

    private mutating func parseInteger() throws(JSONPreflightError) {
        if take(UInt8(ascii: "0")) {
            if index < bytes.count, bytes[index].isASCIIDigit { throw .malformed }
        } else {
            guard takeDigit(in: UInt8(ascii: "1")...UInt8(ascii: "9")) else { throw .malformed }
            while index < bytes.count, bytes[index].isASCIIDigit { index += 1 }
        }
    }

    private mutating func parseFraction() throws(JSONPreflightError) {
        guard take(UInt8(ascii: ".")) else { return }
        try takeRequiredDigit()
        while index < bytes.count, bytes[index].isASCIIDigit { index += 1 }
    }

    private mutating func parseExponent() throws(JSONPreflightError) {
        guard take(UInt8(ascii: "e")) || take(UInt8(ascii: "E")) else { return }
        _ = take(UInt8(ascii: "+")) || take(UInt8(ascii: "-"))
        try takeRequiredDigit()
        while index < bytes.count, bytes[index].isASCIIDigit { index += 1 }
    }

    private mutating func takeRequiredDigit() throws(JSONPreflightError) {
        guard takeDigit(in: UInt8(ascii: "0")...UInt8(ascii: "9")) else { throw .malformed }
    }

    private mutating func skipWhitespace() {
        while index < bytes.count, Self.whitespace.contains(bytes[index]) {
            index += 1
        }
    }

    private mutating func take(_ byte: UInt8) -> Bool {
        guard index < bytes.count, bytes[index] == byte else { return false }
        index += 1
        return true
    }

    private mutating func takeDigit(in range: ClosedRange<UInt8>) -> Bool {
        guard index < bytes.count, range.contains(bytes[index]) else { return false }
        index += 1
        return true
    }
}

extension UInt8 {
    fileprivate var isASCIIDigit: Bool { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(self) }
}
