import Foundation

/// Validates the exact v1 origin spelling before a credential is attached to a request.
public enum OriginGuard {
    public static func accepts(_ url: URL) -> Bool {
        let raw = url.absoluteString
        guard raw.hasPrefix("https://") else { return false }
        let hostname = String(raw.dropFirst("https://".count))
        let labels = hostname.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count == 4, labels[2] == "workers", labels[3] == "dev" else {
            return false
        }
        return labels[0...1].allSatisfy { label in
            guard !label.isEmpty, label.count <= 63,
                let first = label.utf8.first, let last = label.utf8.last,
                isLowerAlphaNumeric(first), isLowerAlphaNumeric(last)
            else { return false }
            return label.utf8.allSatisfy { isLowerAlphaNumeric($0) || $0 == UInt8(ascii: "-") }
        }
    }

    private static func isLowerAlphaNumeric(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
            || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
    }
}
