@preconcurrency import AppKit
import ResetRadarScheduling
@preconcurrency import UserNotifications

@MainActor
final class ResetRadarMacAppDelegate: NSObject, NSApplicationDelegate {
    private let notificationPresenter = MacResetNotificationPresenter()

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = notificationPresenter
    }
}

private final class MacResetNotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        guard
            ResetNotificationPresentationPolicy.shouldPresent(
                identifier: notification.request.identifier,
                authorizationStatus: await center.notificationSettings().authorizationStatus)
        else { return [] }
        return [.banner, .sound]
    }
}
