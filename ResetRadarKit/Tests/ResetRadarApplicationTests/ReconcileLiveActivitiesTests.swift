import Foundation
import ResetRadarDomain
import ResetRadarTestSupport
import Testing

@testable import ResetRadarApplication

@Suite struct ReconcileLiveActivitiesTests {
    let clock = FakeAppClock(start: epoch)
    let store = FakeSnapshotStore(snapshot: fullSnapshot())
    let controller = FakeLiveActivityController()

    func make(reader: (any ReaderStore)? = nil) -> ReconcileLiveActivities {
        ReconcileLiveActivities(
            visible: VisibleSnapshot(snapshots: store, reader: reader), controller: controller,
            clock: clock)
    }

    @Test func aBackgroundRunNeverStartsAnActivity() async {
        await make().run()
        #expect(controller.starts.isEmpty && controller.running.isEmpty)
    }

    @Test func startIsForFiveHourSlotsOnlyAndAtMostOnePerSlot() async {
        let use = make()
        #expect(await use.start(slot: .codexFiveHour) == .started)
        #expect(await use.start(slot: .codexFiveHour) == .alreadyRunning)
        #expect(await use.start(slot: .codexWeekly) == .unavailable)
        #expect(controller.starts == [.codexFiveHour])
    }

    @Test func disabledActivitiesNeverStart() async {
        controller.setEnabled(false)
        #expect(await make().start(slot: .codexFiveHour) == .unavailable)
    }

    @Test(arguments: [
        (3_600.0, 900.0), (600.0, 600.0), (900.0, 900.0), (901.0, 900.0), (899.0, 899.0),
    ])
    func theStaleDateIsTheEarlierOfExpiryAndReset(reset: Double, expected: Double) async throws {
        try await store.commitLocal(fullSnapshot(fiveHourReset: reset))
        _ = await make().start(slot: .codexFiveHour)
        #expect(controller.running[.codexFiveHour]?.staleDate == at(expected))
    }

    @Test func aRunUpdatesContentFromTheCommittedSnapshot() async throws {
        let use = make()
        _ = await use.start(slot: .codexFiveHour)
        try await store.commitLocal(fullSnapshot(fiveHourReset: 3_000))
        await use.run()
        #expect(controller.updates == [.codexFiveHour])
        #expect(controller.running[.codexFiveHour]?.content.resetsAt == at(3_000))
    }

    @Test func anActivityEndsWithImmediateDismissalWhenItsResetHasPassed() async {
        let use = make()
        _ = await use.start(slot: .codexFiveHour)
        clock.set(at(3_600))
        await use.run()
        #expect(controller.ends == [.codexFiveHour] && controller.running.isEmpty)
    }

    @Test func anActivityEndsWhenItsSlotResolvesToAnotherWindow() async throws {
        let use = make()
        _ = await use.start(slot: .codexFiveHour)
        try await store.commitLocal(fullSnapshot(codexScope: scopeB))
        await use.run()
        #expect(controller.ends == [.codexFiveHour])
    }

    @Test func anActivityEndsWhenTheObservationIsGone() async throws {
        let use = make()
        _ = await use.start(slot: .codexFiveHour)
        try await store.clear()
        await use.run()
        #expect(controller.ends == [.codexFiveHour])
    }

    @Test func aUserStoppedActivityIsNotRecreatedOrEnded() async {
        let use = make()
        _ = await use.start(slot: .codexFiveHour)
        controller.userStops(.codexFiveHour)
        await use.run()
        #expect(controller.ends.isEmpty && controller.running.isEmpty)
        #expect(controller.starts == [.codexFiveHour])
    }

    @Test func forgettingTheMacEndsEveryActivity() async {
        let reader = FakeReaderStore(installationID: installation)
        reader.seed { state in
            state.pairing = ReaderPairing(
                endpoint: endpoint, publisherID: publisher, readerID: readerA, minimumSequence: 0,
                keyVersion: 1, registrationExpiresAt: epoch)
        }
        let use = make(reader: reader)
        _ = await use.start(slot: .codexFiveHour)
        _ = await use.start(slot: .claudeCodeFiveHour)
        reader.seed { $0.pairing = nil }
        await use.run()
        #expect(Set(controller.ends) == [.codexFiveHour, .claudeCodeFiveHour])
    }

    @Test func disablingActivitiesEndsThem() async {
        let use = make()
        _ = await use.start(slot: .codexFiveHour)
        controller.setEnabled(false)
        await use.run()
        #expect(controller.ends == [.codexFiveHour])
    }
}
