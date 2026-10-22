import Foundation

/// The one encoder/decoder pair for every wire and persisted record: ISO-8601 UTC dates with
/// millisecond precision and sorted keys.
public enum WireCoding {
    private static let dateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            // The format style truncates: round to the millisecond, then nudge half a millisecond
            // up so a binary-fraction date keeps its wire value.
            let millis = (date.timeIntervalSince1970 * 1000).rounded()
            try container.encode(
                dateStyle.format(Date(timeIntervalSince1970: (millis + 0.5) / 1000)))
        }
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            do {
                return try dateStyle.parse(text)
            } catch {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected an ISO-8601 UTC date with milliseconds.")
            }
        }
        return decoder
    }
}

/// A string-valued enum whose unrecognized wire values decode to `unknown` instead of failing,
/// so a newer writer's additions never discard the record.
public protocol TolerantEnum: RawRepresentable, Codable, Sendable where RawValue == String {
    static var unknown: Self { get }
}

extension TolerantEnum {
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? Self.unknown
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
