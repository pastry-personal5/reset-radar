import Foundation
import ResetRadarDomain
import ResetRadarProviderAdapters
import Testing

@Suite("Codex per-account schedule")
struct CodexScheduleTests {
    private let origin = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test("start is idempotent and stop is terminal")
    func lifecycle() {
        var schedule = CodexSchedule()
        let firstStart = schedule.start(at: origin)
        let secondStart = schedule.start(at: origin.addingTimeInterval(10))
        #expect(firstStart)
        #expect(secondStart)
        #expect(schedule.nextAutomaticDeadline == origin)
        schedule.stop()
        let restarted = schedule.start(at: origin.addingTimeInterval(20))
        #expect(!restarted)
        #expect(schedule.nextAutomaticDeadline == nil)
        #expect(schedule.readPermission(at: origin) == .unavailable(sourceState: .unavailable))
    }

    @Test("complete report arms the poll and one deadline per distinct future reset")
    func reportDeadlines() {
        var schedule = startedSchedule()
        let past = origin.addingTimeInterval(-1)
        let first = origin.addingTimeInterval(100)
        let second = origin.addingTimeInterval(200)
        schedule.recordCompleteReport(
            at: origin, resetsAt: [past, first, first, second])

        #expect(schedule.sourceState == .reporting)
        #expect(schedule.pollDeadline == origin.addingTimeInterval(300))
        #expect(
            schedule.resetDeadlines
                == Set([
                    first.addingTimeInterval(30), second.addingTimeInterval(30),
                ]))
        #expect(schedule.nextAutomaticDeadline == first.addingTimeInterval(30))
    }

    @Test("notification before request send is satisfied but a newer update trails")
    func notificationOrdering() {
        var schedule = startedSchedule()
        schedule.recordCompleteReport(at: origin, resetsAt: [])
        let sentAt = origin.addingTimeInterval(10)
        schedule.notificationReceived(
            at: sentAt.addingTimeInterval(-1), activeRequestSentAt: sentAt)
        #expect(schedule.notificationDeadline == nil)

        schedule.notificationRefetchStarted(at: sentAt)
        schedule.notificationReceived(
            at: sentAt.addingTimeInterval(1), activeRequestSentAt: sentAt)
        #expect(schedule.notificationDeadline == sentAt.addingTimeInterval(60))
        schedule.notificationReceived(
            at: sentAt.addingTimeInterval(30), activeRequestSentAt: nil)
        #expect(schedule.notificationDeadline == sentAt.addingTimeInterval(60))
    }

    @Test("notification reads are no more frequent than once per sixty seconds")
    func notificationRateLimit() {
        var schedule = startedSchedule()
        schedule.notificationRefetchStarted(at: origin)
        schedule.notificationReceived(
            at: origin.addingTimeInterval(59), activeRequestSentAt: nil)
        #expect(schedule.notificationDeadline == origin.addingTimeInterval(60))
        schedule.consumeAutomaticDeadline(origin.addingTimeInterval(60))
        schedule.notificationRefetchStarted(at: origin.addingTimeInterval(60))
        schedule.notificationReceived(
            at: origin.addingTimeInterval(61), activeRequestSentAt: nil)
        #expect(schedule.notificationDeadline == origin.addingTimeInterval(120))
    }

    @Test("transient failures use the bounded ladder and explicit reads defer")
    func restartBackoff() throws {
        var schedule = startedSchedule()
        for (index, delay) in [60.0, 120, 300, 900, 900].enumerated() {
            let failedAt = origin.addingTimeInterval(TimeInterval(index) * 1_000)
            let deadline = schedule.recordTransientFailure(at: failedAt)
            #expect(deadline == failedAt.addingTimeInterval(delay))
            #expect(
                schedule.readPermission(at: failedAt)
                    == .deferred(
                        retryAt: failedAt.addingTimeInterval(delay),
                        sourceState: .sourceOffline))
            #expect(schedule.nextAutomaticDeadline == deadline)
            schedule.consumeAutomaticDeadline(try #require(deadline))
        }
    }

    @Test("one success resets the restart ladder")
    func successResetsBackoff() {
        var schedule = startedSchedule()
        _ = schedule.recordTransientFailure(at: origin)
        _ = schedule.recordTransientFailure(at: origin.addingTimeInterval(100))
        schedule.recordCompleteReport(at: origin.addingTimeInterval(300), resetsAt: [])
        let failedAt = origin.addingTimeInterval(400)
        let deadline = schedule.recordTransientFailure(at: failedAt)
        #expect(deadline == failedAt.addingTimeInterval(60))
    }

    @Test("signed-out keeps normal polling while incompatible waits for change")
    func nonTransientStates() {
        var schedule = startedSchedule()
        schedule.recordSignedOut(at: origin)
        #expect(schedule.sourceState == .signedOut)
        #expect(schedule.pollDeadline == origin.addingTimeInterval(300))
        #expect(schedule.readPermission(at: origin) == .perform)

        schedule.recordIncompatible()
        #expect(schedule.nextAutomaticDeadline == nil)
        #expect(schedule.readPermission(at: origin) == .unavailable(sourceState: .incompatible))
        schedule.configurationChanged(at: origin.addingTimeInterval(10))
        #expect(schedule.readPermission(at: origin.addingTimeInterval(10)) == .perform)
        #expect(schedule.nextAutomaticDeadline == origin.addingTimeInterval(10))
    }

    @Test("two schedules keep sibling backoff isolated")
    func siblingIsolation() {
        var first = startedSchedule()
        var second = startedSchedule()
        _ = first.recordTransientFailure(at: origin)
        second.recordCompleteReport(at: origin, resetsAt: [])
        #expect(first.readPermission(at: origin) != .perform)
        #expect(second.readPermission(at: origin) == .perform)
    }

    private func startedSchedule() -> CodexSchedule {
        var schedule = CodexSchedule()
        _ = schedule.start(at: origin)
        schedule.consumeAutomaticDeadline(origin)
        return schedule
    }
}
