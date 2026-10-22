import Foundation

/// The normalized result of one Mac source read or source-state transition.
public struct SourceSnapshot: Hashable, Sendable {
    public let source: ProductSource
    public let windows: [AllowanceWindow]
    /// False for a state-only result that must not advance observations.
    public let isCompleteReport: Bool

    public init(source: ProductSource, windows: [AllowanceWindow], isCompleteReport: Bool) {
        self.source = source
        self.windows = windows
        self.isCompleteReport = isCompleteReport
    }
}
