import Foundation
import ResetRadarDomain

/// The approved M11 bounds. A legitimate input past one of them is returned for owner review,
/// never silently widened.
public enum StatusLineLimits {
    public static let maximumInputBytes = 1_048_576
    public static let maximumStringBytes = 4_096
    public static let maximumNestingDepth = 32
    public static let maximumIdentifierBytes = 128
    public static let maximumRateLimitMembers = 128
    public static let maximumRecordBytes = 65_536
    public static let maximumSettingsBytes = 1_048_576
    public static let maximumExecutableBytes = 67_108_864
    public static let lockTimeout: TimeInterval = 1
    public static let maximumRecords = 1_024
    public static let maximumDirectoryEntries = 4_096
    public static let pruneAge: TimeInterval = 8 * 24 * 60 * 60
    public static let syntheticCommandTimeout: TimeInterval = 5
    public static let syntheticOutputBytes = 65_536
}

/// Printable ASCII grammars shared by the decoder and the record decoder.
enum StatusLineGrammar {
    static func isVersion(_ text: String) -> Bool {
        isBounded(text) { $0.isASCIIAlphanumeric || "._+-".utf8.contains($0) }
    }

    static func isWindowKind(_ text: String) -> Bool {
        isBounded(text) { ($0 >= 0x61 && $0 <= 0x7A) || ($0 >= 0x30 && $0 <= 0x39) || $0 == 0x5F }
    }

    private static func isBounded(_ text: String, allowed: (UInt8) -> Bool) -> Bool {
        let bytes = text.utf8
        return !bytes.isEmpty && bytes.count <= StatusLineLimits.maximumIdentifierBytes
            && bytes.allSatisfy(allowed)
    }

    static func durationMinutes(forKind kind: String) -> Int? {
        switch kind {
        case "five_hour": AccountWindow.StandardWindow.fiveHour.durationMinutes
        case "seven_day": AccountWindow.StandardWindow.weekly.durationMinutes
        default: nil
        }
    }
}

extension UInt8 {
    fileprivate var isASCIIAlphanumeric: Bool {
        (self >= 0x30 && self <= 0x39) || (self >= 0x41 && self <= 0x5A)
            || (self >= 0x61 && self <= 0x7A)
    }
}
