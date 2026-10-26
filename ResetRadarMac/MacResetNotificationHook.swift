import Foundation
import ResetRadarApplication

/// Runs the local, device-only reset-notification reconciliation after a collector snapshot
/// commits. It never participates in collection or publication failure handling.
struct MacResetNotificationHook: ResetNotificationHook {
    let reminders: ReconcileResetNotifications

    func snapshotDidCommit() async {
        _ = await reminders.run(onIOS: false)
    }
}
