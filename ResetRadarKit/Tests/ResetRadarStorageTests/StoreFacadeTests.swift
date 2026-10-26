import Foundation
import ResetRadarApplication
import ResetRadarDomain
import ResetRadarTestSupport
import Testing

@testable import ResetRadarStorage

private func locations(_ directory: TemporaryDirectory) -> StorageLocations {
    StorageLocations(root: directory.url, flavor: .release)
}

struct SnapshotFacadeTests {
    @Test func macCommitLocalThenLoadRoundTrips() async throws {
        let directory = TemporaryDirectory()
        let store = FileSnapshotStore(locations: locations(directory))
        #expect(try await store.load() == nil)
        try await store.commitLocal(snapshot(percent: 33))
        #expect(
            try await FileSnapshotStore(locations: locations(directory)).load()
                == snapshot(percent: 33))
        try await store.clear()
        #expect(try await store.load() == nil)
    }

    @Test func readerClearChangesOnlyTheSnapshot() async throws {
        let directory = TemporaryDirectory()
        let reader = FileReaderStore(locations: locations(directory))
        try await reader.transact {
            $0.snapshot = snapshot()
            $0.pairing = pairing
            $0.committedSequence = 5
        }
        let facade = ReaderSnapshotStore(store: reader)
        #expect(try await facade.load() == snapshot())
        try await facade.clear()
        let state = try await reader.load()
        #expect(state.snapshot == nil)
        #expect(state.pairing == pairing)
        #expect(state.committedSequence == 5)
    }

    @Test func watchClearKeepsTheRevision() async throws {
        let directory = TemporaryDirectory()
        let watch = FileWatchCacheStore(locations: locations(directory))
        try await watch.transact {
            $0.snapshot = snapshot()
            $0.deliveryRevision = 4
        }
        let facade = WatchSnapshotStore(store: watch)
        #expect(try await facade.load() == snapshot())
        try await facade.clear()
        let state = try await watch.load()
        #expect(state.snapshot == nil)
        #expect(state.deliveryRevision == 4)
    }
}

struct DefaultsPreferenceStoreTests {
    private func suite() -> (UserDefaults, String) {
        let name = "reset-radar-test-\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test func optInIsPerAccountWindowAndNilUntilSet() async {
        let (defaults, name) = suite()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = DefaultsPreferenceStore(defaults: defaults)
        #expect(await store.notificationOptIn(codexWeekly) == nil)
        await store.setNotificationOptIn(codexWeekly, enabled: true)
        await store.setNotificationOptIn(codexFiveHour, enabled: false)
        #expect(await store.notificationOptIn(codexWeekly) == true)
        #expect(await store.notificationOptIn(codexFiveHour) == false)
        #expect(await store.notificationOptIn(otherWeekly) == nil)
    }

    @Test func complicationDefaultsToFalse() async {
        let (defaults, name) = suite()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = DefaultsPreferenceStore(defaults: defaults)
        #expect(await store.complicationEnabled() == false)
        await store.setComplicationEnabled(true)
        #expect(await store.complicationEnabled() == true)
    }

    @Test func separateSuitesDoNotShareValues() async {
        let (first, firstName) = suite()
        let (second, secondName) = suite()
        defer {
            first.removePersistentDomain(forName: firstName)
            second.removePersistentDomain(forName: secondName)
        }
        await DefaultsPreferenceStore(defaults: first).setNotificationOptIn(
            codexWeekly, enabled: true)
        await DefaultsPreferenceStore(defaults: first).setComplicationEnabled(true)
        let other = DefaultsPreferenceStore(defaults: second)
        #expect(await other.notificationOptIn(codexWeekly) == nil)
        #expect(await other.complicationEnabled() == false)
    }

    @Test func standardSelectionUsesTheExistingAccountWindowKeyInBothDirections() async {
        let (defaults, name) = suite()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = DefaultsPreferenceStore(defaults: defaults)
        let selection = WindowSelection.standard(codexWeekly)

        await store.setNotificationOptIn(codexWeekly, enabled: true)
        #expect(await store.notificationOptIn(selection) == true)
        await store.setNotificationOptIn(selection, enabled: false)
        #expect(await store.notificationOptIn(codexWeekly) == false)
    }

    @Test func additionalSelectionsUseBoundedDistinctKeysVisibleAcrossInstances() async {
        let (defaults, name) = suite()
        defer { defaults.removePersistentDomain(forName: name) }
        let first = DefaultsPreferenceStore(defaults: defaults)
        let second = DefaultsPreferenceStore(defaults: UserDefaults(suiteName: name)!)
        let scopeA = AccountScope(data: bytes(16, 0xA1))!
        let scopeB = AccountScope(data: bytes(16, 0xB1))!
        let selectionA = WindowSelection.additional(
            WindowID(
                accountID: codexAccountID, product: .codex, scope: scopeA, limitID: "burst",
                durationMinutes: 60))
        let selectionB = WindowSelection.additional(
            WindowID(
                accountID: codexAccountID, product: .codex, scope: scopeB, limitID: "burst",
                durationMinutes: 60))

        await first.setNotificationOptIn(selectionA, enabled: true)
        #expect(await second.notificationOptIn(selectionA) == true)
        #expect(await second.notificationOptIn(selectionB) == nil)
        let ownedKeys = defaults.dictionaryRepresentation().keys.filter {
            $0.hasPrefix("notificationOptIn.v1.")
        }
        #expect(ownedKeys.count == 1)
        #expect(ownedKeys.first?.count == 85)
    }
}

struct FileNotificationReconcileGateTests {
    private final class LockMarker: @unchecked Sendable {
        private let lock = NSLock()
        private var held = false

        func markHeld() {
            lock.lock()
            defer { lock.unlock() }
            held = true
        }

        var isHeld: Bool {
            lock.lock()
            defer { lock.unlock() }
            return held
        }
    }

    @Test func secondClaimIsRefusedWhileTheFirstIsLive() async {
        let directory = TemporaryDirectory()
        let clock = FakeAppClock(start: epoch)
        let gate = FileNotificationReconcileGate(locations: locations(directory), clock: clock)
        let first = await gate.claim()
        #expect(first != nil)
        #expect(await gate.claim() == nil)
        await gate.release(first!)
        #expect(await gate.claim() != nil)
    }

    @Test func claimIsReclaimableExactlyAtExpiryAndNotOneSecondBefore() async {
        let directory = TemporaryDirectory()
        let clock = FakeAppClock(start: epoch)
        let gate = FileNotificationReconcileGate(locations: locations(directory), clock: clock)
        _ = await gate.claim()
        clock.advance(by: 29)
        #expect(await gate.claim() == nil)
        clock.advance(by: 1)
        #expect(await gate.claim() != nil)
    }

    @Test func claimTakenBeforeTheClockMovedBackIsReclaimable() async {
        let directory = TemporaryDirectory()
        let clock = FakeAppClock(start: epoch)
        let gate = FileNotificationReconcileGate(locations: locations(directory), clock: clock)
        _ = await gate.claim()
        clock.advance(by: -3_600)
        #expect(await gate.claim() != nil)
    }

    @Test func lateReleaseOfAReclaimedClaimDoesNotFreeTheNewHolder() async {
        let directory = TemporaryDirectory()
        let clock = FakeAppClock(start: epoch)
        let gate = FileNotificationReconcileGate(locations: locations(directory), clock: clock)
        let stale = await gate.claim()!
        clock.advance(by: 30)
        let current = await gate.claim()!
        await gate.release(stale)
        #expect(await gate.claim() == nil)
        await gate.release(current)
        #expect(await gate.claim() != nil)
    }

    @Test func twoGateInstancesOverOneDirectoryAgree() async {
        let directory = TemporaryDirectory()
        let clock = FakeAppClock(start: epoch)
        let app = FileNotificationReconcileGate(locations: locations(directory), clock: clock)
        let widget = FileNotificationReconcileGate(locations: locations(directory), clock: clock)
        let held = await app.claim()
        #expect(held != nil)
        #expect(await widget.claim() == nil)
        await app.release(held!)
        #expect(await widget.claim() != nil)
    }

    @Test func claimExpiryStartsWhenTheLockIsAcquired() async throws {
        let directory = TemporaryDirectory()
        let clock = FakeAppClock(start: epoch)
        let gate = FileNotificationReconcileGate(locations: locations(directory), clock: clock)
        let marker = LockMarker()
        let lock = ProcessFileLock(
            lockFile: directory.url.appending(path: "reconcile-gate.lock"))
        let holder = Task {
            try await lock.withLock {
                marker.markHeld()
                Thread.sleep(forTimeInterval: 0.2)
            }
        }
        while !marker.isHeld { try await Task.sleep(for: .milliseconds(5)) }
        let waiting = Task { await gate.claim() }
        try await Task.sleep(for: .milliseconds(50))
        clock.advance(by: 20)
        try await holder.value
        let claim = try #require(await waiting.value)
        #expect(claim.expiresAt == clock.now.addingTimeInterval(30))
    }
}

struct LogDiagnosticsSinkTests {
    private func event(_ sequence: UInt64) -> DiagnosticEvent {
        .publicationStopped(httpStatusClass: 4, lastSequence: sequence, at: at(Double(sequence)))
    }

    @Test func ringKeepsTheLastTwoHundredOfTwoHundredOneInOrder() async {
        let directory = TemporaryDirectory()
        let sink = LogDiagnosticsSink(locations: locations(directory))
        for sequence in 1...201 { await sink.record(event(UInt64(sequence))) }
        let history = await sink.history()
        #expect(history.count == 200)
        #expect(history.first?.lastSequence == 2)
        #expect(history.last?.lastSequence == 201)
    }

    @Test func historySurvivesRelaunch() async {
        let directory = TemporaryDirectory()
        await LogDiagnosticsSink(locations: locations(directory)).record(event(1))
        let history = await LogDiagnosticsSink(locations: locations(directory)).history()
        #expect(history == [event(1)])
    }

    @Test func storedEventHoldsOnlyEnumsNumbersAndDates() async throws {
        let directory = TemporaryDirectory()
        await LogDiagnosticsSink(locations: locations(directory)).record(event(1))
        let data = try Data(contentsOf: directory.url.appending(path: "diagnostics.json"))
        var strings: [String] = []
        func collect(_ node: Any) {
            if let text = node as? String { strings.append(text) }
            if let array = node as? [Any] { array.forEach(collect) }
            if let dictionary = node as? [String: Any] { dictionary.values.forEach(collect) }
        }
        collect(try JSONSerialization.jsonObject(with: data))
        let wireDate = String(
            bytes: try WireCoding.encoder().encode(["d": at(1)]), encoding: .utf8)!
        #expect(wireDate.contains(strings.first { $0.hasPrefix("20") } ?? "-"))
        #expect(Set(strings.filter { !$0.hasPrefix("20") }) == ["publicationStopped"])
    }

    @Test func smallCapacityIsHonored() async {
        let directory = TemporaryDirectory()
        let sink = LogDiagnosticsSink(locations: locations(directory), capacity: 2)
        for sequence in 1...3 { await sink.record(event(UInt64(sequence))) }
        #expect(await sink.history().map(\.lastSequence) == [2, 3])
    }
}
