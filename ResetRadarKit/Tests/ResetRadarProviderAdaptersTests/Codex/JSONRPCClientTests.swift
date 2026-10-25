import Foundation
import ResetRadarProviderAdapters
import ResetRadarTestSupport
import Testing

private final class FakeJSONRPCTransport: JSONRPCTransport, @unchecked Sendable {
    private struct State {
        var writes: [Data] = []
        var terminationCount = 0
        var writeFailure = false
    }

    let stdoutChunks: AsyncStream<Data>
    let exits: AsyncStream<Int32>
    private let stdoutContinuation: AsyncStream<Data>.Continuation
    private let exitContinuation: AsyncStream<Int32>.Continuation
    private let state = Locked(State())

    init() {
        let stdout = AsyncStream<Data>.makeStream()
        stdoutChunks = stdout.stream
        stdoutContinuation = stdout.continuation
        let exits = AsyncStream<Int32>.makeStream()
        self.exits = exits.stream
        exitContinuation = exits.continuation
    }

    var writes: [Data] { state.withLock { $0.writes } }
    var terminationCount: Int { state.withLock { $0.terminationCount } }

    func write(_ data: Data) async throws {
        let fails = state.withLock { state in
            state.writes.append(data)
            return state.writeFailure
        }
        if fails { throw CocoaError(.fileWriteUnknown) }
    }

    func terminate() async {
        state.withLock { $0.terminationCount += 1 }
    }

    func emit(_ message: String) {
        stdoutContinuation.yield(Data(message.utf8))
    }

    func exit(_ status: Int32 = 1) {
        exitContinuation.yield(status)
        exitContinuation.finish()
    }

    func failWrites() {
        state.withLock { $0.writeFailure = true }
    }
}

@Suite("Codex JSON-RPC client")
struct JSONRPCClientTests {
    @Test("initialization gates reads and sends initialized only after success")
    func initialization() async throws {
        let transport = FakeJSONRPCTransport()
        let client = JSONRPCClient(
            transport: transport, clock: FakeAppClock(), generation: 7)

        await #expect(throws: JSONRPCClientError.notInitialized) {
            try await client.accountStatus()
        }
        let initializing = Task { try await client.initialize() }
        await waitForWrites(1, on: transport)
        #expect(method(in: transport.writes[0]) == "initialize")
        transport.emit(response(id: 1, result: "{}"))
        #expect(try await initializing.value == .object([:]))
        await waitForWrites(2, on: transport)
        #expect(method(in: transport.writes[1]) == "initialized")

        let status = Task { try await client.accountStatus() }
        await waitForWrites(3, on: transport)
        #expect(method(in: transport.writes[2]) == "account/read")
        #expect(parameters(in: transport.writes[2])?["refreshToken"] as? Bool == false)
        transport.emit(response(id: 2, result: "{\"account\":null}"))
        #expect(try await status.value == .object(["account": .null]))
    }

    @Test("correlates out-of-order responses and tags allowlisted notifications")
    func correlationAndNotifications() async throws {
        let transport = FakeJSONRPCTransport()
        let client = JSONRPCClient(
            transport: transport, clock: FakeAppClock(), generation: 42)
        try await initialize(client, transport: transport)

        let status = Task { try await client.accountStatus() }
        let limits = Task { try await client.rateLimits() }
        await waitForWrites(4, on: transport)
        let methods = Dictionary(
            uniqueKeysWithValues: transport.writes.suffix(2).map {
                (requestID(in: $0), method(in: $0))
            })
        let statusID = try #require(methods.first(where: { $0.value == "account/read" })?.key)
        let limitsID = try #require(
            methods.first(where: { $0.value == "account/rateLimits/read" })?.key)
        transport.emit(response(id: limitsID, result: "{\"limit\":2}"))
        transport.emit(
            "{\"method\":\"account/rateLimits/updated\",\"params\":{}}\n")
        transport.emit(response(id: statusID, result: "{\"status\":1}"))

        #expect(try await status.value == .object(["status": .integer(1)]))
        #expect(try await limits.value == .object(["limit": .integer(2)]))
        var iterator = client.notifications.makeAsyncIterator()
        #expect(
            await iterator.next()
                == JSONRPCNotification(generation: 42, kind: .rateLimitsUpdated))
    }

    @Test("an injected request deadline fails all pending work and terminates the session")
    func timeout() async throws {
        let transport = FakeJSONRPCTransport()
        let clock = FakeAppClock()
        let client = JSONRPCClient(
            transport: transport, clock: clock, generation: 1, timeout: .seconds(10))
        try await initialize(client, transport: transport)

        let request = Task { try await client.rateLimits() }
        await waitForWrites(3, on: transport)
        await clock.waitForSleepers()
        clock.advance(by: 10)
        await #expect(throws: JSONRPCClientError.requestTimedOut) { try await request.value }
        await waitForTermination(on: transport)
        #expect(transport.terminationCount == 1)
    }

    @Test("a late or duplicate response is a session protocol violation")
    func duplicateResponse() async throws {
        let transport = FakeJSONRPCTransport()
        let client = JSONRPCClient(
            transport: transport, clock: FakeAppClock(), generation: 1)
        try await initialize(client, transport: transport)
        let request = Task { try await client.rateLimits() }
        await waitForWrites(3, on: transport)
        let id = requestID(in: transport.writes[2])
        transport.emit(response(id: id, result: "{}"))
        _ = try await request.value
        transport.emit(response(id: id, result: "{}"))
        await waitForTermination(on: transport)
        #expect(transport.terminationCount == 1)
        await #expect(throws: JSONRPCClientError.stopped) { try await client.rateLimits() }
    }

    @Test("process exit and write failure complete a pending request exactly once")
    func transportFailures() async throws {
        let exitedTransport = FakeJSONRPCTransport()
        let exitedClient = JSONRPCClient(
            transport: exitedTransport, clock: FakeAppClock(), generation: 1)
        try await initialize(exitedClient, transport: exitedTransport)
        let pending = Task { try await exitedClient.rateLimits() }
        await waitForWrites(3, on: exitedTransport)
        exitedTransport.exit()
        await #expect(throws: JSONRPCClientError.processExited) { try await pending.value }

        let failedTransport = FakeJSONRPCTransport()
        let failedClient = JSONRPCClient(
            transport: failedTransport, clock: FakeAppClock(), generation: 2)
        try await initialize(failedClient, transport: failedTransport)
        failedTransport.failWrites()
        await #expect(throws: JSONRPCClientError.transportFailure) {
            try await failedClient.accountStatus()
        }
    }

    @Test("request IDs are never reused after the safe maximum")
    func exhaustedIDs() async throws {
        let transport = FakeJSONRPCTransport()
        let client = JSONRPCClient(
            transport: transport, clock: FakeAppClock(), generation: 1,
            requestIDs: JSONRPCIDSequence(startingAt: JSONRPCIDSequence.maximum))
        let initializing = Task { try await client.initialize() }
        await waitForWrites(1, on: transport)
        transport.emit(response(id: JSONRPCIDSequence.maximum, result: "{}"))
        _ = try await initializing.value
        await #expect(throws: JSONRPCClientError.requestIDExhausted) {
            try await client.rateLimits()
        }
    }

    private func initialize(
        _ client: JSONRPCClient, transport: FakeJSONRPCTransport
    ) async throws {
        let task = Task { try await client.initialize() }
        await waitForWrites(1, on: transport)
        transport.emit(response(id: 1, result: "{}"))
        _ = try await task.value
        await waitForWrites(2, on: transport)
    }

    private func waitForWrites(_ count: Int, on transport: FakeJSONRPCTransport) async {
        for _ in 0..<5_000 where transport.writes.count < count { await Task.yield() }
    }

    private func waitForTermination(on transport: FakeJSONRPCTransport) async {
        for _ in 0..<5_000 where transport.terminationCount == 0 { await Task.yield() }
    }

    private func response(id: Int64, result: String) -> String {
        "{\"id\":\(id),\"result\":\(result)}\n"
    }

    private func requestID(in data: Data) -> Int64 {
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (object?["id"] as? NSNumber)?.int64Value ?? 0
    }

    private func method(in data: Data) -> String? {
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return object?["method"] as? String
    }

    private func parameters(in data: Data) -> [String: Any]? {
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return object?["params"] as? [String: Any]
    }
}
