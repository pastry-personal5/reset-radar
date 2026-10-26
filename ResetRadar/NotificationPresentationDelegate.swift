import ResetRadarScheduling
import UIKit
@preconcurrency import UserNotifications

@MainActor
final class ResetRadarAppDelegate: NSObject, UIApplicationDelegate {
    private let notificationPresenter = ResetNotificationPresenter()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = notificationPresenter
        return true
    }
}

private final class ResetNotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
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
