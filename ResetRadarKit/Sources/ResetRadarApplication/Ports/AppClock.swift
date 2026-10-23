import Foundation

/// Current time and cancellable waiting. Only `RequestMacRefresh`'s bounded wait sleeps; every
/// repeating timer belongs to a driver.
public protocol AppClock: Sendable {
    var now: Date { get }
    func sleep(for duration: Duration) async throws
}
