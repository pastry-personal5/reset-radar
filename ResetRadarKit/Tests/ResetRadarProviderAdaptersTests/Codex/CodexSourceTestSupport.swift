import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarProviderAdapters
import ResetRadarTestSupport
import Testing

final class FakeCodexRPCSession: CodexRPCSession, @unchecked Sendable {
    private struct State {
        var initializeParameters: [JSONValue] = []
        var statusResults: [Result<JSONValue, JSONRPCClientError>]
        var rateLimitResults: [Result<JSONValue, JSONRPCClientError>]
        var statusReads = 0
        var rateLimitReads = 0
        var stops = 0
        var holdStatuses = false
        var holdRateLimits = false
    }

    let notifications: AsyncStream<JSONRPCNotification>
    private let notificationContinuation: AsyncStream<JSONRPCNotification>.Continuation
    private let statusRelease = AsyncStream<Void>.makeStream()
    private let release = AsyncStream<Void>.makeStream()
    private let state: Locked<State>

    init(
        statuses: [Result<JSONValue, JSONRPCClientError>],
        rateLimits: [Result<JSONValue, JSONRPCClientError>]
    ) {
        let notifications = AsyncStream<JSONRPCNotification>.makeStream()
        self.notifications = notifications.stream
        notificationContinuation = notifications.continuation
        state = Locked(State(statusResults: statuses, rateLimitResults: rateLimits))
    }

    var initializeParameters: [JSONValue] { state.withLock { $0.initializeParameters } }
    var statusReads: Int { state.withLock { $0.statusReads } }
    var rateLimitReads: Int { state.withLock { $0.rateLimitReads } }
    var stops: Int { state.withLock { $0.stops } }

    func initialize(params: JSONValue) async throws -> JSONValue {
        state.withLock { $0.initializeParameters.append(params) }
        return .object([:])
    }

    func accountStatus() async throws -> JSONValue {
        let held = state.withLock { state in
            state.statusReads += 1
            return state.holdStatuses
        }
        if held {
            var iterator = statusRelease.stream.makeAsyncIterator()
            _ = await iterator.next()
        }
        return try state.withLock {
            return try take(&$0.statusResults, fallback: .success(Self.authenticated)).get()
        }
    }

    func rateLimits() async throws -> JSONValue {
        let held = state.withLock { state in
            state.rateLimitReads += 1
            return state.holdRateLimits
        }
        if held {
            var iterator = release.stream.makeAsyncIterator()
            _ = await iterator.next()
        }
        return try state.withLock {
            try take(&$0.rateLimitResults, fallback: .success(Self.successfulLimits)).get()
        }
    }

    func stop() async { state.withLock { $0.stops += 1 } }

    func holdStatusReads() { state.withLock { $0.holdStatuses = true } }
    func releaseStatusRead() {
        state.withLock { $0.holdStatuses = false }
        statusRelease.continuation.yield()
    }
    func holdRateLimitReads() { state.withLock { $0.holdRateLimits = true } }
    func releaseRateLimitRead() {
        state.withLock { $0.holdRateLimits = false }
        release.continuation.yield()
    }
    func notify(generation: UInt64) {
        notificationContinuation.yield(
            JSONRPCNotification(generation: generation, kind: .rateLimitsUpdated))
    }

    private func take<Value>(
        _ values: inout [Value], fallback: Value
    ) -> Value {
        values.isEmpty ? fallback : values.removeFirst()
    }

    static let authenticated = JSONValue.object([
        "account": .object(["type": .string("chatgpt")]),
        "requiresOpenaiAuth": .boolean(true),
    ])
    static let signedOut = JSONValue.object([
        "account": .null, "requiresOpenaiAuth": .boolean(true),
    ])
    static let successfulLimits = JSONValue.object([
        "accountId": .string("synthetic-account"),
        "ordinaryUsageAllowed": .boolean(true),
        "rateLimits": .object([
            "limitId": .string("codex"),
            "primary": .object([
                "usedPercent": .integer(25),
                "windowDurationMins": .integer(300),
                "resetsAt": .integer(2_000_000_100),
            ]),
        ]),
    ])
}

final class FakeCodexRPCSessionFactory: CodexRPCSessionFactory, @unchecked Sendable {
    private let session: FakeCodexRPCSession
    private let generationsState = Locked<[UInt64]>([])
    private let failure: CodexSourceFailure?

    init(session: FakeCodexRPCSession, failure: CodexSourceFailure? = nil) {
        self.session = session
        self.failure = failure
    }

    var generations: [UInt64] { generationsState.snapshot }

    func makeSession(generation: UInt64) async throws -> any CodexRPCSession {
        generationsState.withLock { $0.append(generation) }
        if let failure { throw failure }
        return session
    }
}

final class FakeCodexRuntimeInspector: CodexRuntimeInspecting, @unchecked Sendable {
    private let values: Locked<[CodexRuntimeMetadata]>

    init(_ values: [CodexRuntimeMetadata]) {
        self.values = Locked(values)
    }

    func inspect() async throws -> CodexRuntimeMetadata {
        values.withLock { values in
            if values.count > 1 { return values.removeFirst() }
            return values[0]
        }
    }
}

final class ScriptedCodexRuntimeInspector: CodexRuntimeInspecting, @unchecked Sendable {
    private let results: Locked<[Result<CodexRuntimeMetadata, CodexSourceFailure>]>

    init(_ results: [Result<CodexRuntimeMetadata, CodexSourceFailure>]) {
        self.results = Locked(results)
    }

    func inspect() async throws -> CodexRuntimeMetadata {
        try results.withLock { results in
            if results.count > 1 { return try results.removeFirst().get() }
            return try results[0].get()
        }
    }
}

final class GatedAccountScoper: AccountScoper, @unchecked Sendable {
    private let inner = FakeAccountScoper()
    private let state = Locked((held: false, entered: 0))
    private let gate = AsyncStream<Void>.makeStream()

    var entered: Int { state.withLock { $0.entered } }
    func hold() { state.withLock { $0.held = true } }
    func release() {
        state.withLock { $0.held = false }
        gate.continuation.yield()
    }

    func scope(forAccountIdentifier identifier: String) async throws -> AccountScope {
        let held = state.withLock { state in
            state.entered += 1
            return state.held
        }
        if held {
            var iterator = gate.stream.makeAsyncIterator()
            _ = await iterator.next()
        }
        return try await inner.scope(forAccountIdentifier: identifier)
    }
}

struct CodexSourceRig {
    let source: CodexAppServerSource
    let session: FakeCodexRPCSession
    let clock: FakeAppClock
    let diagnostics: FakeDiagnosticsSink
}

protocol CodexSourceTestHarness {}

extension CodexSourceTestHarness {
    var accountID: AccountID { AccountID(data: Data(repeating: 0xB1, count: 16))! }
    var origin: Date { Date(timeIntervalSince1970: 2_000_000_000) }

    func makeRig(
        session: FakeCodexRPCSession? = nil,
        runtimeInspector: (any CodexRuntimeInspecting)? = nil,
        scoper: any AccountScoper = FakeAccountScoper()
    ) -> CodexSourceRig {
        let session =
            session
            ?? FakeCodexRPCSession(
                statuses: [.success(FakeCodexRPCSession.authenticated)],
                rateLimits: [.success(FakeCodexRPCSession.successfulLimits)])
        let clock = FakeAppClock(start: origin)
        let diagnostics = FakeDiagnosticsSink()
        let source = CodexAppServerSource(
            accountID: accountID, sourceVersion: "codex 0.164.0",
            factory: FakeCodexRPCSessionFactory(session: session),
            scoper: scoper, diagnostics: diagnostics, clock: clock,
            runtimeInspector: runtimeInspector)
        return CodexSourceRig(
            source: source, session: session, clock: clock, diagnostics: diagnostics)
    }

    func waitForRateLimitReads(
        _ count: Int, session: FakeCodexRPCSession
    ) async {
        for _ in 0..<5_000 where session.rateLimitReads < count { await Task.yield() }
    }

    func waitForStatusReads(
        _ count: Int, session: FakeCodexRPCSession
    ) async {
        for _ in 0..<5_000 where session.statusReads < count { await Task.yield() }
    }

    func runtimeMetadata(version: String) -> CodexRuntimeMetadata {
        let identity = CodexExecutableFileIdentity(
            canonicalPath: "/synthetic/codex", device: 1, inode: 2, size: 3,
            modifiedSeconds: 4, modifiedNanoseconds: 5, ownerID: 6, permissions: 0o700)
        return CodexRuntimeMetadata(
            configurationRevision: ConfigurationPreviewRevision(
                value: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!),
            executable: CodexValidatedExecutable(
                invocationPath: "/synthetic/codex", executable: identity, node: nil),
            sourceVersion: version)
    }
}
