@preconcurrency import AppKit
import Darwin
import Foundation
import Network

protocol FirstInstanceActivating: Sendable {
    func activateFirstInstance()
}

struct DistributedFirstInstanceActivator: FirstInstanceActivating {
    let notificationName: Notification.Name

    func activateFirstInstance() {
        DistributedNotificationCenter.default().post(name: notificationName, object: nil)
    }
}

final class SingleInstanceLock: @unchecked Sendable {
    private let fileURL: URL
    private let activator: any FirstInstanceActivating
    private let mutex = NSLock()
    private var descriptor: Int32 = -1

    init(fileURL: URL, activator: any FirstInstanceActivating) {
        self.fileURL = fileURL
        self.activator = activator
    }

    func acquire() -> Bool {
        mutex.withLock {
            guard descriptor < 0 else { return true }
            try? FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let candidate = open(fileURL.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
            guard candidate >= 0 else { return false }
            guard flock(candidate, LOCK_EX | LOCK_NB) == 0 else {
                close(candidate)
                activator.activateFirstInstance()
                return false
            }
            descriptor = candidate
            return true
        }
    }

    func release() {
        mutex.withLock {
            guard descriptor >= 0 else { return }
            _ = flock(descriptor, LOCK_UN)
            close(descriptor)
            descriptor = -1
        }
    }

    deinit { release() }
}

protocol ProcessActivityControlling: Sendable {
    func begin() async -> UUID
    func end(_ token: UUID) async
}

actor SystemProcessActivityController: ProcessActivityControlling {
    private var activities: [UUID: NSObjectProtocol] = [:]

    func begin() -> UUID {
        let id = UUID()
        activities[id] = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Reset Radar collector runtime")
        return id
    }

    func end(_ token: UUID) {
        guard let activity = activities.removeValue(forKey: token) else { return }
        ProcessInfo.processInfo.endActivity(activity)
    }
}

actor AppNapGuard {
    private let controller: any ProcessActivityControlling
    private var token: UUID?

    init(controller: any ProcessActivityControlling) {
        self.controller = controller
    }

    func start() async {
        guard token == nil else { return }
        token = await controller.begin()
    }

    func stop() async {
        guard let token else { return }
        self.token = nil
        await controller.end(token)
    }
}

enum WorkspaceEvent: Sendable {
    case woke
    case sessionActive
    case foreground
    case sleeping
}

protocol WorkspaceEventProviding: Sendable {
    var events: AsyncStream<WorkspaceEvent> { get }
}

final class SystemWorkspaceEvents: WorkspaceEventProviding, @unchecked Sendable {
    let events: AsyncStream<WorkspaceEvent>
    private let continuation: AsyncStream<WorkspaceEvent>.Continuation
    private var observers: [NSObjectProtocol] = []

    init() {
        let pair = AsyncStream<WorkspaceEvent>.makeStream(bufferingPolicy: .bufferingNewest(16))
        events = pair.stream
        continuation = pair.continuation
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(
            workspace.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: nil
            ) { [continuation] _ in continuation.yield(.woke) })
        observers.append(
            workspace.addObserver(
                forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: nil
            ) { [continuation] _ in continuation.yield(.sessionActive) })
        observers.append(
            workspace.addObserver(
                forName: NSWorkspace.willSleepNotification, object: nil, queue: nil
            ) { [continuation] _ in continuation.yield(.sleeping) })
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: nil
            ) { [continuation] _ in continuation.yield(.foreground) })
    }

    deinit {
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        continuation.finish()
    }
}

actor WakeMonitor {
    typealias Handler = @Sendable (WorkspaceEvent) async -> Void
    private let events: any WorkspaceEventProviding
    private let handler: Handler
    private var task: Task<Void, Never>?

    init(events: any WorkspaceEventProviding, handler: @escaping Handler) {
        self.events = events
        self.handler = handler
    }

    func start() {
        guard task == nil else { return }
        task = Task { [events, handler] in
            for await event in events.events { await handler(event) }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}

protocol NetworkPathProviding: Sendable {
    var restored: AsyncStream<Void> { get }
    func start()
    func stop()
}

final class SystemNetworkPathProvider: NetworkPathProviding, @unchecked Sendable {
    let restored: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var sawFailure = false

    init() {
        let pair = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        restored = pair.stream
        continuation = pair.continuation
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let shouldYield = lock.withLock {
                if path.status != .satisfied {
                    sawFailure = true
                    return false
                }
                defer { sawFailure = false }
                return sawFailure
            }
            if shouldYield { continuation.yield() }
        }
    }

    func start() { monitor.start(queue: DispatchQueue(label: "reset-radar.network")) }
    func stop() { monitor.cancel() }
    deinit { continuation.finish() }
}

actor NetworkMonitor {
    private let paths: any NetworkPathProviding
    private let restored: @Sendable () async -> Void
    private var task: Task<Void, Never>?

    init(paths: any NetworkPathProviding, restored: @escaping @Sendable () async -> Void) {
        self.paths = paths
        self.restored = restored
    }

    func start() {
        guard task == nil else { return }
        paths.start()
        task = Task { [paths, restored] in
            for await _ in paths.restored { await restored() }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        paths.stop()
    }
}
