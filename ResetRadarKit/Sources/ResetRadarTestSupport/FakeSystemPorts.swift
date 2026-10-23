import Foundation
import ResetRadarApplication
import ResetRadarDomain

public final class FakePreferenceStore: PreferenceStore, @unchecked Sendable {
    private struct State {
        var optIn: [HomeSlot: Bool] = [:]
        var complication = false
    }

    private let state = Locked(State())

    public init() {}

    public func notificationOptIn(_ slot: HomeSlot) async -> Bool? {
        state.withLock { $0.optIn[slot] }
    }

    public func setNotificationOptIn(_ slot: HomeSlot, enabled: Bool) async {
        state.withLock { $0.optIn[slot] = enabled }
    }

    public func complicationEnabled() async -> Bool { state.withLock { $0.complication } }

    public func setComplicationEnabled(_ enabled: Bool) async {
        state.withLock { $0.complication = enabled }
    }
}

/// A bounded claim: held until released or until the clock passes its expiry.
public final class FakeNotificationReconcileGate: NotificationReconcileGate, @unchecked Sendable {
    public static let lease: TimeInterval = 30

    private let clock: any AppClock
    private let held = Locked<GateClaim?>(nil)
    private let claims = Locked(0)

    public init(clock: any AppClock) {
        self.clock = clock
    }

    public var claimCount: Int { claims.snapshot }
    public var isHeld: Bool { held.withLock { $0.map { $0.expiresAt > clock.now } ?? false } }

    public func claim() async -> GateClaim? {
        let now = clock.now
        return held.withLock { current in
            if let existing = current, existing.expiresAt > now { return nil }
            let claim = GateClaim(id: UUID(), expiresAt: now.addingTimeInterval(Self.lease))
            current = claim
            claims.withLock { $0 += 1 }
            return claim
        }
    }

    public func release(_ claim: GateClaim) async {
        held.withLock { current in
            if current?.id == claim.id { current = nil }
        }
    }
}

public final class FakeNotificationScheduler: NotificationScheduler, @unchecked Sendable {
    private struct State {
        var authorization: NotificationAuthorization = .authorized
        var grantOnRequest: NotificationAuthorization = .authorized
        var requests: [HomeSlot: ResetRequest] = [:]
        var authorizationRequests = 0
        var scheduled: [ResetRequest] = []
        var cancelled: [HomeSlot] = []
        var scheduleFailure = false
    }

    private let state = Locked(State())

    public init(authorization: NotificationAuthorization = .authorized) {
        state.withLock { $0.authorization = authorization }
    }

    public var authorizationRequests: Int { state.withLock { $0.authorizationRequests } }
    public var scheduled: [ResetRequest] { state.withLock { $0.scheduled } }
    public var cancelled: [HomeSlot] { state.withLock { $0.cancelled } }
    public var current: [HomeSlot: ResetRequest] { state.withLock { $0.requests } }

    public func setAuthorization(
        _ value: NotificationAuthorization, grantOnRequest: NotificationAuthorization? = nil
    ) {
        state.withLock {
            $0.authorization = value
            if let grantOnRequest { $0.grantOnRequest = grantOnRequest }
        }
    }

    public func failSchedules(_ fail: Bool) { state.withLock { $0.scheduleFailure = fail } }

    public func authorization() async -> NotificationAuthorization {
        state.withLock { $0.authorization }
    }

    public func requestAuthorization() async -> NotificationAuthorization {
        state.withLock { state in
            state.authorizationRequests += 1
            if state.authorization == .notDetermined { state.authorization = state.grantOnRequest }
            return state.authorization
        }
    }

    public func pending() async -> [ResetRequest] {
        state.withLock { Array($0.requests.values) }
    }

    public func schedule(_ request: ResetRequest) async throws {
        try state.withLock { state in
            if state.scheduleFailure { throw FakeStoreError.injected }
            state.requests[request.slot] = request
            state.scheduled.append(request)
        }
    }

    public func cancel(slot: HomeSlot) async {
        state.withLock { state in
            state.requests[slot] = nil
            state.cancelled.append(slot)
        }
    }
}

public final class FakeLiveActivityController: LiveActivityController, @unchecked Sendable {
    public struct Entry: Sendable, Equatable {
        public let content: ActivityContent
        public let staleDate: Date
    }

    private struct State {
        var enabled = true
        var running: [HomeSlot: Entry] = [:]
        var starts: [HomeSlot] = []
        var updates: [HomeSlot] = []
        var ends: [HomeSlot] = []
    }

    private let state = Locked(State())

    public init() {}

    public var starts: [HomeSlot] { state.withLock { $0.starts } }
    public var updates: [HomeSlot] { state.withLock { $0.updates } }
    public var ends: [HomeSlot] { state.withLock { $0.ends } }
    public var running: [HomeSlot: Entry] { state.withLock { $0.running } }

    public func setEnabled(_ enabled: Bool) { state.withLock { $0.enabled = enabled } }

    /// Simulates a running activity the app did not start in this process.
    public func seed(_ slot: HomeSlot, content: ActivityContent, staleDate: Date) {
        state.withLock { $0.running[slot] = Entry(content: content, staleDate: staleDate) }
    }

    /// Simulates the user stopping an activity from the Lock Screen.
    public func userStops(_ slot: HomeSlot) { state.withLock { $0.running[slot] = nil } }

    public func areActivitiesEnabled() async -> Bool { state.withLock { $0.enabled } }

    public func list() async -> [RunningActivity] {
        state.withLock { state in
            state.running.map { RunningActivity(slot: $0.key, windowID: $0.value.content.windowID) }
        }
    }

    public func start(slot: HomeSlot, content: ActivityContent, staleDate: Date) async throws {
        state.withLock { state in
            state.running[slot] = Entry(content: content, staleDate: staleDate)
            state.starts.append(slot)
        }
    }

    public func update(slot: HomeSlot, content: ActivityContent, staleDate: Date) async {
        state.withLock { state in
            state.running[slot] = Entry(content: content, staleDate: staleDate)
            state.updates.append(slot)
        }
    }

    public func end(slot: HomeSlot) async {
        state.withLock { state in
            state.running[slot] = nil
            state.ends.append(slot)
        }
    }
}

public final class FakeWatchLink: WatchLink, @unchecked Sendable {
    private struct State {
        var contexts: [WatchPayload] = []
        var transfers: [WatchPayload] = []
        var contextFailure = false
    }

    private let state = Locked(State())

    public init() {}

    public var contexts: [WatchPayload] { state.withLock { $0.contexts } }
    public var transfers: [WatchPayload] { state.withLock { $0.transfers } }
    public func failContexts(_ fail: Bool) { state.withLock { $0.contextFailure = fail } }

    public func sendContext(_ payload: WatchPayload) async throws {
        try state.withLock { state in
            if state.contextFailure { throw FakeStoreError.injected }
            state.contexts.append(payload)
        }
    }

    public func transferComplication(_ payload: WatchPayload) async throws {
        state.withLock { $0.transfers.append(payload) }
    }
}

public final class FakePhoneLink: PhoneLink, @unchecked Sendable {
    private struct State {
        var reply: WatchPayload?
        var requests = 0
        var receipts: [WatchEraseReceipt] = []
    }

    private let state = Locked(State())

    public init() {}

    public var requestCount: Int { state.withLock { $0.requests } }
    public var receipts: [WatchEraseReceipt] { state.withLock { $0.receipts } }
    public func setReply(_ payload: WatchPayload?) { state.withLock { $0.reply = payload } }

    public func requestRefresh() async -> WatchPayload? {
        state.withLock { state in
            state.requests += 1
            return state.reply
        }
    }

    public func queueReceipt(_ receipt: WatchEraseReceipt) async throws {
        state.withLock { $0.receipts.append(receipt) }
    }
}

public final class FakeSurfaceReloader: SurfaceReloader, @unchecked Sendable {
    private struct Counts {
        var widgets = 0
        var complications = 0
    }

    private let counts = Locked(Counts())

    public init() {}

    public var widgetReloads: Int { counts.withLock { $0.widgets } }
    public var complicationReloads: Int { counts.withLock { $0.complications } }

    public func reloadWidgets() { counts.withLock { $0.widgets += 1 } }
    public func reloadComplications() { counts.withLock { $0.complications += 1 } }
}

public final class FakeDiagnosticsSink: DiagnosticsSink, @unchecked Sendable {
    private let events = Locked<[DiagnosticEvent]>([])

    public init() {}

    public func record(_ event: DiagnosticEvent) async { events.withLock { $0.append(event) } }
    public func history() async -> [DiagnosticEvent] { events.snapshot }
    public var recorded: [DiagnosticEvent] { events.snapshot }
    public func categories() -> [DiagnosticEvent.Category] { recorded.map(\.category) }
}
