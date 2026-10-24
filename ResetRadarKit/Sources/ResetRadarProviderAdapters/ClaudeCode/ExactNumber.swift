import Foundation

/// Exact numeric parsing that rejects precision loss instead of rounding.
enum ExactNumber {
    private struct Parts {
        let negative: Bool
        let integer: Substring
        let fraction: Substring
        let hasExponent: Bool
    }

    private static func parts(_ lexeme: String) -> Parts? {
        var text = Substring(lexeme)
        let negative = text.first == "-"
        if negative { text = text.dropFirst() }
        let hasExponent = text.contains(where: { $0 == "e" || $0 == "E" })
        let mantissa = text.prefix(while: { $0 != "e" && $0 != "E" })
        let pieces = mantissa.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count <= 2, let integer = pieces.first else { return nil }
        let fraction = pieces.count == 2 ? pieces[1] : ""
        return Parts(
            negative: negative, integer: integer, fraction: fraction, hasExponent: hasExponent)
    }

    private static func significantFraction(_ fraction: Substring) -> Substring {
        var result = fraction
        while result.last == "0" { result = result.dropLast() }
        return result
    }

    /// 0...100 with at most one significant fractional digit.
    static func percentage(_ lexeme: String) -> Double? {
        guard let parts = parts(lexeme), !parts.negative, !parts.hasExponent,
            parts.integer.count <= 3, significantFraction(parts.fraction).count <= 1,
            let value = Double(lexeme), value.isFinite, (0...100).contains(value)
        else { return nil }
        return value
    }

    /// An integral Unix-seconds instant from 1970 through 9999.
    static func unixSeconds(_ lexeme: String) -> Double? {
        guard let parts = parts(lexeme), !parts.negative, !parts.hasExponent,
            parts.fraction.isEmpty, !lexeme.contains("."), parts.integer.count <= 12,
            let value = Int64(lexeme), (0...253_402_300_799).contains(value)
        else { return nil }
        return Double(value)
    }

    /// A finite nonnegative counter that a Double represents exactly (at most 15 digits).
    static func activity(_ lexeme: String) -> Double? {
        guard let parts = parts(lexeme), !parts.negative, !parts.hasExponent else { return nil }
        let integer = parts.integer.drop(while: { $0 == "0" })
        let digits = integer.count + significantFraction(parts.fraction).count
        guard digits <= 15, let value = Double(lexeme), value.isFinite, value >= 0
        else { return nil }
        return value
    }
}
