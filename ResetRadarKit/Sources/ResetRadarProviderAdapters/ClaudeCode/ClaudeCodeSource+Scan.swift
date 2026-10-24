import Foundation
import ResetRadarApplication
import ResetRadarDomain

extension ClaudeCodeSource {
    // MARK: Activation and watching

    /// Probes setup, then arms the directory watch before the initial scan so no record
    /// replacement can land between the scan and the subscription.
    func activate() async {
        let status = await probe.status()
        guard !terminallyStopped else { return }
        switch status {
        case .ready:
            awaitingConfiguration = false
        case .notConfigured, .helperUnavailable:
            awaitingConfiguration = true
            discardWatch()
            await fail(.notInstalled, startedAt: clock.now)
            return
        }
        guard await revalidate() == nil, !terminallyStopped else { return }
        _ = await scanNow()
    }

    /// Arms a fresh watch generation. Returns nil on success; a failure reports once, schedules
    /// the next attempt when it is operational, and returns its state-only receipt.
    func revalidate() async -> ReadReceipt? {
        guard !terminallyStopped else { return .unavailable(sourceState: .unavailable) }
        discardWatch()
        retryDeadline = nil
        do {
            try file.prepare()
        } catch {
            let unsafe = error as? SessionRecordError == .unsafeLocation
            return await fail(unsafe ? .malformed : .temporarilyUnavailable, startedAt: clock.now)
        }
        do {
            let session = try watchFactory.watch(directory: file.directoryURL)
            generation &+= 1
            let armed = generation
            watch = session
            watchTask = Task { [weak self] in
                for await event in session.events {
                    await self?.received(event, generation: armed)
                }
            }
            return nil
        } catch {
            return await fail(ClaudeCodeSourceFailure(error), startedAt: clock.now)
        }
    }

    func discardWatch() {
        generation &+= 1
        watchTask?.cancel()
        watch?.cancel()
        watchTask = nil
        watch = nil
    }

    private func received(_ event: DirectoryWatchEvent, generation armed: UInt64) async {
        guard !terminallyStopped, armed == generation else { return }
        switch event {
        case .changed:
            scheduleCoalescedScan()
        case .rootInvalidated:
            discardWatch()
            await fail(.temporarilyUnavailable, startedAt: clock.now)
        }
    }

    // MARK: Scanning

    /// An event received while a scan runs leaves one trailing scan, because the older
    /// enumeration cannot satisfy a newer filesystem change.
    private func scheduleCoalescedScan() {
        if scanTask != nil {
            trailingScanNeeded = true
            return
        }
        guard coalesceTask == nil else { return }
        coalesceTask = Task { [clock, weak self] in
            do {
                try await clock.sleep(for: .seconds(Self.coalescingInterval))
                await self?.coalescingElapsed()
            } catch {}
        }
    }

    private func coalescingElapsed() async {
        coalesceTask = nil
        guard !terminallyStopped, retryDeadline == nil, !awaitingConfiguration else { return }
        _ = await scanNow()
    }

    /// One physical scan shared by every caller that arrives while it runs.
    func scanNow() async -> ReadReceipt {
        if let scanTask { return await scanTask.value }
        coalesceTask?.cancel()
        coalesceTask = nil
        let task = Task { [weak self] in
            guard let self else { return ReadReceipt.unavailable(sourceState: .unavailable) }
            return await self.physicalScan()
        }
        scanTask = task
        let receipt = await task.value
        if scanTask == task {
            scanTask = nil
            if trailingScanNeeded {
                trailingScanNeeded = false
                scheduleCoalescedScan()
            }
        }
        return receipt
    }

    private func physicalScan() async -> ReadReceipt {
        let startedAt = clock.now
        let armed = generation
        scanCount += 1
        let outcome = Self.collect(file: file, accountID: accountID, now: startedAt)
        guard !terminallyStopped, armed == generation else {
            return .unavailable(sourceState: .unavailable)
        }
        switch outcome {
        case .success(let merged):
            return publish(merged, startedAt: startedAt)
        case .failure(let failure):
            return await fail(failure, startedAt: startedAt)
        }
    }

    private static func collect(
        file: SessionRecordFile, accountID: AccountID, now: Date
    ) -> Result<MergedUsage, ClaudeCodeSourceFailure> {
        do {
            try SessionPruner(file: file).prune(now: now)
            let records = try SessionRecordReader(file: file).scan()
            let merged = try SessionMerger(accountID: accountID).merge(records)
            return merged.windows.isEmpty ? .failure(.noObservation) : .success(merged)
        } catch let error as SessionScanError {
            return .failure(ClaudeCodeSourceFailure(error))
        } catch let error as SessionMergeError {
            return .failure(error == .conflictingObservations ? .conflict : .malformed)
        } catch {
            return .failure(.temporarilyUnavailable)
        }
    }

    // MARK: Results

    private func publish(_ merged: MergedUsage, startedAt: Date) -> ReadReceipt {
        lastVersion = merged.version ?? lastVersion
        retryDeadline = nil
        schedule.reset()
        let report = SourceSnapshot(
            source: source(state: .reporting), windows: merged.windows, isCompleteReport: true)
        emit(report)
        return ReadReceipt(
            startedAt: startedAt, finishedAt: clock.now, succeeded: true, report: report)
    }

    @discardableResult
    func fail(_ failure: ClaudeCodeSourceFailure, startedAt: Date) async -> ReadReceipt {
        guard !terminallyStopped else { return .unavailable(sourceState: .unavailable) }
        let report = SourceSnapshot(
            source: source(state: failure.state), windows: [], isCompleteReport: false)
        emit(report)
        if let diagnosticClass = failure.diagnosticClass {
            await diagnostics.record(
                .providerFailure(
                    diagnosticClass, accountID: accountID, product: .claudeCode, at: clock.now))
        }
        if failure.retriesWithBackoff { scheduleRevalidation() }
        return ReadReceipt(
            startedAt: startedAt, finishedAt: clock.now, succeeded: false, report: report)
    }

    private func source(state: SourceState) -> AccountSource {
        AccountSource(
            accountID: accountID, product: .claudeCode, kind: .claudeCodeStatusLine,
            version: lastVersion, state: state)
    }

    /// An unchanged result emits nothing; a state-only repeat is not republished.
    private func emit(_ report: SourceSnapshot) {
        guard report != lastEmitted else { return }
        lastEmitted = report
        updateContinuation.yield(report)
    }

    private func scheduleRevalidation() {
        guard !terminallyStopped else { return }
        let deadline = schedule.nextDeadline(after: clock.now)
        retryDeadline = deadline
        retryTask?.cancel()
        let delay = max(0, deadline.timeIntervalSince(clock.now))
        retryTask = Task { [clock, weak self] in
            do {
                try await clock.sleep(for: .seconds(delay))
                await self?.revalidationDue(deadline)
            } catch {}
        }
    }

    private func revalidationDue(_ deadline: Date) async {
        guard !terminallyStopped, retryDeadline == deadline else { return }
        guard await revalidate() == nil, !terminallyStopped else { return }
        _ = await scanNow()
    }
}
