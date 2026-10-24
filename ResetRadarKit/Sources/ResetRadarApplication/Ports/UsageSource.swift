import ResetRadarDomain

/// One product's source on the Mac.
public protocol UsageSource: Sendable {
    var accountID: AccountID { get }
    var product: ProductID { get }
    var updates: AsyncStream<SourceSnapshot> { get }
    func start() async throws
    /// Forces a read and reports when it started and finished.
    func refresh() async -> ReadReceipt
    func stop() async
}
