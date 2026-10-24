import Foundation

public enum ExistingStatusLineParseError: Error, Equatable, Sendable {
    /// Anything beyond one absolute or owner-home executable path, possibly quoted for spaces.
    case unsupported
}

/// Parses an existing `statusLine.command` without invoking a shell. It accepts exactly one
/// executable path: an unquoted path, an unquoted `~/` path, or a quoted absolute path.
public enum ExistingStatusLineParser {
    public static func parse(
        _ command: String, homeDirectory: URL
    ) throws(ExistingStatusLineParseError) -> String {
        guard !command.isEmpty, command.utf8.count <= 4_096 else { throw .unsupported }
        var bytes = Array(command.utf8)
        guard bytes.allSatisfy({ $0 >= 0x20 && $0 != 0x7F }) else { throw .unsupported }
        let quote = bytes.first
        if quote == UInt8(ascii: "\"") || quote == UInt8(ascii: "'") {
            guard bytes.count >= 3, bytes.last == quote else { throw .unsupported }
            bytes.removeFirst()
            bytes.removeLast()
            // Inside quotes only the closing quote, escapes, and expansion are special.
            let forbidden: Set<UInt8> = [
                UInt8(ascii: "\""), UInt8(ascii: "'"), UInt8(ascii: "\\"), UInt8(ascii: "$"),
                UInt8(ascii: "`"),
            ]
            guard !bytes.contains(where: forbidden.contains), bytes.first == UInt8(ascii: "/")
            else { throw .unsupported }
            return try validated(String(bytes: bytes, encoding: .utf8) ?? "")
        }
        let allowed = Set(
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._+@,:/-".utf8)
        if bytes.starts(with: Array("~/".utf8)) {
            let rest = bytes.dropFirst(2)
            guard !rest.isEmpty, rest.allSatisfy(allowed.contains) else { throw .unsupported }
            let home = homeDirectory.standardizedFileURL.path
            return try validated(home + "/" + (String(bytes: rest, encoding: .utf8) ?? ""))
        }
        guard bytes.first == UInt8(ascii: "/"), bytes.allSatisfy(allowed.contains) else {
            throw .unsupported
        }
        return try validated(command)
    }

    private static func validated(_ path: String) throws(ExistingStatusLineParseError) -> String {
        let components = path.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
        guard !components.isEmpty, !path.hasSuffix("/"),
            !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
        else { throw .unsupported }
        return path
    }
}
