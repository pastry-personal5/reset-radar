import Foundation
import Testing

@testable import ResetRadar

@MainActor
private final class FakeBackgroundRefreshTask: BackgroundRefreshTask {
    var expirationHandler: (() -> Void)?
    private(set) var completions: [Bool] = []

    func setTaskCompleted(success: Bool) {
        completions.append(success)
    }

    func expire() {
        expirationHandler?()
    }
}

@MainActor
@Suite struct BackgroundRefreshTests {
    @Test func successfulWorkResubmitsBeforeCompletingExactlyOnce() async throws {
        let harness = ReaderHarness()
        try await harness.seedPaired()
        harness.relay.queueGet(.notModified)
        let environment = harness.environment()
        let task = FakeBackgroundRefreshTask()
        var resubmissions = 0

        await environment.runBackgroundRefresh(task) {
            resubmissions += 1
            #expect(task.completions.isEmpty)
        }

        #expect(resubmissions == 1)
        #expect(task.completions == [true])
    }

    @Test func expirationCancelsOnceResubmitsAndDoesNotRecordTransportFailure() async throws {
        let harness = ReaderHarness()
        try await harness.seedPaired()
        let initial = try await harness.store.load()
        harness.relay.queueGet(try harness.envelope(sequence: 6))
        harness.relay.holdNext(.getSnapshot)
        let environment = harness.environment()
        let task = FakeBackgroundRefreshTask()
        var resubmissions = 0

        let run = Task {
            await environment.runBackgroundRefresh(task) { resubmissions += 1 }
        }
        await harness.relay.waitForCalls(.getSnapshot)
        task.expire()
        task.expire()
        harness.relay.release(.getSnapshot)
        await run.value

        let final = try await harness.store.load()
        #expect(resubmissions == 1)
        #expect(task.completions == [false])
        #expect(final.lease == nil)
        #expect(final.transportStatus == initial.transportStatus)
        #expect(final.failureCount == initial.failureCount)
        #expect(final.backoffUntil == initial.backoffUntil)
        #expect(final.etag == initial.etag)
        #expect(final.committedSequence == initial.committedSequence)
    }
}
