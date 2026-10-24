import Foundation

/// Positions of one member inside an already-validated JSON object.
struct JSONMember: Equatable {
    let key: String
    let keyStart: Int
    let value: Range<Int>
}

/// A byte-range view over settings JSON that has passed `JSONStructuralPreflight`. It exists so
/// edits can replace one token and leave every other byte as it was.
struct SettingsScanner {
    let bytes: [UInt8]

    /// Members of the object whose `{` is at `open`, plus the index of its closing brace.
    func members(ofObjectAt open: Int) -> (members: [JSONMember], close: Int)? {
        guard open < bytes.count, bytes[open] == UInt8(ascii: "{") else { return nil }
        var index = open + 1
        var result: [JSONMember] = []
        skipWhitespace(&index)
        if index < bytes.count, bytes[index] == UInt8(ascii: "}") { return (result, index) }
        while index < bytes.count {
            skipWhitespace(&index)
            guard let member = parseMember(&index) else { return nil }
            result.append(member)
            skipWhitespace(&index)
            guard index < bytes.count else { return nil }
            if bytes[index] == UInt8(ascii: ",") {
                index += 1
            } else if bytes[index] == UInt8(ascii: "}") {
                return (result, index)
            } else {
                return nil
            }
        }
        return nil
    }

    private func parseMember(_ index: inout Int) -> JSONMember? {
        let keyStart = index
        guard let key = decodeString(at: &index) else { return nil }
        skipWhitespace(&index)
        guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { return nil }
        index += 1
        skipWhitespace(&index)
        let valueStart = index
        guard skipValue(&index) else { return nil }
        return JSONMember(key: key, keyStart: keyStart, value: valueStart..<index)
    }

    var rootOpen: Int? {
        var index = 0
        skipWhitespace(&index)
        return index < bytes.count && bytes[index] == UInt8(ascii: "{") ? index : nil
    }

    func decodeStringValue(_ range: Range<Int>) -> String? {
        var index = range.lowerBound
        guard let text = decodeString(at: &index), index == range.upperBound else { return nil }
        return text
    }

    func isObject(_ range: Range<Int>) -> Bool {
        bytes[range.lowerBound] == UInt8(ascii: "{")
    }

    private func skipWhitespace(_ index: inout Int) {
        while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
    }

    private func decodeString(at index: inout Int) -> String? {
        guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else { return nil }
        let start = index
        index += 1
        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "\\") {
                index += 2
                continue
            }
            if byte == UInt8(ascii: "\"") {
                index += 1
                let token = Data(bytes[start..<index])
                return (try? JSONDecoder().decode(String.self, from: token))
            }
            index += 1
        }
        return nil
    }

    private func skipValue(_ index: inout Int) -> Bool {
        guard index < bytes.count else { return false }
        switch bytes[index] {
        case UInt8(ascii: "\""):
            return decodeStringEnd(&index)
        case UInt8(ascii: "{"), UInt8(ascii: "["):
            return skipContainer(&index)
        default:
            let delimiters: Set<UInt8> = [
                0x20, 0x09, 0x0A, 0x0D, UInt8(ascii: ","), UInt8(ascii: "}"), UInt8(ascii: "]"),
            ]
            while index < bytes.count, !delimiters.contains(bytes[index]) {
                index += 1
            }
            return true
        }
    }

    private func skipContainer(_ index: inout Int) -> Bool {
        var depth = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "\"") {
                guard decodeStringEnd(&index) else { return false }
                continue
            }
            if byte == UInt8(ascii: "{") || byte == UInt8(ascii: "[") {
                depth += 1
            } else if byte == UInt8(ascii: "}") || byte == UInt8(ascii: "]") {
                depth -= 1
            }
            index += 1
            if depth == 0 { return true }
        }
        return false
    }

    private func decodeStringEnd(_ index: inout Int) -> Bool {
        index += 1
        while index < bytes.count {
            if bytes[index] == UInt8(ascii: "\\") {
                index += 2
            } else if bytes[index] == UInt8(ascii: "\"") {
                index += 1
                return true
            } else {
                index += 1
            }
        }
        return false
    }
}

enum JSONTokens {
    /// A JSON string token for `text`, escaping only what JSON requires.
    static func string(_ text: String) -> String {
        var result = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                if scalar.value < 0x20 {
                    result += String(format: "\\u%04x", scalar.value)
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result + "\""
    }
}
