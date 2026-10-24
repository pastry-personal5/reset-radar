import Foundation

/// The normalized result of one Mac source read or source-state transition.
public struct SourceSnapshot: Hashable, Sendable {
    public let source: AccountSource
    public let windows: [AllowanceWindow]
    /// False for a state-only result that must not advance observations.
    public let isCompleteReport: Bool
    /// A proven account-identity eviction may clear this row without fabricating observations.
    public let clearsWindows: Bool

    public init(
        source: AccountSource, windows: [AllowanceWindow], isCompleteReport: Bool,
        clearsWindows: Bool = false
    ) {
        self.source = source
        self.windows = windows
        self.isCompleteReport = isCompleteReport
        self.clearsWindows = clearsWindows
    }
}
