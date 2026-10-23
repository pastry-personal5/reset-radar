import Foundation

/// Exponential backoff with full jitter: a 30-second base doubling to a 15-minute cap.
public enum BackoffPolicy {
    public static let base: TimeInterval = 30
    public static let cap: TimeInterval = 900

    /// `randomUnit` (clamped to `0...1`) scales the ceiling, so the delay is uniform in
    /// `0...ceiling`. No failures means no delay.
    public static func delay(afterFailures failures: Int, randomUnit: Double) -> TimeInterval {
        guard failures > 0 else { return 0 }
        let unit = randomUnit.isNaN ? 0 : min(max(randomUnit, 0), 1)
        // The cap is reached by the sixth failure; bounding the exponent avoids overflow.
        let ceiling = min(base * pow(2, Double(min(failures - 1, 10))), cap)
        return unit * ceiling
    }
}
