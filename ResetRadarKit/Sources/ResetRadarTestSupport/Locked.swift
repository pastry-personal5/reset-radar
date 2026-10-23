import Foundation

/// A lock-protected value, the building block of the fakes. Fakes whose protocol methods are
/// synchronous use it directly; the others use it so tests can read state without `await`.
public final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    public init(_ value: Value) {
        self.value = value
    }

    @discardableResult
    public func withLock<T>(_ body: (inout Value) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }

    public var snapshot: Value { withLock { $0 } }
}

/// An ordered log of event names shared across fakes, for call-order assertions.
public final class FakeEventLog: @unchecked Sendable {
    private let events = Locked<[String]>([])

    public init() {}

    public func append(_ event: String) { events.withLock { $0.append(event) } }
    public var all: [String] { events.snapshot }
}
