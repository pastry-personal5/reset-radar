import Foundation
import ResetRadarApplication

public protocol JSONRPCTransport: Sendable {
    var stdoutChunks: AsyncStream<Data> { get }
    var exits: AsyncStream<Int32> { get }

    func write(_ data: Data) async throws
    func terminate() async
}

public enum JSONRPCClientError: Error, Equatable, Sendable {
    case alreadyInitialized
    case notInitialized
    case requestCancelled
    case requestTimedOut
    case processExited
    case protocolViolation
    case requestIDExhausted
    case remoteError(code: Int64)
    case stopped
    case transportFailure
}

public struct JSONRPCNotification: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case rateLimitsUpdated
    }

    public let generation: UInt64
    public let kind: Kind

    public init(generation: UInt64, kind: Kind) {
        self.generation = generation
        self.kind = kind
    }
}

public actor JSONRPCClient {
    public nonisolated let notifications: AsyncStream<JSONRPCNotification>

    private enum State {
        case idle
        case initializing
        case ready
        case stopped
    }

    private struct PendingRequest {
        let generation: UInt64
        let continuation: CheckedContinuation<JSONValue, any Error>
    }

    private let transport: any JSONRPCTransport
    private let clock: any AppClock
    private let generation: UInt64
    private let timeout: Duration
    private let notificationContinuation: AsyncStream<JSONRPCNotification>.Continuation
    private var sequence: JSONRPCIDSequence
    private var state = State.idle
    private var pending: [Int64: PendingRequest] = [:]
    private var timeoutTasks: [Int64: Task<Void, Never>] = [:]
    private var stdoutTask: Task<Void, Never>?
    private var exitTask: Task<Void, Never>?

    public init(
        transport: any JSONRPCTransport,
        clock: any AppClock,
        generation: UInt64,
        timeout: Duration = .seconds(10),
        requestIDs: JSONRPCIDSequence = JSONRPCIDSequence()
    ) {
        let pair = AsyncStream<JSONRPCNotification>.makeStream()
        notifications = pair.stream
        notificationContinuation = pair.continuation
        self.transport = transport
        self.clock = clock
        self.generation = generation
        self.timeout = timeout
        sequence = requestIDs
    }

    deinit {
        stdoutTask?.cancel()
        exitTask?.cancel()
        for task in timeoutTasks.values { task.cancel() }
        notificationContinuation.finish()
    }

    public func initialize(params: JSONValue = .object([:])) async throws -> JSONValue {
        switch state {
        case .idle:
            state = .initializing
        case .initializing, .ready:
            throw JSONRPCClientError.alreadyInitialized
        case .stopped:
            throw JSONRPCClientError.stopped
        }
        startReaders()
        do {
            let result = try await request(
                method: .initialize, params: params, permitsInitializing: true)
            try await transport.write(JSONRPCMessageEncoder.initialized())
            guard state == .initializing else { throw JSONRPCClientError.stopped }
            state = .ready
            return result
        } catch {
            let clientError = mapped(error)
            await failSession(clientError)
            throw clientError
        }
    }

    public func accountStatus() async throws -> JSONValue {
        try await request(
            method: .accountRead,
            params: .object(["refreshToken": .boolean(false)]),
            permitsInitializing: false)
    }

    public func rateLimits() async throws -> JSONValue {
        try await request(
            method: .accountRateLimitsRead, params: .object([:]), permitsInitializing: false)
    }

    public func stop() {
        guard state != .stopped else { return }
        finish(with: .stopped)
    }

    private func request(
        method: JSONRPCMethod, params: JSONValue, permitsInitializing: Bool
    ) async throws -> JSONValue {
        guard permitsInitializing ? state == .initializing : state == .ready else {
            throw state == .stopped ? JSONRPCClientError.stopped : .notInitialized
        }
        let id: Int64
        do {
            id = try sequence.next()
        } catch {
            throw JSONRPCClientError.requestIDExhausted
        }
        let payload = try JSONRPCMessageEncoder.request(id: id, method: method, params: params)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = PendingRequest(generation: generation, continuation: continuation)
                timeoutTasks[id] = Task { [clock, timeout, weak self] in
                    do {
                        try await clock.sleep(for: timeout)
                        await self?.timeOut(id: id)
                    } catch {}
                }
                Task { [transport, weak self] in
                    do {
                        try await transport.write(payload)
                    } catch {
                        await self?.transportFailed(id: id)
                    }
                }
            }
        } onCancel: {
            Task { [weak self] in await self?.cancel(id: id) }
        }
    }

    private func startReaders() {
        guard stdoutTask == nil, exitTask == nil else { return }
        let stdoutChunks = transport.stdoutChunks
        stdoutTask = Task { [weak self] in
            var framer = BoundedRPCFrame()
            do {
                for await chunk in stdoutChunks {
                    for frame in try framer.consume(chunk) {
                        await self?.receive(frame)
                    }
                }
                try framer.finish()
                await self?.streamEnded()
            } catch {
                await self?.protocolFailed()
            }
        }
        let exits = transport.exits
        exitTask = Task { [weak self] in
            for await _ in exits {
                await self?.processExited()
                return
            }
        }
    }

    private func receive(_ frame: Data) async {
        guard state != .stopped else { return }
        let message: JSONRPCDecodedMessage
        do {
            message = try JSONRPCMessageDecoder.decode(frame)
        } catch {
            await failSession(.protocolViolation)
            return
        }
        switch message {
        case .response(let id, let result):
            await resolve(id: id, result: .success(result))
        case .error(let id, let code):
            await resolve(
                id: id, result: .failure(JSONRPCClientError.remoteError(code: code)))
        case .rateLimitsUpdated:
            notificationContinuation.yield(
                JSONRPCNotification(generation: generation, kind: .rateLimitsUpdated))
        case .ignoredNotification:
            break
        }
    }

    private func resolve(id: Int64, result: Result<JSONValue, any Error>) async {
        if cancelledIDs.remove(id) != nil { return }  // the server's late answer to a cancel
        guard let request = pending.removeValue(forKey: id), request.generation == generation else {
            await failSession(.protocolViolation)
            return
        }
        timeoutTasks.removeValue(forKey: id)?.cancel()
        request.continuation.resume(with: result)
    }

    private var cancelledIDs: Set<Int64> = []

    private func cancel(id: Int64) {
        guard let request = pending.removeValue(forKey: id) else { return }
        cancelledIDs.insert(id)
        timeoutTasks.removeValue(forKey: id)?.cancel()
        request.continuation.resume(throwing: JSONRPCClientError.requestCancelled)
    }

    private func timeOut(id: Int64) async {
        guard pending[id] != nil else { return }
        await failSession(.requestTimedOut)
    }

    private func transportFailed(id: Int64) async {
        guard pending[id] != nil else { return }
        await failSession(.transportFailure)
    }

    private func protocolFailed() async {
        guard state != .stopped else { return }
        await failSession(.protocolViolation)
    }

    private func streamEnded() async {
        guard state != .stopped else { return }
        await failSession(.processExited)
    }

    private func processExited() async {
        guard state != .stopped else { return }
        await failSession(.processExited)
    }

    private func failSession(_ error: JSONRPCClientError) async {
        guard state != .stopped else { return }
        finish(with: error)
        await transport.terminate()
    }

    private func finish(with error: JSONRPCClientError) {
        state = .stopped
        stdoutTask?.cancel()
        exitTask?.cancel()
        stdoutTask = nil
        exitTask = nil
        for task in timeoutTasks.values { task.cancel() }
        timeoutTasks.removeAll()
        let requests = Array(pending.values)
        pending.removeAll()
        for request in requests { request.continuation.resume(throwing: error) }
        notificationContinuation.finish()
    }

    private func mapped(_ error: any Error) -> JSONRPCClientError {
        if let error = error as? JSONRPCClientError { return error }
        if error is JSONRPCProtocolError { return .protocolViolation }
        return .transportFailure
    }
}
