import Foundation
import ResetRadarApplication
import ResetRadarDomain

public actor CodexAppServerSource: UsageSource {
    private struct ActiveRequest: Sendable {
        let generation: UInt64
        let sentAt: Date
    }

    public nonisolated let accountID: AccountID
    public nonisolated let product = ProductID.codex
    public nonisolated let updates: AsyncStream<SourceSnapshot>

    private var sourceVersion: String
    private let factory: any CodexRPCSessionFactory
    private let runtimeInspector: (any CodexRuntimeInspecting)?
    private let scoper: any AccountScoper
    private let diagnostics: any DiagnosticsSink
    private let clock: any AppClock
    private let updateContinuation: AsyncStream<SourceSnapshot>.Continuation
    private var schedule = CodexSchedule()
    private var session: (any CodexRPCSession)?
    private var generation: UInt64 = 0
    private var readTask: Task<ReadReceipt, Never>?
    private var timerTask: Task<Void, Never>?
    private var notificationTask: Task<Void, Never>?
    private var activeRequest: ActiveRequest?
    private var runtimeMetadata: CodexRuntimeMetadata?
    private var latestProviderScope: AccountScope?
    private var terminallyStopped = false

    public init(
        accountID: AccountID, sourceVersion: String,
        factory: any CodexRPCSessionFactory, scoper: any AccountScoper,
        diagnostics: any DiagnosticsSink, clock: any AppClock,
        runtimeInspector: (any CodexRuntimeInspecting)? = nil
    ) {
        let pair = AsyncStream<SourceSnapshot>.makeStream()
        self.accountID = accountID
        self.sourceVersion = sourceVersion
        self.factory = factory
        self.runtimeInspector = runtimeInspector
        self.scoper = scoper
        self.diagnostics = diagnostics
        self.clock = clock
        updates = pair.stream
        updateContinuation = pair.continuation
    }

    deinit {
        readTask?.cancel()
        timerTask?.cancel()
        notificationTask?.cancel()
        updateContinuation.finish()
    }

    public func start() async throws {
        guard !terminallyStopped else { throw CodexAppServerSourceError.stopped }
        guard schedule.start(at: clock.now) else { throw CodexAppServerSourceError.stopped }
        _ = await refresh()
    }

    public func refresh() async -> ReadReceipt {
        if let readTask { return await readTask.value }
        switch schedule.readPermission(at: clock.now) {
        case .deferred(let retryAt, let sourceState):
            return .deferred(retryAt: retryAt, sourceState: sourceState)
        case .unavailable(let sourceState):
            guard await executableChangedWhileBlocked() else {
                return .unavailable(sourceState: sourceState)
            }
            await configurationChanged()
            return await refresh()
        case .perform:
            let task = Task { [weak self] in
                guard let self else {
                    return ReadReceipt.unavailable(sourceState: .unavailable)
                }
                return await self.performPhysicalRead()
            }
            readTask = task
            let receipt = await task.value
            if readTask == task {
                readTask = nil
                activeRequest = nil
            }
            armTimer()
            return receipt
        }
    }

    public func stop() async {
        guard !terminallyStopped else { return }
        terminallyStopped = true
        schedule.stop()
        generation &+= 1
        timerTask?.cancel()
        notificationTask?.cancel()
        readTask?.cancel()
        timerTask = nil
        notificationTask = nil
        readTask = nil
        if let session { await session.stop() }
        session = nil
        updateContinuation.finish()
    }

    public func configurationChanged() async {
        let supersededRead = readTask
        supersededRead?.cancel()
        await discardSession()
        if let supersededRead { _ = await supersededRead.value }
        if readTask == supersededRead { readTask = nil }
        schedule.configurationChanged(at: clock.now)
        armTimer()
    }

    public var providerScope: AccountScope? { latestProviderScope }

    public func rejectDuplicateProviderScope() async {
        guard !terminallyStopped else { return }
        schedule.recordIncompatible()
        await discardSession()
        let report = SourceSnapshot(
            source: AccountSource(
                accountID: accountID, product: .codex, kind: .codexAppServer,
                version: sourceVersion, state: .incompatible,
                providerScope: latestProviderScope),
            windows: [], isCompleteReport: false, clearsWindows: true)
        await diagnostics.record(
            .providerFailure(
                .duplicateProviderScope, accountID: accountID, product: .codex, at: clock.now))
        updateContinuation.yield(report)
    }
}

extension CodexAppServerSource {
    private struct StaleRead: Error {}

    private func performPhysicalRead() async -> ReadReceipt {
        let startedAt = clock.now
        var expectedGeneration = generation
        var knownProviderScope: AccountScope?
        do {
            try await synchronizeRuntime()
            expectedGeneration = prepareGenerationForRead()
            return try await completeRead(
                generation: expectedGeneration, startedAt: startedAt,
                providerScope: &knownProviderScope)
        } catch {
            guard isCurrent(expectedGeneration) else { return staleReceipt() }
            return await failedRead(
                CodexSourceFailure(thrown: error), startedAt: startedAt,
                providerScope: knownProviderScope)
        }
    }

    private func requireCurrent(_ expectedGeneration: UInt64) throws {
        guard isCurrent(expectedGeneration) else { throw StaleRead() }
    }

    private func completeRead(
        generation expectedGeneration: UInt64, startedAt: Date,
        providerScope: inout AccountScope?
    ) async throws -> ReadReceipt {
        let client = try await currentSession(generation: expectedGeneration)
        try requireCurrent(expectedGeneration)
        let status = try await client.accountStatus()
        try requireCurrent(expectedGeneration)
        switch RateLimitDecoder.decodeAccountStatus(status) {
        case .authenticated: break
        case .signedOut: throw CodexSourceFailure.signedOut
        case .incompatible: throw CodexSourceFailure.incompatible
        }
        let value = try await requestRateLimits(from: client, generation: expectedGeneration)
        try requireCurrent(expectedGeneration)
        let decoded = try await RateLimitDecoder.decodeRateLimits(value, scoper: scoper)
        try requireCurrent(expectedGeneration)
        providerScope = decoded.accountScope
        let normalized = try await CodexNormalizer(
            accountID: accountID, sourceVersion: sourceVersion
        ).normalize(decoded, observedAt: clock.now)
        try requireCurrent(expectedGeneration)
        return await publish(normalized, generation: expectedGeneration, startedAt: startedAt)
    }

    private func requestRateLimits(
        from client: any CodexRPCSession, generation expectedGeneration: UInt64
    ) async throws -> JSONValue {
        activeRequest = ActiveRequest(generation: expectedGeneration, sentAt: clock.now)
        return try await readRateLimits(from: client)
    }

    private func publish(
        _ normalized: CodexNormalization, generation expectedGeneration: UInt64,
        startedAt: Date
    ) async -> ReadReceipt {
        let report = normalized.snapshot
        latestProviderScope = report.source.providerScope
        schedule.recordCompleteReport(
            at: clock.now, resetsAt: report.windows.compactMap(\.resetsAt))
        updateContinuation.yield(report)
        for event in normalized.diagnostics {
            guard isCurrent(expectedGeneration) else { break }
            await diagnostics.record(event)
        }
        return ReadReceipt(
            startedAt: startedAt, finishedAt: clock.now, succeeded: true, report: report)
    }

    /// A blocked source arms no timer, so an executable that became inspectable or was upgraded is
    /// noticed on the next explicit refresh and restarts the child.
    private func executableChangedWhileBlocked() async -> Bool {
        guard !terminallyStopped, schedule.started, let runtimeInspector,
            let current = try? await runtimeInspector.inspect()
        else { return false }
        return current != runtimeMetadata
    }

    private func prepareGenerationForRead() -> UInt64 {
        if session == nil { generation &+= 1 }
        return generation
    }

    private func synchronizeRuntime() async throws {
        guard let runtimeInspector else { return }
        let current = try await runtimeInspector.inspect()
        guard let previous = runtimeMetadata else {
            runtimeMetadata = current
            sourceVersion = current.sourceVersion
            return
        }
        guard previous != current else { return }
        await discardSession()
        runtimeMetadata = current
        sourceVersion = current.sourceVersion
    }

    private func currentSession(
        generation expectedGeneration: UInt64
    ) async throws -> any CodexRPCSession {
        if let session { return session }
        let created: any CodexRPCSession
        do {
            created = try await factory.makeSession(generation: expectedGeneration)
        } catch let failure as CodexSourceFailure {
            throw failure
        } catch {
            throw CodexSourceFailure.temporarilyUnavailable
        }
        guard expectedGeneration == generation, !terminallyStopped else {
            await created.stop()
            throw CodexSourceFailure.processExited
        }
        session = created
        listenForNotifications(from: created, generation: expectedGeneration)
        do {
            _ = try await created.initialize(params: .codexInitializeParameters)
        } catch let error as JSONRPCClientError {
            throw CodexSourceFailure(error)
        } catch {
            throw CodexSourceFailure.temporarilyUnavailable
        }
        return created
    }

    private func readRateLimits(from client: any CodexRPCSession) async throws -> JSONValue {
        do {
            return try await client.rateLimits()
        } catch let error as JSONRPCClientError {
            guard case .remoteError = error else { throw CodexSourceFailure(error) }
            let status: JSONValue
            do {
                status = try await client.accountStatus()
            } catch let statusError as JSONRPCClientError {
                throw CodexSourceFailure(statusError)
            }
            if RateLimitDecoder.decodeAccountStatus(status) == .signedOut {
                throw CodexSourceFailure.signedOut
            }
            throw CodexSourceFailure(error)
        }
    }

    private func failedRead(
        _ failure: CodexSourceFailure, startedAt: Date, providerScope: AccountScope?
    ) async -> ReadReceipt {
        let state = apply(failure)
        let priorScope = latestProviderScope
        let clearsWindows = providerScope.map { priorScope != nil && priorScope != $0 } ?? false
        if let providerScope { latestProviderScope = providerScope }
        let report = SourceSnapshot(
            source: AccountSource(
                accountID: accountID, product: .codex, kind: .codexAppServer,
                version: sourceVersion, state: state,
                providerScope: providerScope ?? priorScope),
            windows: [], isCompleteReport: false, clearsWindows: clearsWindows)
        updateContinuation.yield(report)
        await diagnostics.record(
            .providerFailure(
                failure.diagnosticClass, accountID: accountID, product: .codex, at: clock.now))
        if state == .sourceOffline || state == .incompatible || state == .unavailable {
            await discardSession()
        }
        return ReadReceipt(
            startedAt: startedAt, finishedAt: clock.now, succeeded: false, report: report)
    }

    private func isCurrent(_ expectedGeneration: UInt64) -> Bool {
        !terminallyStopped && generation == expectedGeneration
    }

    private func staleReceipt() -> ReadReceipt {
        .unavailable(sourceState: terminallyStopped ? .unavailable : schedule.sourceState)
    }

    private func apply(_ failure: CodexSourceFailure) -> SourceState {
        switch failure {
        case .notConfigured, .notInstalled, .permissionDenied:
            schedule.recordUnavailable()
            return .unavailable
        case .signedOut:
            schedule.recordSignedOut(at: clock.now)
            return .signedOut
        case .incompatible, .malformed, .duplicateProviderScope:
            schedule.recordIncompatible()
            return .incompatible
        case .timeout, .processExited, .accountScope, .temporarilyUnavailable:
            _ = schedule.recordTransientFailure(at: clock.now)
            return .sourceOffline
        }
    }

    private func discardSession() async {
        generation &+= 1
        activeRequest = nil
        notificationTask?.cancel()
        notificationTask = nil
        if let session { await session.stop() }
        session = nil
    }

    private func listenForNotifications(
        from session: any CodexRPCSession, generation expectedGeneration: UInt64
    ) {
        notificationTask?.cancel()
        notificationTask = Task { [weak self] in
            for await notification in session.notifications {
                await self?.received(notification, expectedGeneration: expectedGeneration)
            }
        }
    }

    private func received(
        _ notification: JSONRPCNotification, expectedGeneration: UInt64
    ) {
        guard !terminallyStopped, expectedGeneration == generation,
            notification.generation == generation
        else { return }
        if readTask != nil, activeRequest == nil { return }
        schedule.notificationReceived(
            at: clock.now, activeRequestSentAt: activeRequest?.sentAt)
        armTimer()
    }

    private func armTimer() {
        timerTask?.cancel()
        guard !terminallyStopped, let deadline = schedule.nextAutomaticDeadline else {
            timerTask = nil
            return
        }
        let delay = max(0, deadline.timeIntervalSince(clock.now))
        timerTask = Task { [clock, weak self] in
            do {
                try await clock.sleep(for: .seconds(delay))
                await self?.automaticDeadlineReached(deadline)
            } catch {}
        }
    }

    private func automaticDeadlineReached(_ deadline: Date) async {
        guard !terminallyStopped, schedule.nextAutomaticDeadline == deadline else { return }
        let notificationRead = schedule.notificationDeadline == deadline
        if notificationRead, readTask != nil {
            // The notification arrived after the in-flight request was sent. Await that request,
            // but leave the notification deadline pending so `armTimer` starts one trailing read.
            _ = await refresh()
            return
        }
        schedule.consumeAutomaticDeadline(deadline)
        if notificationRead { schedule.notificationRefetchStarted(at: clock.now) }
        _ = await refresh()
    }
}
