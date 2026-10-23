import Foundation
import ResetRadarDomain
import ResetRadarTestSupport
import Testing

@testable import ResetRadarApplication

/// Records whether the gate was held at the moment the snapshot was read.
final class GateProbeStore: SnapshotStore, @unchecked Sendable {
    private let inner: FakeSnapshotStore
    private let gate: FakeNotificationReconcileGate
    let heldAtRead = Locked<[Bool]>([])

    init(inner: FakeSnapshotStore, gate: FakeNotificationReconcileGate) {
        self.inner = inner
        self.gate = gate
    }

    func load() async throws -> UsageSnapshot? {
        heldAtRead.withLock { $0.append(gate.isHeld) }
        return try await inner.load()
    }

    func clear() async throws { try await inner.clear() }
}

final class ReminderRig: @unchecked Sendable {
    let clock = FakeAppClock(start: epoch)
    let store = FakeSnapshotStore(snapshot: fullSnapshot())
    let preferences = FakePreferenceStore()
    let scheduler = FakeNotificationScheduler()
    let gate: FakeNotificationReconcileGate

    init() {
        gate = FakeNotificationReconcileGate(clock: clock)
    }

    func reconcile(
        snapshots: (any SnapshotStore)? = nil, useGate: Bool = true
    ) -> ReconcileResetNotifications {
        ReconcileResetNotifications(
            visible: VisibleSnapshot(snapshots: snapshots ?? store), preferences: preferences,
            scheduler: scheduler, gate: useGate ? gate : nil, clock: clock)
    }
}

@Suite struct ReconcileResetNotificationsTests {
    let rig = ReminderRig()

    @Test func oneRequestPerOptedInSlotWithAFutureReset() async {
        await rig.preferences.setNotificationOptIn(.codexFiveHour, enabled: true)
        await rig.preferences.setNotificationOptIn(.claudeCodeWeekly, enabled: true)
        await rig.preferences.setNotificationOptIn(.codexWeekly, enabled: false)
        #expect(await rig.reconcile().run(onIOS: true) == .reconciled)
        let pending = rig.scheduler.current
        #expect(Set(pending.keys) == [.codexFiveHour, .claudeCodeWeekly])
        #expect(pending[.codexFiveHour]?.identifier == "reset.codexFiveHour")
        #expect(pending[.codexFiveHour]?.fireAt == at(3_600))
    }

    @Test func aNewerResetReplacesTheRequestAndAnUnchangedOneIsNotRescheduled() async throws {
        await rig.preferences.setNotificationOptIn(.codexFiveHour, enabled: true)
        let use = rig.reconcile()
        _ = await use.run(onIOS: true)
        _ = await use.run(onIOS: true)
        #expect(rig.scheduler.scheduled.count == 1)
        try await rig.store.commitLocal(fullSnapshot(fiveHourReset: 7_200))
        _ = await use.run(onIOS: true)
        #expect(rig.scheduler.scheduled.count == 2)
        #expect(rig.scheduler.current[.codexFiveHour]?.fireAt == at(7_200))
    }

    @Test func aMissingExpiredIncompatibleOrReplacedWindowCancels() async throws {
        await rig.preferences.setNotificationOptIn(.codexFiveHour, enabled: true)
        let use = rig.reconcile()
        let replacements: [UsageSnapshot] = [
            snapshot(windows: []),
            fullSnapshot(fiveHourReset: 3_600, codexState: .incompatible),
            snapshot(windows: [window(minutes: 60, isDefault: false)]),
        ]
        for replacement in replacements {
            try await rig.store.commitLocal(fullSnapshot())
            _ = await use.run(onIOS: true)
            #expect(rig.scheduler.current[.codexFiveHour] != nil)
            try await rig.store.commitLocal(replacement)
            _ = await use.run(onIOS: true)
            #expect(rig.scheduler.current[.codexFiveHour] == nil)
        }
        try await rig.store.clear()
        try await rig.store.commitLocal(fullSnapshot())
        _ = await use.run(onIOS: true)
        try await rig.store.clear()
        _ = await use.run(onIOS: true)
        #expect(rig.scheduler.current.isEmpty)
    }

    @Test func aResetAtOrBeforeNowSchedulesNothing() async {
        await rig.preferences.setNotificationOptIn(.codexFiveHour, enabled: true)
        rig.clock.set(at(3_600))
        _ = await rig.reconcile().run(onIOS: true)
        #expect(rig.scheduler.scheduled.isEmpty)
        rig.clock.set(at(3_599))
        _ = await rig.reconcile().run(onIOS: true)
        #expect(rig.scheduler.scheduled.count == 1)
    }

    @Test func theRequestHoldsAnAbsoluteInstantThatATimeZoneChangeDoesNotMove() async {
        await rig.preferences.setNotificationOptIn(.codexFiveHour, enabled: true)
        let use = rig.reconcile()
        _ = await use.run(onIOS: true)
        let before = rig.scheduler.current[.codexFiveHour]?.fireAt
        let original = NSTimeZone.default
        defer { NSTimeZone.default = original }
        NSTimeZone.default = TimeZone(identifier: "Pacific/Kiritimati") ?? original
        _ = await use.run(onIOS: true)
        #expect(rig.scheduler.current[.codexFiveHour]?.fireAt == before)
        #expect(rig.scheduler.scheduled.count == 1)
    }

    @Test func theGateIsHeldWhileTheSnapshotIsReadAndReleasedAfterwards() async {
        await rig.preferences.setNotificationOptIn(.codexFiveHour, enabled: true)
        let probe = GateProbeStore(inner: rig.store, gate: rig.gate)
        _ = await rig.reconcile(snapshots: probe).run(onIOS: true)
        #expect(probe.heldAtRead.snapshot == [true])
        #expect(!rig.gate.isHeld)
    }

    @Test func aClaimHeldElsewhereIsRetryableAndAnInterruptedOneIsRetriedLater() async {
        await rig.preferences.setNotificationOptIn(.codexFiveHour, enabled: true)
        _ = await rig.gate.claim()
        #expect(await rig.reconcile().run(onIOS: true) == .retryable)
        #expect(rig.scheduler.scheduled.isEmpty)
        rig.clock.advance(by: FakeNotificationReconcileGate.lease)
        #expect(await rig.reconcile().run(onIOS: true) == .reconciled)
        #expect(rig.scheduler.scheduled.count == 1)
    }

    @Test func theMacUsesNoGate() async {
        await rig.preferences.setNotificationOptIn(.codexFiveHour, enabled: true)
        _ = await rig.gate.claim()
        #expect(await rig.reconcile(useGate: false).run(onIOS: false) == .reconciled)
        #expect(rig.scheduler.scheduled.count == 1)
    }

    @Test func copyCarriesOnlyAProductAndWindowAndNeverATimeOrPercentage() {
        let request = ResetRequest(slot: .claudeCodeWeekly, fireAt: epoch)
        #expect(Mirror(reflecting: request).children.compactMap(\.label) == ["slot", "fireAt"])
        #expect(request.product == .claudeCode && request.slot.durationMinutes == 10_080)
    }

    @Test func withoutAuthorizationNothingIsScheduledAndNothingIsRequested() async {
        rig.scheduler.setAuthorization(.notDetermined)
        await rig.preferences.setNotificationOptIn(.codexFiveHour, enabled: true)
        _ = await rig.reconcile().run(onIOS: true)
        #expect(rig.scheduler.scheduled.isEmpty)
        #expect(rig.scheduler.authorizationRequests == 0)
    }
}

@Suite struct SetNotificationOptInTests {
    let rig = ReminderRig()

    func make() -> SetNotificationOptIn {
        SetNotificationOptIn(
            preferences: rig.preferences, scheduler: rig.scheduler, reconcile: rig.reconcile())
    }

    @Test func theFirstEnableRequestsAuthorizationOnce() async {
        rig.scheduler.setAuthorization(.notDetermined, grantOnRequest: .authorized)
        let use = make()
        #expect(await use.set(.codexFiveHour, enabled: true) == .enabled)
        #expect(await use.set(.claudeCodeFiveHour, enabled: true) == .enabled)
        #expect(rig.scheduler.authorizationRequests == 1)
        #expect(await rig.preferences.notificationOptIn(.codexFiveHour) == true)
        #expect(Set(rig.scheduler.current.keys) == [.codexFiveHour, .claudeCodeFiveHour])
    }

    @Test func aDeniedChoiceStaysRecordedWithoutAskingAgain() async {
        rig.scheduler.setAuthorization(.notDetermined, grantOnRequest: .denied)
        let use = make()
        #expect(await use.set(.codexFiveHour, enabled: true) == .denied)
        #expect(await use.set(.codexFiveHour, enabled: true) == .denied)
        #expect(rig.scheduler.authorizationRequests == 1)
        #expect(await rig.preferences.notificationOptIn(.codexFiveHour) == true)
        #expect(rig.scheduler.scheduled.isEmpty)
    }

    @Test func disablingCancelsTheRequest() async {
        let use = make()
        _ = await use.set(.codexFiveHour, enabled: true)
        #expect(await use.set(.codexFiveHour, enabled: false) == .disabled)
        #expect(rig.scheduler.current.isEmpty)
        #expect(await rig.preferences.notificationOptIn(.codexFiveHour) == false)
    }
}
