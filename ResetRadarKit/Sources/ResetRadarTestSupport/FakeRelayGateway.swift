import Foundation
import ResetRadarApplication
import ResetRadarDomain

public enum RelayCall: Sendable, Equatable {
    case putSnapshot(Data)
    case getSnapshot(etag: String?)
    case activateReader
    case postRefreshRequest(RequestID)
    case listRefreshRequests
    case deleteRefreshRequest(RequestID)
    case registerReader(ReaderID, digest: Data)
    case listReaders
    case revokeReader(ReaderID)
    case destroyRelay
}

public enum RelayOperation: Sendable, Hashable {
    case putSnapshot, getSnapshot, activateReader, postRefreshRequest, listRefreshRequests
    case deleteRefreshRequest, registerReader, listReaders, revokeReader, destroyRelay
}

extension RelayCall {
    var operation: RelayOperation {
        switch self {
        case .putSnapshot: .putSnapshot
        case .getSnapshot: .getSnapshot
        case .activateReader: .activateReader
        case .postRefreshRequest: .postRefreshRequest
        case .listRefreshRequests: .listRefreshRequests
        case .deleteRefreshRequest: .deleteRefreshRequest
        case .registerReader: .registerReader
        case .listReaders: .listReaders
        case .revokeReader: .revokeReader
        case .destroyRelay: .destroyRelay
        }
    }
}

/// Scripted relay: each operation pops its queue, then repeats its fallback. An operation can
/// be held so a test observes a suspended call and releases it later.
public final class FakeRelayGateway: RelayGateway, @unchecked Sendable {
    private struct State {
        var calls: [RelayCall] = []
        var tokens: [SecretValue] = []
        var put: [RelayOutcome] = []
        var get: [RelayOutcome] = []
        var activate: [RelayOutcome] = []
        var post: [RelayOutcome] = []
        var listRequests: [RelayResponse<[PendingRefreshRequest]>] = []
        var delete: [RelayOutcome] = []
        var register: [RelayResponse<Date>] = []
        var listReaders: [RelayResponse<[RelayReader]>] = []
        var revoke: [RelayOutcome] = []
        var destroy: [RelayOutcome] = []
        var held: Set<RelayOperation> = []
        var waiting: [(RelayOperation, CheckedContinuation<Void, Never>)] = []
    }

    private let state = Locked(State())
    private let log: FakeEventLog?
    public var fallbackPut: RelayOutcome = .accepted(sequence: nil)
    public var fallbackGet: RelayOutcome = .notModified
    public var fallbackActivate: RelayOutcome = .accepted(sequence: nil)
    public var fallbackPost: RelayOutcome = .refreshAccepted(expiresAt: .distantFuture)
    public var fallbackDelete: RelayOutcome = .deleted
    public var fallbackRevoke: RelayOutcome = .deleted
    public var fallbackDestroy: RelayOutcome = .deleted

    public init(log: FakeEventLog? = nil) {
        self.log = log
    }

    public var calls: [RelayCall] { state.withLock { $0.calls } }
    public func calls(_ operation: RelayOperation) -> [RelayCall] {
        calls.filter { $0.operation == operation }
    }

    public func queuePut(_ outcomes: RelayOutcome...) { state.withLock { $0.put += outcomes } }
    public func queueGet(_ outcomes: RelayOutcome...) { state.withLock { $0.get += outcomes } }
    public func queueActivate(_ outcomes: RelayOutcome...) {
        state.withLock { $0.activate += outcomes }
    }
    public func queuePost(_ outcomes: RelayOutcome...) { state.withLock { $0.post += outcomes } }
    public func queueDelete(_ outcomes: RelayOutcome...) {
        state.withLock { $0.delete += outcomes }
    }
    public func queueRevoke(_ outcomes: RelayOutcome...) {
        state.withLock { $0.revoke += outcomes }
    }
    public func queueDestroy(_ outcomes: RelayOutcome...) {
        state.withLock { $0.destroy += outcomes }
    }
    public func queueListRequests(_ responses: RelayResponse<[PendingRefreshRequest]>...) {
        state.withLock { $0.listRequests += responses }
    }
    public func queueRegister(_ responses: RelayResponse<Date>...) {
        state.withLock { $0.register += responses }
    }
    public func queueListReaders(_ responses: RelayResponse<[RelayReader]>...) {
        state.withLock { $0.listReaders += responses }
    }

    /// Holds every future call of `operation` until `release(_:)`.
    public func hold(_ operation: RelayOperation) { state.withLock { $0.held.insert(operation) } }

    public func release(_ operation: RelayOperation) {
        let resumed = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.held.remove(operation)
            let matching = state.waiting.filter { $0.0 == operation }
            state.waiting.removeAll { $0.0 == operation }
            return matching.map(\.1)
        }
        for continuation in resumed { continuation.resume() }
    }

    /// Suspends until `operation` has been called at least `count` times.
    public func waitForCalls(_ operation: RelayOperation, count: Int = 1) async {
        for _ in 0..<5_000 where calls(operation).count < count {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    public func putSnapshot(
        _ envelope: Data, endpoint: URL, writeToken: SecretValue
    ) async -> RelayOutcome {
        await enter(.putSnapshot(envelope), writeToken, "putSnapshot")
        return pop(\.put, fallbackPut)
    }

    public func getSnapshot(
        endpoint: URL, readToken: SecretValue, etag: String?
    ) async -> RelayOutcome {
        await enter(.getSnapshot(etag: etag), readToken)
        return pop(\.get, fallbackGet)
    }

    public func activateReader(endpoint: URL, readToken: SecretValue) async -> RelayOutcome {
        await enter(.activateReader, readToken)
        return pop(\.activate, fallbackActivate)
    }

    public func postRefreshRequest(
        _ id: RequestID, endpoint: URL, readToken: SecretValue
    ) async -> RelayOutcome {
        await enter(.postRefreshRequest(id), readToken)
        return pop(\.post, fallbackPost)
    }

    public func listRefreshRequests(
        endpoint: URL, writeToken: SecretValue
    ) async -> RelayResponse<[PendingRefreshRequest]> {
        await enter(.listRefreshRequests, writeToken)
        return pop(\.listRequests, .value([]))
    }

    public func deleteRefreshRequest(
        _ id: RequestID, endpoint: URL, writeToken: SecretValue
    ) async -> RelayOutcome {
        await enter(.deleteRefreshRequest(id), writeToken)
        return pop(\.delete, fallbackDelete)
    }

    public func registerReader(
        _ id: ReaderID, digest: Data, endpoint: URL, adminToken: SecretValue
    ) async -> RelayResponse<Date> {
        await enter(.registerReader(id, digest: digest), adminToken)
        return pop(\.register, .value(Date(timeIntervalSinceReferenceDate: 800_000_300)))
    }

    public func listReaders(
        endpoint: URL, adminToken: SecretValue
    ) async -> RelayResponse<[RelayReader]> {
        await enter(.listReaders, adminToken)
        return pop(\.listReaders, .value([]))
    }

    public func revokeReader(
        _ id: ReaderID, endpoint: URL, adminToken: SecretValue
    ) async -> RelayOutcome {
        await enter(.revokeReader(id), adminToken)
        return pop(\.revoke, fallbackRevoke)
    }

    public func destroyRelay(endpoint: URL, adminToken: SecretValue) async -> RelayOutcome {
        await enter(.destroyRelay, adminToken)
        return pop(\.destroy, fallbackDestroy)
    }

    private func enter(_ call: RelayCall, _ token: SecretValue, _ event: String? = nil) async {
        let isHeld = state.withLock { state -> Bool in
            state.calls.append(call)
            state.tokens.append(token)
            return state.held.contains(call.operation)
        }
        if let event { log?.append(event) }
        if isHeld {
            await withCheckedContinuation { continuation in
                let stillHeld = state.withLock { state -> Bool in
                    guard state.held.contains(call.operation) else { return false }
                    state.waiting.append((call.operation, continuation))
                    return true
                }
                if !stillHeld { continuation.resume() }
            }
        }
    }

    private func pop<T>(_ path: WritableKeyPath<State, [T]>, _ fallback: T) -> T {
        state.withLock { state in
            state[keyPath: path].isEmpty ? fallback : state[keyPath: path].removeFirst()
        }
    }
}
