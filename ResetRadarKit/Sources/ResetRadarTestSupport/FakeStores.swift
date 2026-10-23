import Foundation
import ResetRadarApplication
import ResetRadarDomain

public enum FakeStoreError: Error, Equatable, Sendable {
    case injected
}

/// Atomic read-modify-write over one value, shared by the three transactional fakes.
final class TransactionalBox<State: Sendable>: @unchecked Sendable {
    private let state: Locked<State>
    private let failures = Locked(0)

    init(_ initial: State) {
        state = Locked(initial)
    }

    var value: State { state.snapshot }
    func failNextTransactions(_ count: Int) { failures.withLock { $0 = count } }

    func transact<T>(_ body: (inout State) throws -> T) throws -> T {
        let shouldFail = failures.withLock { count -> Bool in
            guard count > 0 else { return false }
            count -= 1
            return true
        }
        if shouldFail { throw FakeStoreError.injected }
        return try state.withLock { current in
            var copy = current
            let result = try body(&copy)
            current = copy
            return result
        }
    }
}

/// Mac snapshot store: local commits only.
public final class FakeSnapshotStore: LocalSnapshotCommitting, @unchecked Sendable {
    private struct State {
        var snapshot: UsageSnapshot?
        var commits: [UsageSnapshot] = []
    }

    private let state = Locked(State())

    public init(snapshot: UsageSnapshot? = nil) {
        state.withLock { $0.snapshot = snapshot }
    }

    public var commits: [UsageSnapshot] { state.withLock { $0.commits } }
    public var current: UsageSnapshot? { state.withLock { $0.snapshot } }

    public func load() async throws -> UsageSnapshot? { current }
    public func clear() async throws { state.withLock { $0.snapshot = nil } }

    public func commitLocal(_ snapshot: UsageSnapshot) async throws {
        state.withLock {
            $0.snapshot = snapshot
            $0.commits.append(snapshot)
        }
    }
}

/// The reader's `ReaderStore` and its `SnapshotStore` facade share one atomic box, so two
/// use-case instances over one fake behave like two processes over one bundle.
public final class FakeReaderStore: ReaderStore, @unchecked Sendable {
    let box: TransactionalBox<ReaderState>

    public init(installationID: InstallationID) {
        box = TransactionalBox(ReaderState(installationID: installationID))
    }

    public var state: ReaderState { box.value }
    public func failNextTransactions(_ count: Int = 1) { box.failNextTransactions(count) }
    public var snapshotStore: any SnapshotStore { FakeReaderSnapshotStore(box: box) }

    public func seed(_ body: (inout ReaderState) -> Void) {
        try? box.transact { body(&$0) }
    }

    public func load() async throws -> ReaderState { box.value }

    public func transact<T: Sendable>(
        _ body: @Sendable (inout ReaderState) throws -> T
    ) async throws -> T {
        try box.transact(body)
    }
}

struct FakeReaderSnapshotStore: SnapshotStore {
    let box: TransactionalBox<ReaderState>

    func load() async throws -> UsageSnapshot? { box.value.snapshot }
    func clear() async throws { try box.transact { $0.snapshot = nil } }
}

public final class FakeWatchCacheStore: WatchCacheStore, @unchecked Sendable {
    let box = TransactionalBox(WatchCacheState())

    public init() {}

    public var state: WatchCacheState { box.value }
    public func failNextTransactions(_ count: Int = 1) { box.failNextTransactions(count) }
    public var snapshotStore: any SnapshotStore { FakeWatchSnapshotStore(box: box) }

    public func load() async throws -> WatchCacheState { box.value }

    public func transact<T: Sendable>(
        _ body: @Sendable (inout WatchCacheState) throws -> T
    ) async throws -> T {
        try box.transact(body)
    }
}

struct FakeWatchSnapshotStore: SnapshotStore {
    let box: TransactionalBox<WatchCacheState>

    func load() async throws -> UsageSnapshot? { box.value.snapshot }
    func clear() async throws { try box.transact { $0.snapshot = nil } }
}

public final class FakePublisherStore: PublisherStore, @unchecked Sendable {
    private let box = TransactionalBox(PublisherState())
    private let log: FakeEventLog?
    private let sequenceCalls = Locked(0)
    private let failAfterPersist = Locked(false)

    public init(log: FakeEventLog? = nil) {
        self.log = log
    }

    public var state: PublisherState { box.value }
    public var nextSequenceCalls: Int { sequenceCalls.snapshot }
    public func failNextTransactions(_ count: Int = 1) { box.failNextTransactions(count) }

    /// The next `nextSequence()` persists its increment and then throws, as a crash after the
    /// write would: the number is consumed but never returned.
    public func failNextSequenceAfterPersist() { failAfterPersist.withLock { $0 = true } }

    public func seed(_ body: (inout PublisherState) -> Void) {
        try? box.transact { body(&$0) }
    }

    public func load() async throws -> PublisherState { box.value }

    public func transact<T: Sendable>(
        _ body: @Sendable (inout PublisherState) throws -> T
    ) async throws -> T {
        try box.transact(body)
    }

    public func nextSequence() async throws -> UInt64 {
        log?.append("nextSequence")
        sequenceCalls.withLock { $0 += 1 }
        let sequence = try box.transact { state in
            state.sequence += 1
            return state.sequence
        }
        let fail = failAfterPersist.withLock { flag -> Bool in
            defer { flag = false }
            return flag
        }
        if fail { throw FakeStoreError.injected }
        return sequence
    }
}
