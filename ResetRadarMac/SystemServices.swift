@preconcurrency import AppKit
import Foundation
import ServiceManagement

enum LoginItemState: Sendable, Equatable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable
}

@MainActor
protocol LoginItemManaging: AnyObject {
    var state: LoginItemState { get }
    func setEnabled(_ enabled: Bool) throws
}

@MainActor
final class SystemLoginItemManager: LoginItemManaging {
    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
    }

    var state: LoginItemState {
        switch service.status {
        case .enabled: .enabled
        case .notRegistered: .disabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try service.register()
        } else {
            try service.unregister()
        }
    }
}

@MainActor
final class LoginItemViewModel: ObservableObject {
    @Published private(set) var state: LoginItemState
    @Published private(set) var errorMessage: String?
    private let manager: any LoginItemManaging

    init(manager: any LoginItemManaging) {
        self.manager = manager
        state = manager.state
    }

    var isEnabled: Bool { state == .enabled }

    func refresh() { state = manager.state }

    func setEnabled(_ enabled: Bool) {
        do {
            try manager.setEnabled(enabled)
            errorMessage = nil
        } catch {
            errorMessage =
                "Launch at login could not be changed. Review Login Items in System Settings."
        }
        state = manager.state
    }
}

@MainActor
final class SigningIdentityStateStore {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, development: Bool) {
        self.defaults = defaults
        key = development ? "signing-team.dev" : "signing-team"
    }

    var teamIdentifier: String? { defaults.string(forKey: key) }
    func record(_ teamIdentifier: String) { defaults.set(teamIdentifier, forKey: key) }
    func clear() { defaults.removeObject(forKey: key) }
}

struct FirstInstanceActivationObserver {
    private let observer: NSObjectProtocol

    @MainActor
    init(notificationName: Notification.Name) {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: notificationName, object: nil, queue: .main
        ) { _ in
            NSApplication.shared.activate()
            NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
        }
    }

    func invalidate() {
        DistributedNotificationCenter.default().removeObserver(observer)
    }
}
