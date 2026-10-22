import Foundation

public enum MacLiveness {
    /// True while `generatedAt` is no older than three heartbeats. Affects provenance only; it
    /// never makes an old observation current.
    public static func isPublishing(snapshot: UsageSnapshot, now: Date) -> Bool {
        now.timeIntervalSince(snapshot.generatedAt) <= 3 * Double(snapshot.heartbeatSeconds)
    }
}
