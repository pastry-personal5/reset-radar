import Foundation

struct StatusLineParser {
    let bytes: [UInt8]
    var index = 0

    init(bytes: [UInt8]) { self.bytes = bytes }

    // MARK: Structure

    /// Parses an object, rejecting duplicate members, and hands each value position to `member`.
    mutating func parseObject(
        depth: Int,
        member: (inout StatusLineParser, String) throws -> Void
    ) throws(StatusLineDecodingError) {
        guard depth <= StatusLineLimits.maximumNestingDepth else { throw .nestingTooDeep }
        index += 1  // {
        skipWhitespace()
        if take(UInt8(ascii: "}")) { return }
        var seen = Set<String>()
        while true {
            skipWhitespace()
            guard peek == UInt8(ascii: "\"") else { throw .malformedJSON }
            let key = try parseString(limit: StatusLineLimits.maximumStringBytes)
            guard seen.insert(key).inserted else { throw .duplicateMember }
            skipWhitespace()
            guard take(UInt8(ascii: ":")) else { throw .malformedJSON }
            skipWhitespace()
            do {
                try member(&self, key)
            } catch let error as StatusLineDecodingError {
                throw error
            } catch {
                throw .malformedJSON
            }
            skipWhitespace()
            if take(UInt8(ascii: ",")) { continue }
            guard take(UInt8(ascii: "}")) else { throw .malformedJSON }
            return
        }
    }

    /// Validates and discards any value; unknown strings stay under the total-input bound only.
    mutating func skipValue(depth: Int) throws(StatusLineDecodingError) {
        guard let byte = peek else { throw .malformedJSON }
        switch byte {
        case UInt8(ascii: "{"):
            try parseObject(depth: depth) { parser, _ in try parser.skipValue(depth: depth + 1) }
        case UInt8(ascii: "["):
            try skipArray(depth: depth)
        case UInt8(ascii: "\""):
            _ = try parseString(limit: nil)
        case UInt8(ascii: "t"):
            try consumeLiteral("true")
        case UInt8(ascii: "f"):
            try consumeLiteral("false")
        case UInt8(ascii: "n"):
            try consumeLiteral("null")
        default:
            _ = try parseNumberLexeme(failure: .malformedJSON)
        }
    }

    mutating func skipArray(depth: Int) throws(StatusLineDecodingError) {
        guard depth <= StatusLineLimits.maximumNestingDepth else { throw .nestingTooDeep }
        index += 1  // [
        skipWhitespace()
        if take(UInt8(ascii: "]")) { return }
        while true {
            skipWhitespace()
            try skipValue(depth: depth + 1)
            skipWhitespace()
            if take(UInt8(ascii: ",")) { continue }
            guard take(UInt8(ascii: "]")) else { throw .malformedJSON }
            return
        }
    }

    // MARK: Tokens

    mutating func parseAllowlistedString(
        failure: StatusLineDecodingError
    ) throws(StatusLineDecodingError) -> String {
        guard peek == UInt8(ascii: "\"") else {
            try skipValue(depth: 2)
            throw failure
        }
        do {
            return try parseString(limit: StatusLineLimits.maximumStringBytes)
        } catch .stringTooLarge {
            throw failure
        }
    }

    /// Parses a JSON string. `limit` bounds the decoded UTF-8 bytes; nil skips the bound.
    mutating func parseString(limit: Int?) throws(StatusLineDecodingError) -> String {
        index += 1  // opening quote
        var decoded = [UInt8]()
        var count = 0
        while true {
            guard index < bytes.count else { throw .malformedJSON }
            let byte = bytes[index]
            index += 1
            if byte == UInt8(ascii: "\"") {
                guard limit != nil else { return "" }
                return String(bytes: decoded, encoding: .utf8) ?? ""
            }
            let piece: [UInt8]
            if byte == UInt8(ascii: "\\") {
                piece = try parseEscape()
            } else if byte < 0x20 {
                throw .malformedJSON
            } else {
                piece = [byte]
            }
            count += piece.count
            if let limit, count > limit { throw .stringTooLarge }
            if limit != nil { decoded.append(contentsOf: piece) }
        }
    }

    private static let simpleEscapes: [UInt8: UInt32] = [
        UInt8(ascii: "\""): 0x22, UInt8(ascii: "\\"): 0x5C, UInt8(ascii: "/"): 0x2F,
        UInt8(ascii: "b"): 0x08, UInt8(ascii: "f"): 0x0C, UInt8(ascii: "n"): 0x0A,
        UInt8(ascii: "r"): 0x0D, UInt8(ascii: "t"): 0x09,
    ]

    private mutating func parseEscape() throws(StatusLineDecodingError) -> [UInt8] {
        guard index < bytes.count else { throw .malformedJSON }
        let escape = bytes[index]
        index += 1
        let scalar: UInt32
        if escape == UInt8(ascii: "u") {
            scalar = try parseUnicodeEscape()
        } else if let simple = Self.simpleEscapes[escape] {
            scalar = simple
        } else {
            throw .malformedJSON
        }
        guard let unicode = Unicode.Scalar(scalar) else { throw .malformedJSON }
        return Array(String(Character(unicode)).utf8)
    }

    private mutating func parseUnicodeEscape() throws(StatusLineDecodingError) -> UInt32 {
        let value = try parseHex4()
        if (0xD800...0xDBFF).contains(value) {
            guard take(UInt8(ascii: "\\")), take(UInt8(ascii: "u")) else { throw .malformedJSON }
            let low = try parseHex4()
            guard (0xDC00...0xDFFF).contains(low) else { throw .malformedJSON }
            return 0x10000 + ((value - 0xD800) << 10) + (low - 0xDC00)
        }
        if (0xDC00...0xDFFF).contains(value) { throw .malformedJSON }
        return value
    }

    mutating func parseHex4() throws(StatusLineDecodingError) -> UInt32 {
        guard index + 4 <= bytes.count else { throw .malformedJSON }
        var value: UInt32 = 0
        for _ in 0..<4 {
            let digit = bytes[index]
            index += 1
            let nibble: UInt32
            switch digit {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): nibble = UInt32(digit - UInt8(ascii: "0"))
            case UInt8(ascii: "a")...UInt8(ascii: "f"):
                nibble = UInt32(digit - UInt8(ascii: "a")) + 10
            case UInt8(ascii: "A")...UInt8(ascii: "F"):
                nibble = UInt32(digit - UInt8(ascii: "A")) + 10
            default: throw .malformedJSON
            }
            value = value << 4 | nibble
        }
        return value
    }

    /// A strict JSON number lexeme; any other token is the caller's `failure`.
    mutating func parseNumberLexeme(
        failure: StatusLineDecodingError
    ) throws(StatusLineDecodingError) -> String {
        guard let byte = peek, byte == UInt8(ascii: "-") || (0x30...0x39).contains(byte) else {
            throw failure
        }
        let start = index
        _ = take(UInt8(ascii: "-"))
        guard let first = peek, (0x30...0x39).contains(first) else { throw .malformedJSON }
        if first == UInt8(ascii: "0") {
            index += 1
        } else {
            _ = skipDigits()
        }
        if take(UInt8(ascii: ".")) {
            guard skipDigits() else { throw .malformedJSON }
        }
        if let marker = peek, marker == UInt8(ascii: "e") || marker == UInt8(ascii: "E") {
            index += 1
            if let sign = peek, sign == UInt8(ascii: "+") || sign == UInt8(ascii: "-") {
                index += 1
            }
            guard skipDigits() else { throw .malformedJSON }
        }
        return String(bytes: bytes[start..<index], encoding: .utf8) ?? ""
    }

    private mutating func skipDigits() -> Bool {
        let start = index
        while let digit = peek, (0x30...0x39).contains(digit) { index += 1 }
        return index > start
    }

    /// A number lexeme, or nil after skipping any other well-formed value.
    mutating func parseNumberLexemeOrOther() throws(StatusLineDecodingError) -> String? {
        if let byte = peek, byte == UInt8(ascii: "-") || (0x30...0x39).contains(byte) {
            return try parseNumberLexeme(failure: .malformedJSON)
        }
        try skipValue(depth: 4)
        return nil
    }

    mutating func consumeNull() -> Bool {
        guard bytes[index...].starts(with: Array("null".utf8)) else { return false }
        index += 4
        return true
    }

    mutating func consumeLiteral(_ text: String) throws(StatusLineDecodingError) {
        let literal = Array(text.utf8)
        guard bytes[index...].starts(with: literal) else { throw .malformedJSON }
        index += literal.count
    }

    var peek: UInt8? { index < bytes.count ? bytes[index] : nil }

    mutating func take(_ byte: UInt8) -> Bool {
        guard peek == byte else { return false }
        index += 1
        return true
    }

    mutating func skipWhitespace() {
        while let byte = peek, byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
            index += 1
        }
    }
}
