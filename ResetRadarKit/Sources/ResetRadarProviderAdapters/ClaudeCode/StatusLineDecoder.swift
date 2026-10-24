import Foundation

public enum StatusLineDecodingError: Error, Equatable, Sendable {
    case inputTooLarge
    case malformedJSON
    case duplicateMember
    case nestingTooDeep
    case stringTooLarge
    case tooManyLimits
    case invalidVersion
    case invalidSessionID
    case invalidActivity
    case invalidWindow
}

/// One normal rate-limit window, reduced to its allowlisted fields.
public struct StatusLineWindow: Equatable, Sendable {
    public let kind: String
    public let usedPercent: Double
    public let resetsAt: Date?

    public init(kind: String, usedPercent: Double, resetsAt: Date?) {
        self.kind = kind
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

/// The only data that crosses from a status-line invocation into the recorder.
public struct DecodedStatusLine: Equatable, Sendable {
    public let version: String
    public let sessionKey: SessionKey
    /// Cumulative API duration; nil when the input carries none.
    public let activity: Double?
    /// Valid normal windows only, sorted by kind. `spend_limit` never appears.
    public let windows: [StatusLineWindow]

    public init(
        version: String, sessionKey: SessionKey, activity: Double?, windows: [StatusLineWindow]
    ) {
        self.version = version
        self.sessionKey = sessionKey
        self.activity = activity
        self.windows = windows
    }
}

/// Decodes one complete in-bound status-line payload without Foundation's lossy number path.
/// Errors are enum-backed and carry no input text.
public enum StatusLineDecoder {
    public static func decode(_ data: Data) throws(StatusLineDecodingError) -> DecodedStatusLine {
        guard data.count <= StatusLineLimits.maximumInputBytes else { throw .inputTooLarge }
        guard String(data: data, encoding: .utf8) != nil else { throw .malformedJSON }
        var parser = StatusLineParser(bytes: Array(data))
        return try parser.parseDocument()
    }
}

extension StatusLineParser {
    mutating func parseDocument() throws(StatusLineDecodingError) -> DecodedStatusLine {
        skipWhitespace()
        guard peek == UInt8(ascii: "{") else { throw .malformedJSON }
        var version: String?
        var sessionID: String?
        var activity: Double?
        var windows: [StatusLineWindow] = []
        try parseObject(depth: 1) { parser, key in
            switch key {
            case "version":
                version = try parser.parseAllowlistedString(failure: .invalidVersion)
            case "session_id":
                sessionID = try parser.parseAllowlistedString(failure: .invalidSessionID)
            case "cost":
                activity = try parser.parseCost()
            case "rate_limits":
                windows = try parser.parseRateLimits()
            default:
                try parser.skipValue(depth: 2)
            }
        }
        skipWhitespace()
        guard index == bytes.count else { throw .malformedJSON }
        guard let version, StatusLineGrammar.isVersion(version) else { throw .invalidVersion }
        guard let sessionID, !sessionID.isEmpty else { throw .invalidSessionID }
        return DecodedStatusLine(
            version: version, sessionKey: SessionKey(sessionID: sessionID), activity: activity,
            windows: windows.sorted { $0.kind < $1.kind })
    }

    // MARK: Allowlisted members

    mutating func parseCost() throws(StatusLineDecodingError) -> Double? {
        guard peek == UInt8(ascii: "{") else {
            if consumeNull() { return nil }
            try skipValue(depth: 2)
            return nil
        }
        var activity: Double?
        try parseObject(depth: 2) { parser, key in
            if key == "total_api_duration_ms" {
                if parser.consumeNull() { return }
                let lexeme = try parser.parseNumberLexeme(failure: .invalidActivity)
                guard let value = ExactNumber.activity(lexeme) else {
                    throw StatusLineDecodingError.invalidActivity
                }
                activity = value
            } else {
                try parser.skipValue(depth: 3)
            }
        }
        return activity
    }

    mutating func parseRateLimits() throws(StatusLineDecodingError) -> [StatusLineWindow] {
        guard peek == UInt8(ascii: "{") else {
            if consumeNull() { return [] }
            throw .invalidWindow
        }
        var windows: [StatusLineWindow] = []
        var members = 0
        try parseObject(depth: 2) { parser, key in
            members += 1
            guard members <= StatusLineLimits.maximumRateLimitMembers else {
                throw StatusLineDecodingError.tooManyLimits
            }
            if key == "spend_limit" {
                try parser.skipValue(depth: 3)
                return
            }
            windows.append(try parser.parseWindow(kind: key))
        }
        return windows
    }

    mutating func parseWindow(kind: String) throws(StatusLineDecodingError) -> StatusLineWindow {
        guard peek == UInt8(ascii: "{") else {
            try skipValue(depth: 3)
            throw .invalidWindow
        }
        var percent: Double?
        var resetsAt: Date?
        var invalid = false
        try parseObject(depth: 3) { parser, key in
            switch key {
            case "used_percentage":
                let lexeme = try parser.parseNumberLexemeOrOther()
                if let lexeme, let value = ExactNumber.percentage(lexeme) {
                    percent = value
                } else {
                    invalid = true
                }
            case "resets_at":
                if parser.consumeNull() { return }
                let lexeme = try parser.parseNumberLexemeOrOther()
                if let lexeme, let seconds = ExactNumber.unixSeconds(lexeme) {
                    resetsAt = Date(timeIntervalSince1970: seconds)
                } else {
                    invalid = true
                }
            default:
                try parser.skipValue(depth: 4)
            }
        }
        guard !invalid, let percent, StatusLineGrammar.isWindowKind(kind) else {
            throw .invalidWindow
        }
        return StatusLineWindow(kind: kind, usedPercent: percent, resetsAt: resetsAt)
    }

}
